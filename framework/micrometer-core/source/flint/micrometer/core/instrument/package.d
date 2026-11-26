/*
 * Copyright 2017 VMware, Inc.
 * Copyright 2019 VMware, Inc.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * https://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
// Ported from micrometer-core 1.18.0: micrometer-core/src/main/java/io/micrometer/core/instrument/Tags.java
// Ported from micrometer-core 1.18.0: micrometer-core/src/main/java/io/micrometer/core/instrument/Tag.java
// Ported from micrometer-core 1.18.0: micrometer-core/src/main/java/io/micrometer/core/instrument/ImmutableTag.java
// Ported from micrometer-core 1.18.0: micrometer-core/src/main/java/io/micrometer/core/instrument/Meter.java
// Ported from micrometer-core 1.18.0: micrometer-core/src/main/java/io/micrometer/core/instrument/Statistic.java
// Ported from micrometer-core 1.18.0: micrometer-core/src/main/java/io/micrometer/core/instrument/MeterRegistry.java
// Ported from micrometer-core 1.18.0: micrometer-core/src/main/java/io/micrometer/core/instrument/Counter.java
// Ported from micrometer-core 1.18.0: micrometer-core/src/main/java/io/micrometer/core/instrument/Measurement.java
// Ported from micrometer-core 1.18.0: micrometer-core/src/main/java/io/micrometer/core/instrument/Clock.java
// Ported from micrometer-core 1.18.0: micrometer-core/src/main/java/io/micrometer/core/instrument/MockClock.java
// Ported from micrometer-core 1.18.0: micrometer-core/src/main/java/io/micrometer/core/instrument/Timer.java
// Ported from micrometer-core 1.18.0: micrometer-core/src/main/java/io/micrometer/core/instrument/noop/NoopTimer.java
// Modified by the Flint authors.
module flint.micrometer.core.instrument;

import core.sync.mutex : Mutex;
import core.time : MonoTime, ticksToNSecs;
import flint.engine.aot.clock : currentTimeMillis;
import flint.engine.aot.objects : objectToString, statelessInstance;
import flint.engine.aot.text : decodeUtf8;
import flint.java.lang : ArithmeticException, Comparable, IllegalArgumentException, Iterable, JavaObject,
    NullPointerException, UnsupportedOperationException, javaEquals, javaHashCode, stringHashCode, valueOf;
import flint.java.time : Duration;
import flint.java.util.concurrent : TimeUnit, toMillis, toNanos;
import flint.java.util : Iterator, List, NoSuchElementException, stableSort;
import flint.java.util.function_ : Consumer, DoubleSupplier, Supplier;
import flint.java.util.stream : Stream;
import std.typecons : Nullable;

@safe:

private alias NullableString = Nullable!string;
private alias TagIterable = Iterable!Tag;
private alias MeasurementIterable = Iterable!Measurement;

/// Sources of epoch milliseconds and monotonic nanoseconds.
interface Clock
{
    /// The shared clock for readings from the system.
    static @property Clock SYSTEM() nothrow @nogc
    {
        return statelessInstance!SystemClock();
    }

    /// Current time in milliseconds since the Unix epoch.
    long wallTime() nothrow @nogc;

    /// Monotonic time in nanoseconds from a fixed origin.
    long monotonicTime() nothrow @nogc;
}

private final class SystemClock : Clock
{
    override long wallTime() nothrow @nogc
    {
        return currentTimeMillis();
    }

    override long monotonicTime() nothrow @nogc
    {
        return ticksToNSecs(MonoTime.currTime.ticks);
    }
}

/// A clock controlled by its caller, for deterministic metric tests.
class MockClock : Clock
{
    private long timeNanos = 1_000_000;

    override long monotonicTime() nothrow @nogc
    {
        return timeNanos;
    }

    override long wallTime() nothrow @nogc
    {
        return TimeUnit.NANOSECONDS.toMillis(timeNanos);
    }

    /// Advance the clock and return the new monotonic time.
    long add(long amount, TimeUnit unit) nothrow @nogc
    {
        timeNanos += unit.toNanos(amount);
        return timeNanos;
    }

    /// Advance the clock by a Java duration.
    long add(Duration duration)
    {
        return add(checkedNanos(duration), TimeUnit.NANOSECONDS);
    }

    /// Advance the clock by a number of seconds.
    long addSeconds(long amount) nothrow @nogc
    {
        return add(amount, TimeUnit.SECONDS);
    }
}

private long checkedNanos(Duration duration)
{
    if (duration.compareTo(Duration.ofNanos(long.min)) < 0 || duration.compareTo(Duration.ofNanos(long.max)) > 0)
        throw new ArithmeticException("Duration exceeds a signed nanosecond count");
    return duration.toNanos();
}

/// One key/value dimension of a meter (R1, R3, R6).
interface Tag : Comparable!Tag
{
    string getKey();
    string getValue();

    /// Create an immutable tag.
    static Tag of(string key, string value)
    {
        return new ImmutableTag(key, value);
    }

    /// Compare tags by key, as in Java's default method (R3).
    mixin template Defaults()
    {
        override int compareTo(Tag other)
        {
            if (other is null)
                throw new NullPointerException("tag");
            return compareKeys(getKey(), other.getKey());
        }
    }
}

// Java's String.compareTo returns the first differing UTF-16 code units' difference or the length difference.
private int compareKeys(scope const(char)[] left, scope const(char)[] right) pure nothrow @nogc
{
    size_t i, j;
    while (i < left.length && j < right.length)
    {
        const a = decodeUtf8(left, i);
        const b = decodeUtf8(right, j);
        if (a != b)
        {
            const difference = firstUnit(a) - firstUnit(b);
            // An equal leading surrogate leaves only the difference in the trailing units.
            return difference != 0 ? difference : cast(int) a - cast(int) b;
        }
    }
    return utf16Length(left[i .. $]) - utf16Length(right[j .. $]);
}

private int firstUnit(dchar scalar) pure nothrow @nogc
{
    return scalar < 0x10000 ? cast(int) scalar : 0xD800 + (cast(int) scalar - 0x10000) / 1024;
}

private int utf16Length(scope const(char)[] input) pure nothrow @nogc
{
    size_t position;
    int units;
    while (position < input.length)
        units += decodeUtf8(input, position) < 0x10000 ? 1 : 2;
    return units;
}

/// Immutable key/value pair (R11).
class ImmutableTag : Tag
{
    private immutable string key;
    private immutable string value;

    /// Store the non-null key and value.
    this(string key, string value)
    {
        if (key is null || value is null)
            throw new NullPointerException("tag key and value must be non-null");
        this.key = key;
        this.value = value;
    }

    override string getKey() nothrow @nogc
    {
        return key;
    }

    override string getValue() nothrow @nogc
    {
        return value;
    }

    /// Compare the key and value of two immutable tags.
    bool equals(Object other)
    {
        auto tag = cast(ImmutableTag) other;
        return this is tag || (tag !is null && key == tag.getKey() && value == tag.getValue());
    }

    /// Hash the key and value using Java's string hash.
    int hashCode() nothrow @nogc
    {
        return 31 * stringHashCode(key) + stringHashCode(value);
    }

    /// Format this dimension as `tag(key=value)`.
    override string toString() const
    {
        return "tag(" ~ key ~ "=" ~ value ~ ")";
    }

    mixin Tag.Defaults;
    mixin JavaObject;
}

/// Immutable tags in key order. Later instances of a key replace earlier ones.
abstract class Tags : TagIterable
{
    // Only this module constructs Tags. EmptyTags uses the existing stateless Java singleton path.
    private this() nothrow @nogc
    {
    }

    protected abstract Tag[] entries() nothrow @nogc;

    /// Return the shared empty set.
    static Tags empty() nothrow @nogc
    {
        return statelessInstance!EmptyTags();
    }

    /// Normalize the contents of an iterable.
    static Tags of(TagIterable tags)
    {
        if (tags is null)
            return empty();
        if (auto existing = cast(Tags) tags)
            return existing;
        Tag[] items;
        foreach (tag; tags)
            items ~= requireTag(tag);
        return fromOwned(items);
    }

    /// Create a set holding one dimension.
    static Tags of(string key, string value)
    {
        return new StoredTags([Tag.of(key, value)]);
    }

    /// Create a set from alternating keys and values.
    static Tags of(scope const(string)[] keyValues...)
    {
        if (keyValues.length == 0 || (keyValues.length == 1 && keyValues[0] is null))
            return empty();
        if (keyValues.length % 2 != 0)
            throw new IllegalArgumentException("size must be even, it is a set of key=value pairs");

        auto items = new Tag[keyValues.length / 2];
        foreach (index, ref item; items)
            item = Tag.of(keyValues[index * 2], keyValues[index * 2 + 1]);
        return fromOwned(items);
    }

    /// Normalize a sequence of tag objects.
    static Tags of(scope Tag[] tags...)
    {
        if (tags.length == 0 || (tags.length == 1 && tags[0] is null))
            return empty();
        auto items = new Tag[tags.length];
        foreach (index, tag; tags)
            items[index] = requireTag(tag);
        return fromOwned(items);
    }

    /// Merge two iterables. The second supplies the value of any repeated key.
    static Tags concat(TagIterable tags, TagIterable otherTags)
    {
        return of(tags).and(otherTags);
    }

    /// Merge an iterable with alternating keys and values.
    static Tags concat(TagIterable tags, scope const(string)[] keyValues...)
    {
        return of(tags).and(keyValues);
    }

    /// Merge this set with the given iterable.
    final Tags and(TagIterable tags)
    {
        return merge(of(tags));
    }

    /// Add or replace one dimension.
    final Tags and(string key, string value)
    {
        return merge(of(key, value));
    }

    /// Merge additional key/value pairs.
    final Tags and(scope const(string)[] keyValues...)
    {
        return merge(of(keyValues));
    }

    /// Merge additional tag objects.
    final Tags and(scope Tag[] tags...)
    {
        return merge(of(tags));
    }

    final override Iterator!Tag iterator()
    {
        return new TagsIterator(entries());
    }

    final override void forEach(void delegate(Tag) @safe action)
    {
        foreach (item; entries())
            action(item);
    }

    final override int opApply(scope int delegate(Tag) @safe visit)
    {
        foreach (item; entries())
        {
            if (const result = visit(item))
                return result;
        }
        return 0;
    }

    /// Stream the dimensions in key order.
    final Stream!Tag stream()
    {
        // Both the array and its entries stay owned by this collection.
        return Stream!Tag.ofArray(entries());
    }

    /// Compare normalized keys and values in order.
    final bool equals(Object other)
    {
        auto tags = cast(Tags) other;
        if (this is tags)
            return true;
        if (tags is null)
            return false;
        auto left = entries();
        auto right = tags.entries();
        if (left.length != right.length)
            return false;
        foreach (index, item; left)
        {
            if (!javaEquals(item, right[index]))
                return false;
        }
        return true;
    }

    /// Hash the tags in key order.
    final int hashCode()
    {
        int result = 1;
        foreach (item; entries())
            result = 31 * result + javaHashCode(item);
        return result;
    }

    /// Format the tags in key order.
    abstract override string toString() const;

    mixin JavaObject;

    private Tags merge(Tags other)
    {
        auto first = entries();
        auto second = other.entries();
        const left = first.length;
        const right = second.length;
        if (right == 0 || equals(other))
            return this;
        if (left == 0)
            return other;

        auto output = new Tag[left + right];
        size_t i, j, length;
        while (i < left && j < right)
        {
            const order = first[i].compareTo(second[j]);
            if (order < 0)
                output[length++] = first[i++];
            else
            {
                output[length++] = second[j++];
                if (order == 0)
                    i++;
            }
        }
        output[length .. length + left - i] = first[i .. $];
        length += left - i;
        output[length .. length + right - j] = second[j .. $];
        return new StoredTags(output[0 .. length + right - j]);
    }

    private static Tag requireTag(Tag tag)
    {
        if (tag is null)
            throw new NullPointerException("tag");
        return tag;
    }

    private static Tags fromOwned(Tag[] items)
    {
        if (items.length == 0)
            return empty();
        foreach (index; 1 .. items.length)
        {
            if (items[index - 1].compareTo(items[index]) >= 0)
            {
                stableSort!Tag(items, (a, b) => a.compareTo(b));
                break;
            }
        }
        size_t length;
        foreach (index; 1 .. items.length)
        {
            if (items[index - 1].getKey() != items[index].getKey())
                items[length++] = items[index - 1];
        }
        items[length++] = items[$ - 1];
        items[length .. $] = null;
        return new StoredTags(items[0 .. length]);
    }
}

private final class EmptyTags : Tags
{
    override string toString() const
    {
        return "[]";
    }

    protected override Tag[] entries() nothrow @nogc
    {
        return null;
    }
}

private final class StoredTags : Tags
{
    private Tag[] items;
    // A Java Tag may provide its own Object.toString. The callback renders those tags without changing this set.
    private string delegate() @safe format;

    this(Tag[] items) nothrow @nogc
    {
        this.items = items;
        format = &formatTags;
    }

    override string toString() const
    {
        return format();
    }

    private string formatTags()
    {
        char[] output = "[".dup;
        foreach (index, item; items)
        {
            if (index != 0)
                output ~= ',';
            output ~= objectToString(cast(Object) item);
        }
        output ~= ']';
        return output.idup;
    }

    protected override Tag[] entries() nothrow @nogc
    {
        return items;
    }
}

private final class TagsIterator : Iterator!Tag
{
    private Tag[] remaining;

    this(Tag[] items) nothrow @nogc
    {
        remaining = items;
    }

    override bool hasNext() nothrow @nogc
    {
        return remaining.length != 0;
    }

    override Tag next()
    {
        if (!hasNext())
            throw new NoSuchElementException("no more tags");
        auto item = remaining[0];
        remaining = remaining[1 .. $];
        return item;
    }

    override void remove()
    {
        throw new UnsupportedOperationException("cannot remove items from tags");
    }
}

/// The meaning of a meter measurement.
struct Statistic
{
    private ubyte ordinal;

    private this(ubyte ordinal) pure nothrow @nogc
    {
        this.ordinal = ordinal;
    }

    /// Unspecified measurement.
    enum UNKNOWN = Statistic(0);
    /// Sum of recorded amounts.
    enum TOTAL = Statistic(1);
    /// Sum of recorded durations.
    enum TOTAL_TIME = Statistic(2);
    /// Number of recorded samples.
    enum COUNT = Statistic(3);
    /// Maximum recorded sample.
    enum MAX = Statistic(4);
    /// Instantaneous value.
    enum VALUE = Statistic(5);
    /// Number of ongoing tasks.
    enum ACTIVE_TASKS = Statistic(6);
    /// Duration of a running task.
    enum DURATION = Statistic(7);

    /// The associated value of the "statistic" tag.
    string getTagValueRepresentation() const pure nothrow @nogc
    {
        static immutable string[8] names = [
            "unknown", "total", "total", "count", "max", "value", "active", "duration"
        ];
        return names[ordinal];
    }
}

/// A reading of a statistic supplied by a meter.
class Measurement
{
    private double delegate() @safe sample;
    private immutable Statistic statistic;

    /// Read the statistic through a primitive-double supplier.
    this(DoubleSupplier valueFunction, Statistic statistic)
    {
        this(&valueFunction.getAsDouble, statistic);
    }

    /// Read the statistic through a boxed Java supplier.
    this(Supplier!double valueFunction, Statistic statistic)
    {
        this(&valueFunction.get, statistic);
    }

    /// Read the statistic through a D delegate (R9).
    this(double delegate() @safe valueFunction, Statistic statistic)
    {
        sample = valueFunction;
        this.statistic = statistic;
    }

    /// Sample the current value.
    double getValue() const
    {
        return sample();
    }

    /// The meaning of the sampled value.
    Statistic getStatistic() const nothrow @nogc
    {
        return statistic;
    }

    /// Render the statistic and current value.
    override string toString() const
    {
        static immutable string[8] names = [
            "UNKNOWN", "TOTAL", "TOTAL_TIME", "COUNT", "MAX", "VALUE", "ACTIVE_TASKS", "DURATION"
        ];
        return "Measurement{statistic='" ~ names[statistic.ordinal] ~ "', value=" ~ valueOf(getValue()) ~ "}";
    }
}

/// A named source of measurements.
interface Meter
{
    /// The meter's registered identity.
    Id getId();

    /// Measurements sampled from this meter.
    MeasurementIterable measure();

    /// The kind of measurements the meter reports.
    enum Type : ubyte
    {
        COUNTER,
        GAUGE,
        LONG_TASK_TIMER,
        TIMER,
        DISTRIBUTION_SUMMARY,
        OTHER,
    }

    /// An identity consists of the meter name and normalized tags.
    static class Id
    {
        private immutable string name;
        private Tags tags;
        private NullableString baseUnit;
        private NullableString description;
        private Type type;

        /// The name and tags identify the meter. Unit, description and type describe it.
        this(string name, Tags tags, NullableString baseUnit, NullableString description, Type type)
        {
            this.name = name;
            this.tags = tags;
            this.baseUnit = baseUnit;
            this.description = description;
            this.type = type;
        }

        /// Copy the description and tags to an ID with a different name.
        Id withName(string newName)
        {
            return new Id(newName, tags, baseUnit, description, type);
        }

        /// Return an ID with an added or replaced dimension.
        Id withTag(Tag tag)
        {
            return new Id(name, tags.and(tag), baseUnit, description, type);
        }

        /// Return an ID with the given statistic tag.
        Id withTag(Statistic statistic)
        {
            return new Id(name, tags.and("statistic", statistic.getTagValueRepresentation()),
                    baseUnit, description, type);
        }

        /// Return an ID with the supplied dimensions merged into the current ones.
        Id withTags(TagIterable extraTags)
        {
            return new Id(name, tags.and(extraTags), baseUnit, description, type);
        }

        /// Return an ID whose only dimensions are the supplied tags.
        Id replaceTags(TagIterable replacement)
        {
            return new Id(name, Tags.of(replacement), baseUnit, description, type);
        }

        /// Return an ID for the same meter with a different base unit.
        Id withBaseUnit(NullableString newBaseUnit)
        {
            return new Id(name, tags, newBaseUnit, description, type);
        }

        /// The meter's name.
        string getName() const pure nothrow @nogc
        {
            return name;
        }

        /// The meter's dimensions as an unmodifiable list.
        List!Tag getTags()
        {
            return List!Tag.of(tags.entries());
        }

        /// The meter's dimensions in key order.
        TagIterable getTagsAsIterable() nothrow @nogc
        {
            return tags;
        }

        /// The value of the named dimension, or null if absent.
        NullableString getTag(string key)
        {
            if (key is null)
                return NullableString.init;
            foreach (tag; tags.entries())
            {
                if (tag.getKey() == key)
                    return NullableString(tag.getValue());
            }
            return NullableString.init;
        }

        /// The meter's base unit, if set.
        NullableString getBaseUnit() const pure nothrow @nogc
        {
            return baseUnit;
        }

        /// The meter's description, if set.
        NullableString getDescription() const pure nothrow @nogc
        {
            return description;
        }

        /// How the registry exposes this meter.
        Type getType() const pure nothrow @nogc
        {
            return type;
        }

        /// Compare by meter name and tags.
        bool equals(Object other)
        {
            auto id = cast(Id) other;
            return this is id || (id !is null && name == id.name && tags.equals(id.tags));
        }

        /// Hash the meter name and tags.
        int hashCode()
        {
            return 31 * stringHashCode(name) + tags.hashCode();
        }

        /// Format the meter's identity for diagnostics.
        override string toString() const
        {
            return "MeterId{name='" ~ name ~ "', tags=" ~ tags.toString() ~ "}";
        }

        mixin JavaObject;
    }
}

/// A counter preallocated during meter registration.
interface Counter : Meter
{
    /// Configure a counter before registering it.
    static Builder builder(string name)
    {
        return Builder(name);
    }

    /// Register a counter with a name, dimensions and optional metadata.
    static struct Builder
    {
        private string name;
        private Tags dimensions;
        private NullableString description_;
        private NullableString baseUnit_;

        private this(string name)
        {
            this.name = name;
            dimensions = Tags.empty();
        }

        /// Add alternating tag keys and values.
        ref Builder tags(scope const(string)[] keyValues...) return
        {
            dimensions = dimensions.and(keyValues);
            return this;
        }

        /// Add dimensions. Later entries override the same key.
        ref Builder tags(TagIterable tags) return
        {
            dimensions = dimensions.and(tags);
            return this;
        }

        /// Add or replace one dimension.
        ref Builder tag(string key, string value) return
        {
            dimensions = dimensions.and(key, value);
            return this;
        }

        /// Set the description of the registered meter.
        ref Builder description(NullableString description) return
        {
            description_ = description;
            return this;
        }

        /// Set the base unit of the registered meter.
        ref Builder baseUnit(NullableString baseUnit) return
        {
            baseUnit_ = baseUnit;
            return this;
        }

        /// Register the counter and return its retained handle.
        Counter register(MeterRegistry registry)
        {
            auto id = new Meter.Id(name, dimensions, baseUnit_, description_, Type.COUNTER);
            return registry.counter(id);
        }
    }

    /// Add one to this counter.
    void increment() nothrow @nogc;

    /// Add an amount to this counter.
    void increment(double amount) nothrow @nogc;

    /// The total since this counter was created.
    double count() nothrow @nogc;

    private static MeasurementIterable countMeasurement(Counter counter)
    {
        return new CounterMeasurement(counter);
    }

    /// Micrometer's default increment and count measurement (R3).
    mixin template Defaults(alias Measurements = MeasurementIterable, alias countSample = countMeasurement)
    {
        override void increment() nothrow @nogc
        {
            Counter counter = this;
            counter.increment(1.0);
        }

        override Measurements measure()
        {
            return countSample(this);
        }
    }
}

/// Count recorded durations and report their total and recent maximum.
interface Timer : Meter
{
    /// Start a sample using the system clock.
    static Sample start()
    {
        return start(Clock.SYSTEM);
    }

    /// Start a sample using the given clock.
    static Sample start(Clock clock)
    {
        return new Sample(clock);
    }

    /// Capture the start time before choosing the timer that will receive it.
    static class Sample
    {
        private Clock clock;
        private immutable long startTime;

        private this(Clock clock)
        {
            if (clock is null)
                throw new NullPointerException("clock");
            this.clock = clock;
            startTime = clock.monotonicTime();
        }

        /// Record and return the elapsed time in nanoseconds.
        long stop(Timer timer)
        {
            const elapsed = clock.monotonicTime() - startTime;
            if (timer is null)
                throw new NullPointerException("timer");
            timer.record(elapsed, TimeUnit.NANOSECONDS);
            return elapsed;
        }
    }

    /// Configure a timer before registering it.
    static Builder builder(string name)
    {
        return Builder(name);
    }

    /// Register a timer with a name, dimensions and optional description.
    static struct Builder
    {
        private string name;
        private Tags dimensions;
        private NullableString description_;

        private this(string name)
        {
            this.name = name;
            dimensions = Tags.empty();
        }

        /// Add alternating tag keys and values.
        ref Builder tags(scope const(string)[] keyValues...) return
        {
            dimensions = dimensions.and(keyValues);
            return this;
        }

        /// Add dimensions. Later entries override the same key.
        ref Builder tags(TagIterable tags) return
        {
            dimensions = dimensions.and(tags);
            return this;
        }

        /// Add or replace one dimension.
        ref Builder tag(string key, string value) return
        {
            dimensions = dimensions.and(key, value);
            return this;
        }

        /// Set the description of the registered timer.
        ref Builder description(NullableString description) return
        {
            description_ = description;
            return this;
        }

        /// Register the timer using the registry's base time unit.
        Timer register(MeterRegistry registry)
        {
            return registry.timer(new Meter.Id(name, dimensions, NullableString.init, description_, Type.TIMER));
        }
    }

    /// Record an event. Negative durations are ignored.
    void record(long amount, TimeUnit unit) nothrow @nogc;

    /// Record an event with a duration representable as signed nanoseconds.
    void record(Duration duration);

    /// The number of recorded events.
    long count() nothrow @nogc;

    /// The sum of recorded durations in the requested unit.
    double totalTime(TimeUnit unit) nothrow @nogc;

    /// The mean of recorded durations in the requested unit.
    double mean(TimeUnit unit) nothrow @nogc;

    /// The maximum duration in the current window in the requested unit.
    double max(TimeUnit unit) nothrow @nogc;

    /// The time unit used for published measurements.
    TimeUnit baseTimeUnit() nothrow @nogc;

    private static MeasurementIterable timerMeasurements(Timer timer)
    {
        return new TimerMeasurements(timer);
    }

    /// Micrometer's default duration conversion, mean and live measurements (R3).
    mixin template Defaults(alias Measurements = MeasurementIterable, alias samples = timerMeasurements,
            alias DurationType = Duration, alias Unit = TimeUnit, alias nanos = checkedNanos)
    {
        override void record(DurationType duration)
        {
            Timer timer = this;
            timer.record(nanos(duration), Unit.NANOSECONDS);
        }

        override double mean(Unit unit) nothrow @nogc
        {
            Timer timer = this;
            const events = timer.count();
            return events == 0 ? 0.0 : timer.totalTime(unit) / events;
        }

        override Measurements measure()
        {
            return samples(this);
        }
    }
}

/// Register meters by name and tags before handing their handles to request code.
abstract class MeterRegistry
{
    private Meter[] meters;
    private Mutex gate;
    private Timer function(Meter.Id) @safe timerFactory;
    private bool closed;

    /// Prepare empty registry storage.
    protected this()
    {
        this(null);
    }

    package this(Timer function(Meter.Id) @safe timerFactory)
    {
        gate = new Mutex;
        this.timerFactory = timerFactory;
    }

    /// Find or register a counter with the given name and tag pairs.
    Counter counter(string name, scope const(string)[] tags...)
    {
        return counter(name, Tags.of(tags));
    }

    /// Find or register a counter with the given name and tag iterable.
    Counter counter(string name, TagIterable tags)
    {
        return counter(name, Tags.of(tags));
    }

    /// Find or register a counter with the given name and normalized tags.
    Counter counter(string name, Tags tags)
    {
        if (tags is null)
            tags = Tags.empty();
        return counter(new Meter.Id(name, tags, NullableString.init, NullableString.init, Meter.Type.COUNTER));
    }

    private Counter counter(Meter.Id id)
    {
        return cast(Counter) registerMeter(id);
    }

    /// Find or register a timer with the given name and tag pairs.
    Timer timer(string name, scope const(string)[] tags...)
    {
        return timer(name, Tags.of(tags));
    }

    /// Find or register a timer with the given name and tag iterable.
    Timer timer(string name, TagIterable tags)
    {
        return timer(name, Tags.of(tags));
    }

    /// Find or register a timer with the given name and normalized tags.
    Timer timer(string name, Tags tags)
    {
        if (tags is null)
            tags = Tags.empty();
        return timer(new Meter.Id(name, tags, NullableString.init, NullableString.init, Meter.Type.TIMER));
    }

    private Timer timer(Meter.Id id)
    {
        return cast(Timer) registerMeter(id);
    }

    private Meter registerMeter(Meter.Id id)
    {
        const registeringTimer = id.getType() == Meter.Type.TIMER;
        gate.lock_nothrow();
        scope (exit)
            gate.unlock_nothrow();

        foreach (meter; meters)
        {
            if (!id.equals(meter.getId()))
                continue;
            if (registeringTimer ? cast(Timer) meter is null : cast(Counter) meter is null)
            {
                const conflict = registeringTimer ? "CumulativeCounter vs. Timer" : "CumulativeTimer vs. Counter";
                throw new IllegalArgumentException("There is already a registered meter of a different type ("
                        ~ conflict ~ ") with the same name: " ~ id.getName());
            }
            return meter;
        }

        if (closed)
        {
            if (registeringTimer)
                return new NoopTimer(id);
            return new NoopCounter(id);
        }
        Meter created;
        if (registeringTimer)
        {
            if (timerFactory is null)
                throw new UnsupportedOperationException("This registry does not provide timers");
            created = timerFactory(id);
        }
        else
            created = newCounter(id);
        meters ~= created;
        return created;
    }

    /// Build the concrete registry's counter.
    protected abstract Counter newCounter(Meter.Id id);

    /// Visit a snapshot of the registered meters.
    void forEachMeter(Consumer!Meter action)
    {
        forEachMeter(&action.accept);
    }

    /// Visit registered meters using a D delegate (R9).
    void forEachMeter(scope void delegate(Meter) @safe action)
    {
        foreach (meter; snapshot())
            action(meter);
    }

    private Meter[] snapshot()
    {
        gate.lock_nothrow();
        scope (exit)
            gate.unlock_nothrow();
        return meters.dup;
    }

    /// Remove the meter whose identity matches this meter.
    Meter remove(Meter meter)
    {
        return remove(meter.getId());
    }

    /// Return the removed meter, or null when no meter has the requested identity.
    Meter remove(Meter.Id id)
    {
        gate.lock_nothrow();
        scope (exit)
            gate.unlock_nothrow();

        foreach (index, meter; meters)
        {
            if (id.equals(meter.getId()))
            {
                foreach (position; index + 1 .. meters.length)
                    meters[position - 1] = meters[position];
                meters[$ - 1] = null;
                meters = meters[0 .. $ - 1];
                return meter;
            }
        }
        return null;
    }

    /// Remove all registered meters.
    void clear()
    {
        gate.lock_nothrow();
        scope (exit)
            gate.unlock_nothrow();
        meters = null;
    }

    /// Stop admitting new meters. Existing handles remain usable.
    void close()
    {
        gate.lock_nothrow();
        scope (exit)
            gate.unlock_nothrow();
        closed = true;
    }

    /// Whether new identities are denied.
    bool isClosed() nothrow @nogc
    {
        gate.lock_nothrow();
        scope (exit)
            gate.unlock_nothrow();
        return closed;
    }
}

private final class NoopCounter : Counter
{
    private Meter.Id id;

    this(Meter.Id id) nothrow @nogc
    {
        this.id = id;
    }

    override Meter.Id getId() nothrow @nogc
    {
        return id;
    }

    override void increment(double) nothrow @nogc
    {
    }

    override double count() nothrow @nogc
    {
        return 0.0;
    }

    mixin Counter.Defaults;
}

private final class NoopTimer : Timer, MeasurementIterable
{
    private Meter.Id id;

    this(Meter.Id id) nothrow @nogc
    {
        this.id = id;
    }

    override Meter.Id getId() nothrow @nogc
    {
        return id;
    }

    override void record(long, TimeUnit) nothrow @nogc
    {
    }

    override long count() nothrow @nogc
    {
        return 0;
    }

    override double totalTime(TimeUnit) nothrow @nogc
    {
        return 0.0;
    }

    override double max(TimeUnit) nothrow @nogc
    {
        return 0.0;
    }

    override TimeUnit baseTimeUnit() nothrow @nogc
    {
        return TimeUnit.SECONDS;
    }

    override MeasurementIterable measure()
    {
        return this;
    }

    override Iterator!Measurement iterator()
    {
        return new MeasurementIterator(null);
    }

    override void forEach(void delegate(Measurement) @safe)
    {
    }

    override int opApply(scope int delegate(Measurement) @safe)
    {
        return 0;
    }

    mixin Timer.Defaults;
}

private final class CounterMeasurement : Measurement, MeasurementIterable
{
    this(Counter counter)
    {
        super(&counter.count, Statistic.COUNT);
    }

    override Iterator!Measurement iterator()
    {
        return new MeasurementIterator(this);
    }

    override void forEach(void delegate(Measurement) @safe action)
    {
        action(this);
    }

    override int opApply(scope int delegate(Measurement) @safe visit)
    {
        return visit(this);
    }
}

private final class TimerMeasurements : MeasurementIterable
{
    private Timer timer;
    private Measurement[3] measurements;

    this(Timer timer)
    {
        this.timer = timer;
        measurements[0] = new Measurement(&count, Statistic.COUNT);
        measurements[1] = new Measurement(&total, Statistic.TOTAL_TIME);
        measurements[2] = new Measurement(&maximum, Statistic.MAX);
    }

    private double count() nothrow @nogc
    {
        return cast(double) timer.count();
    }

    private double total() nothrow @nogc
    {
        return timer.totalTime(timer.baseTimeUnit());
    }

    private double maximum() nothrow @nogc
    {
        return timer.max(timer.baseTimeUnit());
    }

    override Iterator!Measurement iterator()
    {
        return new MeasurementIterator(measurements[0], measurements[1], measurements[2]);
    }

    override void forEach(void delegate(Measurement) @safe action)
    {
        foreach (sample; measurements)
            action(sample);
    }

    override int opApply(scope int delegate(Measurement) @safe visit)
    {
        foreach (sample; measurements)
            if (const result = visit(sample))
                return result;
        return 0;
    }
}

private final class MeasurementIterator : Iterator!Measurement
{
    private Measurement first;
    private Measurement second;
    private Measurement third;

    this(Measurement first, Measurement second = null, Measurement third = null) nothrow @nogc
    {
        this.first = first;
        this.second = second;
        this.third = third;
    }

    override bool hasNext() nothrow @nogc
    {
        return first !is null;
    }

    override Measurement next()
    {
        if (!hasNext())
            throw new NoSuchElementException("no more measurements");
        auto current = first;
        first = second;
        second = third;
        third = null;
        return current;
    }

    override void remove()
    {
        throw new UnsupportedOperationException("cannot remove measurements");
    }
}
