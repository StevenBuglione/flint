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
// Ported from micrometer-core 1.18.0: micrometer-core/src/main/java/io/micrometer/core/instrument/DistributionSummary.java
// Ported from micrometer-core 1.18.0: micrometer-core/src/main/java/io/micrometer/core/instrument/noop/NoopDistributionSummary.java
// Ported from micrometer-core 1.18.0: micrometer-core/src/main/java/io/micrometer/core/instrument/distribution/HistogramSupport.java
// Ported from micrometer-core 1.18.0: micrometer-core/src/main/java/io/micrometer/core/instrument/noop/NoopTimer.java
// Ported from micrometer-core 1.18.0: micrometer-core/src/main/java/io/micrometer/core/instrument/noop/NoopMeter.java
// Ported from micrometer-core 1.18.0: micrometer-core/src/main/java/io/micrometer/core/instrument/Gauge.java
// Ported from micrometer-core 1.18.0: micrometer-core/src/main/java/io/micrometer/core/instrument/AbstractMeter.java
// Ported from micrometer-core 1.18.0: micrometer-core/src/main/java/io/micrometer/core/instrument/util/MeterEquivalence.java
// Modified by the Flint authors.
module flint.micrometer.core.instrument;

import core.sync.mutex : Mutex;
import core.time : MonoTime, ticksToNSecs;
import flint.engine.aot.clock : currentTimeMillis;
import flint.engine.aot.objects : objectToString, statelessInstance;
import flint.engine.aot.text : decodeUtf8;
import flint.java.lang : ClassCastException, Comparable, IllegalArgumentException, Iterable, JavaObject,
    NullPointerException, Runnable, UnsupportedOperationException, javaEquals, javaHashCode, stringHashCode, valueOf;
import flint.java.time : Duration;
import flint.java.util.concurrent : TimeUnit, toMillis, toNanos;
import flint.java.util.concurrent.callable : Callable;
import flint.java.util : Iterator, List, NoSuchElementException, stableSort;
import flint.java.util.function_ : BooleanSupplier, Consumer, DoubleSupplier, Supplier;
import flint.java.util.stream : Stream;
import flint.micrometer.core.instrument.config : validateDistributionBufferLength;
import flint.micrometer.core.instrument.distribution.snapshots : HistogramSnapshot;
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
        return add(duration.toNanos(), TimeUnit.NANOSECONDS);
    }

    /// Advance the clock by a number of seconds.
    long addSeconds(long amount) nothrow @nogc
    {
        return add(amount, TimeUnit.SECONDS);
    }

    /// Return the registry clock as a mock clock.
    static MockClock clock(MeterRegistry registry)
    {
        if (auto clock = MeterRegistry.clockOf(registry))
        {
            if (auto mock = cast(MockClock) clock)
                return mock;
            throw new ClassCastException("the registry clock is not a MockClock");
        }
        return null;
    }
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

/// Base class for meters that retain an ID and compare by that ID.
abstract class AbstractMeter : Meter
{
    private Meter.Id id;

    /// Retain the meter's registered ID.
    this(Meter.Id id)
    {
        this.id = id;
    }

    override Meter.Id getId()
    {
        return id;
    }

    /// Compare with another meter by ID.
    bool equals(Object other)
    {
        return metersEqual(this, other);
    }

    /// Hash the meter's ID.
    int hashCode()
    {
        return meterHashCode(this);
    }

    mixin JavaObject;
}

// Keep the shared implementation beside Meter so the utility module depends on instrument in one direction.
package bool metersEqual(Meter meter, Object other)
{
    auto otherMeter = cast(Meter) other;
    if (meter is null || otherMeter is null)
        return false;
    if (meter is otherMeter)
        return true;

    auto id = meter.getId();
    auto otherId = otherMeter.getId();
    if (id is null)
        throw new NullPointerException("meter id");
    return id.equals(otherId);
}

package int meterHashCode(Meter meter)
{
    if (meter is null)
        throw new NullPointerException("meter");
    auto id = meter.getId();
    if (id is null)
        throw new NullPointerException("meter id");
    return id.hashCode();
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
        return new SingleMeasurement(&counter.count, Statistic.COUNT);
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

/// A meter that samples an instantaneous value.
interface Gauge : Meter
{
    /// Sample the current value.
    double value();

    private static MeasurementIterable valueMeasurement(Gauge gauge)
    {
        return new SingleMeasurement(&gauge.value, Statistic.VALUE);
    }

    /// Micrometer's default lazy value measurement (R3).
    mixin template Defaults(alias Measurements = MeasurementIterable, alias sample = valueMeasurement)
    {
        override Measurements measure()
        {
            return sample(this);
        }
    }
}

/// A meter that captures distribution statistics in a snapshot.
interface HistogramSupport : Meter
{
    /// Capture the meter's distribution statistics for publication together.
    HistogramSnapshot takeSnapshot();

    /// The flag is ignored. Histogram settings are chosen when the meter is registered.
    deprecated("Use takeSnapshot()") HistogramSnapshot takeSnapshot(bool supportsAggregablePercentiles);

    /// Micrometer's default legacy overload (R3).
    mixin template Defaults(alias Snapshot = HistogramSnapshot, alias Support = HistogramSupport)
    {
        deprecated("Use takeSnapshot()") override Snapshot takeSnapshot(bool supportsAggregablePercentiles)
        {
            Support histogram = this;
            return histogram.takeSnapshot();
        }
    }
}

// The registry uses these values only when creating the summary's maximum window.
package(flint.micrometer.core.instrument) struct SummaryWindow
{
    Nullable!Duration expiry;
    int bufferLength; // Zero selects the registry default.
}

/// Count nonnegative samples and report their total and recent maximum.
interface DistributionSummary : HistogramSupport
{
    /// Configure a distribution summary before registering it.
    static Builder builder(string name)
    {
        return Builder(name);
    }

    /// Register a distribution summary with a name, dimensions, metadata and scale.
    static struct Builder
    {
        private string name;
        private Tags dimensions;
        private NullableString description_;
        private NullableString baseUnit_;
        private double scale_ = 1.0;
        private Nullable!Duration expiry_;
        private Nullable!int bufferLength_;

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

        /// Set or clear the duration of each maximum bucket.
        ref Builder distributionStatisticExpiry(Nullable!Duration expiry) return
        {
            expiry_ = expiry;
            return this;
        }

        /// Set the duration of each maximum bucket.
        ref Builder distributionStatisticExpiry(Duration expiry) return
        {
            return distributionStatisticExpiry(Nullable!Duration(expiry));
        }

        /// Set or clear the number of buckets in the maximum window.
        ref Builder distributionStatisticBufferLength(Nullable!int bufferLength) return
        {
            bufferLength_ = bufferLength;
            return this;
        }

        /// Set the number of buckets in the maximum window.
        ref Builder distributionStatisticBufferLength(int bufferLength) return
        {
            return distributionStatisticBufferLength(Nullable!int(bufferLength));
        }

        /// Multiply each accepted amount by the given scale.
        ref Builder scale(double scale) return
        {
            scale_ = scale;
            return this;
        }

        /// Register the summary and return its retained handle.
        DistributionSummary register(MeterRegistry registry)
        {
            auto window = SummaryWindow(expiry_);
            if (!bufferLength_.isNull())
            {
                window.bufferLength = bufferLength_.get();
                validateDistributionBufferLength(window.bufferLength);
            }
            if (registry is null)
                throw new NullPointerException("registry");
            auto id = new Meter.Id(name, dimensions, baseUnit_, description_, Type.DISTRIBUTION_SUMMARY);
            return registry.summary(id, scale_, &window);
        }
    }

    /// Record an amount. Negative values and NaN are ignored.
    void record(double amount) nothrow @nogc;

    /// The number of accepted observations.
    long count() nothrow @nogc;

    /// The cumulative total amount.
    double totalAmount() nothrow @nogc;

    /// The mean of accepted observations.
    double mean() nothrow @nogc;

    /// The maximum amount in the current window.
    double max() nothrow @nogc;

    package static MeasurementIterable measurementsOf(DistributionSummary summary, bool withMaximum)
    {
        return new MeterMeasurements(summary, withMaximum);
    }

    /// Micrometer's default mean, snapshot overload and live measurements (R3).
    mixin template Defaults(alias Measurements = MeasurementIterable, alias samples = measurementsOf,
            alias SnapshotDefaults = HistogramSupport.Defaults)
    {
        mixin SnapshotDefaults;

        override double mean() nothrow @nogc
        {
            DistributionSummary summary = this;
            const count = summary.count();
            return count == 0 ? 0.0 : summary.totalAmount() / count;
        }

        override Measurements measure()
        {
            return samples(this, false);
        }
    }
}

/// Count recorded durations and report their total and recent maximum.
interface Timer : HistogramSupport
{
    /// Start a sample using the system clock.
    static Sample start()
    {
        return start(Clock.SYSTEM);
    }

    /// Start a sample using the registry's clock.
    static Sample start(MeterRegistry registry)
    {
        return start(MeterRegistry.clockOf(registry));
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

    /// Run a task and record its elapsed time, including when it throws.
    void record(Runnable action);

    /// Run and time a D delegate without retaining it (R9).
    void record(scope void delegate() @safe action);

    /// Return a boolean result while recording the supplier's elapsed time (R9).
    bool record(BooleanSupplier action);

    /// Return a boolean result from a D delegate without retaining it (R9).
    bool record(scope bool delegate() @safe action);

    /// Return a primitive result while recording the supplier's elapsed time (R9).
    double record(DoubleSupplier action);

    /// Return a primitive result from a D delegate without retaining it (R9).
    double record(scope double delegate() @safe action);

    /// Time the supplier and return its value (R9).
    /// Value results must support default initialization and assignment.
    T record(T)(Supplier!T action)
    {
        static if (!is(T == void))
            T result;
        record(() @safe {
            if (action is null)
                throw nullCallback();
            static if (is(T == void))
                action.get();
            else
                result = action.get();
        });
        static if (!is(T == void))
            return result;
    }

    /// Time a D supplier without retaining it (R9).
    /// Value results must support default initialization and assignment.
    T record(T)(scope T delegate() @safe action) if (!is(T == void))
    {
        return recordCallable!T(action);
    }

    /// Time the callable and propagate any exception it raises (R8, R9).
    /// Value results must support default initialization and assignment.
    T recordCallable(T)(Callable!T action)
    {
        static if (!is(T == void))
            T result;
        record(() @safe {
            if (action is null)
                throw nullCallback();
            static if (is(T == void))
                action.call();
            else
                result = action.call();
        });
        static if (!is(T == void))
            return result;
    }

    /// Time a D callable without retaining it (R9).
    /// Value results must support default initialization and assignment.
    T recordCallable(T)(scope T delegate() @safe action)
    {
        static if (is(T == void))
            record(action);
        else
        {
            T result;
            record(() {
                if (action is null)
                    throw nullCallback();
                result = action();
            });
            return result;
        }
    }

    /// Wrap a task to time each invocation.
    Runnable wrap(Runnable action);

    /// Return a reusable timed delegate that retains the action (R9).
    void delegate() @safe wrap(void delegate() @safe action);

    /// Wrap a callable to record the elapsed time of each invocation (R3, R9).
    /// Value results must support default initialization and assignment.
    Callable!T wrap(T)(Callable!T action)
    {
        static if (is(T == void))
        {
            // A null callable throws inside the timing callback, including for a void result.
            if (action is null)
                return new TimedCallable!T(this, () { throw nullCallback(); });
        }
        return new TimedCallable!T(this, action is null ? null : &action.call);
    }

    /// Wrap a supplier to record the elapsed time of each invocation (R3, R9).
    /// Value results must support default initialization and assignment.
    Supplier!T wrap(T)(Supplier!T action)
    {
        return new TimedSupplier!T(this, action);
    }

    /// Return a reusable timed result delegate that retains the action (R9).
    /// Value results must support default initialization and assignment.
    T delegate() @safe wrap(T)(T delegate() @safe action) if (!is(T == void))
    {
        auto task = new TimedCallable!T(this, action);
        return &task.call;
    }

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
        return new MeterMeasurements(timer);
    }

    private static Runnable timedRunnable(Timer timer, Runnable action)
    {
        return new TimedRunnable(timer, action);
    }

    private static NullPointerException nullCallback()
    {
        return new NullPointerException("action");
    }

    /// Micrometer's default duration conversion, wrappers, mean and live measurements (R3).
    mixin template Defaults(alias Measurements = MeasurementIterable,
            alias samples = timerMeasurements, alias DurationType = Duration,
            alias Unit = TimeUnit, alias RunnableType = Runnable,
            alias makeTimedRunnable = timedRunnable, alias DoubleSupplierType = DoubleSupplier,
            alias BooleanSupplierType = BooleanSupplier,
            alias NullAction = NullPointerException, alias makeNullAction = nullCallback,
            alias SnapshotDefaults = HistogramSupport.Defaults)
    {
        mixin SnapshotDefaults;

        static if (is(NullAction == typeof(makeNullAction())))
            private alias nullAction = makeNullAction;
        else
        {
            private static NullAction nullAction()
            {
                return new NullAction("action");
            }
        }

        override void record(DurationType duration)
        {
            Timer timer = this;
            timer.record(duration.toNanos(), Unit.NANOSECONDS);
        }

        override void record(RunnableType action)
        {
            Timer timer = this;
            timer.record(action is null ? null : &action.run);
        }

        override bool record(BooleanSupplierType action)
        {
            Timer timer = this;
            return timer.record(action is null ? null : &action.getAsBoolean);
        }

        override bool record(scope bool delegate() @safe action)
        {
            bool result;
            Timer timer = this;
            timer.record(() {
                if (action is null)
                    throw nullAction();
                result = action();
            });
            return result;
        }

        override double record(DoubleSupplierType action)
        {
            Timer timer = this;
            return timer.record(action is null ? null : &action.getAsDouble);
        }

        override double record(scope double delegate() @safe action)
        {
            double result;
            Timer timer = this;
            timer.record(() {
                if (action is null)
                    throw nullAction();
                result = action();
            });
            return result;
        }

        override RunnableType wrap(RunnableType action)
        {
            return makeTimedRunnable(this, action);
        }

        override void delegate() @safe wrap(void delegate() @safe action)
        {
            Timer timer = this;
            return () { timer.record(action); };
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

private final class TimedRunnable : Runnable
{
    private Timer timer;
    private Runnable action;

    this(Timer timer, Runnable action) nothrow @nogc
    {
        this.timer = timer;
        this.action = action;
    }

    override void run()
    {
        timer.record(action);
    }
}

private final class TimedCallable(T) : Callable!T
{
    private Timer timer;
    private T delegate() @safe action;

    this(Timer timer, T delegate() @safe action) nothrow @nogc
    {
        this.timer = timer;
        this.action = action;
    }

    override T call()
    {
        return timer.recordCallable!T(action);
    }
}

private final class TimedSupplier(T) : Supplier!T
{
    private Timer timer;
    private Supplier!T action;

    this(Timer timer, Supplier!T action) nothrow @nogc
    {
        this.timer = timer;
        this.action = action;
    }

    override T get()
    {
        return timer.record(action);
    }
}

/// Register meters by name and tags before handing their handles to request code.
abstract class MeterRegistry
{
    private Meter[] meters;
    private Mutex gate;
    private Clock registryClock;
    private Config configuration;
    private alias TimerFactory = Timer function(Meter.Id) @safe;
    private alias SummaryFactory = DistributionSummary function(Meter.Id, double, scope const SummaryWindow*) @safe;
    private TimerFactory timerFactory;
    private SummaryFactory summaryFactory;
    private bool closed;

    /// Prepare empty registry storage.
    protected this()
    {
        this(Clock.SYSTEM);
    }

    /// Prepare empty registry storage using the supplied clock.
    protected this(Clock clock)
    {
        this(clock, null, null);
    }

    package this(TimerFactory timerFactory, SummaryFactory summaryFactory = null)
    {
        this(Clock.SYSTEM, timerFactory, summaryFactory);
    }

    private this(Clock clock, TimerFactory timerFactory, SummaryFactory summaryFactory)
    {
        if (clock is null)
            throw new NullPointerException("clock");
        gate = new Mutex;
        registryClock = clock;
        configuration = new Config;
        this.timerFactory = timerFactory;
        this.summaryFactory = summaryFactory;
    }

    /// Return the configuration owned by this registry.
    Config config()
    {
        return configuration;
    }

    private static Clock clockOf(MeterRegistry registry)
    {
        if (registry is null)
            throw new NullPointerException("registry");
        auto configuration = registry.config();
        if (configuration is null)
            throw new NullPointerException("registry configuration");
        return configuration.clock();
    }

    /// Configuration of the enclosing registry.
    class Config
    {
        /// The clock used for measuring durations in this registry.
        Clock clock()
        {
            return registryClock;
        }
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

    /// Find or register a distribution summary with the given name and tag pairs.
    DistributionSummary summary(string name, scope const(string)[] tags...)
    {
        return summary(name, Tags.of(tags));
    }

    /// Find or register a distribution summary with the given name and tag iterable.
    DistributionSummary summary(string name, TagIterable tags)
    {
        auto id = new Meter.Id(name, Tags.of(tags), NullableString.init, NullableString.init,
                Meter.Type.DISTRIBUTION_SUMMARY);
        return summary(id, 1.0, null);
    }

    private DistributionSummary summary(Meter.Id id, double scale, scope const SummaryWindow* window)
    {
        return cast(DistributionSummary) registerMeter(id, scale, window);
    }

    private Meter registerMeter(Meter.Id id, double summaryScale = 1.0, scope const SummaryWindow* summaryWindow = null)
    {
        gate.lock_nothrow();
        scope (exit)
            gate.unlock_nothrow();

        foreach (meter; meters)
        {
            if (!id.equals(meter.getId()))
                continue;
            requireMeterType(meter, id);
            return meter;
        }

        const wasClosed = closed;
        auto created = createMeter(id, wasClosed, summaryScale, summaryWindow);
        if (!wasClosed)
            meters ~= created;
        return created;
    }

    private static void requireMeterType(Meter meter, Meter.Id id)
    {
        string requested;
        switch (id.getType())
        {
        case Meter.Type.COUNTER:
            if (cast(Counter) meter !is null)
                return;
            requested = "Counter";
            break;
        case Meter.Type.TIMER:
            if (cast(Timer) meter !is null)
                return;
            requested = "Timer";
            break;
        case Meter.Type.DISTRIBUTION_SUMMARY:
            if (cast(DistributionSummary) meter !is null)
                return;
            requested = "DistributionSummary";
            break;
        default:
            assert(0, "unsupported meter type");
        }
        const registered = cast(Counter) meter !is null ? "CumulativeCounter" : cast(Timer) meter !is null
            ? "CumulativeTimer" : "CumulativeDistributionSummary";
        throw new IllegalArgumentException("There is already a registered meter of a different type ("
                ~ registered ~ " vs. " ~ requested ~ ") with the same name: " ~ id.getName());
    }

    private Meter createMeter(Meter.Id id, bool noop, double summaryScale, scope const SummaryWindow* summaryWindow)
    {
        string unavailable;
        switch (id.getType())
        {
        case Meter.Type.COUNTER:
            return noop ? new NoopCounter(id) : newCounter(id);
        case Meter.Type.TIMER:
            if (noop)
                return new NoopTimer(id);
            if (timerFactory !is null)
                return timerFactory(id);
            unavailable = "This registry does not provide timers";
            break;
        case Meter.Type.DISTRIBUTION_SUMMARY:
            if (noop)
                return new NoopDistributionSummary(id);
            if (summaryFactory !is null)
                return summaryFactory(id, summaryScale, summaryWindow);
            unavailable = "This registry does not provide distribution summaries";
            break;
        default:
            assert(0, "unsupported meter type");
        }
        throw new UnsupportedOperationException(unavailable);
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

    override MeasurementIterable measure()
    {
        return statelessInstance!EmptyMeasurements();
    }

    mixin Counter.Defaults;
}

private final class NoopTimer : Timer
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

    override void record(scope void delegate() @safe action)
    {
        if (action is null)
            throw new NullPointerException("action");
        action();
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

    override HistogramSnapshot takeSnapshot()
    {
        return HistogramSnapshot.empty(0, 0, 0);
    }

    override MeasurementIterable measure()
    {
        return statelessInstance!EmptyMeasurements();
    }

    mixin Timer.Defaults;
}

private final class NoopDistributionSummary : DistributionSummary
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

    override void record(double amount) nothrow @nogc
    {
    }

    override long count() nothrow @nogc
    {
        return 0;
    }

    override double totalAmount() nothrow @nogc
    {
        return 0.0;
    }

    override double max() nothrow @nogc
    {
        return 0.0;
    }

    override HistogramSnapshot takeSnapshot()
    {
        return HistogramSnapshot.empty(0, 0, 0);
    }

    override MeasurementIterable measure()
    {
        return statelessInstance!EmptyMeasurements();
    }

    mixin DistributionSummary.Defaults;
}

// Java's no-op meters share an empty list of readings.
private final class EmptyMeasurements : MeasurementIterable
{
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
}

private final class SingleMeasurement : Measurement, MeasurementIterable
{
    this(double delegate() @safe sample, Statistic statistic)
    {
        super(sample, statistic);
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

private final class MeterMeasurements : MeasurementIterable
{
    private Measurement[3] measurements;
    private Timer timer;
    private DistributionSummary summary;

    this(Timer timer)
    {
        this.timer = timer;
        measurements[0] = newSample(&count, Statistic.COUNT);
        measurements[1] = newSample(&totalTime, Statistic.TOTAL_TIME);
        measurements[2] = newSample(&maximumTime, Statistic.MAX);
    }

    this(DistributionSummary summary, bool withMaximum)
    {
        this.summary = summary;
        measurements[0] = newSample(&count, Statistic.COUNT);
        measurements[1] = newSample(&summary.totalAmount, Statistic.TOTAL);
        if (withMaximum)
            measurements[2] = newSample(&summary.max, Statistic.MAX);
    }

    // Keep the cold allocation shared across the timer and summary constructors.
    pragma(inline, false) private static Measurement newSample(double delegate() @safe read, Statistic statistic)
    {
        return new Measurement(read, statistic);
    }

    private double count() nothrow @nogc
    {
        return cast(double)(timer is null ? summary.count() : timer.count());
    }

    private double totalTime() nothrow @nogc
    {
        return timer.totalTime(timer.baseTimeUnit());
    }

    private double maximumTime() nothrow @nogc
    {
        return timer.max(timer.baseTimeUnit());
    }

    private size_t measurementCount() const nothrow @nogc
    {
        // The optional maximum is the only slot that can be empty.
        return measurements[2] is null ? 2 : 3;
    }

    override Iterator!Measurement iterator()
    {
        return new MeasurementIterator(measurements[0], measurements[1], measurements[2]);
    }

    override void forEach(void delegate(Measurement) @safe action)
    {
        foreach (sample; measurements[0 .. measurementCount()])
            action(sample);
    }

    override int opApply(scope int delegate(Measurement) @safe visit)
    {
        foreach (sample; measurements[0 .. measurementCount()])
            if (const result = visit(sample))
                return result;
        return 0;
    }
}

@("a default summary view stops after COUNT and TOTAL")
unittest
{
    auto view = DistributionSummary.measurementsOf(new NoopDistributionSummary(null), false);
    const expected = [Statistic.COUNT, Statistic.TOTAL];
    size_t index;
    view.forEach((reading) { assert(reading.getStatistic() == expected[index++]); });
    assert(index == expected.length);
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
