/*
 * Copyright 2017 VMware, Inc.
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
// Modified by the Flint authors.
module flint.micrometer.core.instrument;

import flint.engine.aot.objects : objectToString, statelessInstance;
import flint.engine.aot.text : decodeUtf8;
import flint.java.lang : Comparable, IllegalArgumentException, Iterable, JavaObject,
    NullPointerException, UnsupportedOperationException, javaEquals, javaHashCode, stringHashCode;
import flint.java.util : Iterator, List, NoSuchElementException, stableSort;
import flint.java.util.stream : Stream;
import std.typecons : Nullable;

@safe:

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
abstract class Tags : Iterable!Tag
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
    static Tags of(Iterable!Tag tags)
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
    static Tags concat(Iterable!Tag tags, Iterable!Tag otherTags)
    {
        return of(tags).and(otherTags);
    }

    /// Merge an iterable with alternating keys and values.
    static Tags concat(Iterable!Tag tags, scope const(string)[] keyValues...)
    {
        return of(tags).and(keyValues);
    }

    /// Merge this set with the given iterable.
    final Tags and(Iterable!Tag tags)
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

/// A named source of measurements.
interface Meter
{
    /// The meter's registered identity.
    Id getId();

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
        private Nullable!string baseUnit;
        private Nullable!string description;
        private Type type;

        /// The name and tags identify the meter. Unit, description and type describe it.
        this(string name, Tags tags, Nullable!string baseUnit, Nullable!string description, Type type)
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
        Id withTags(Iterable!Tag extraTags)
        {
            return new Id(name, tags.and(extraTags), baseUnit, description, type);
        }

        /// Return an ID whose only dimensions are the supplied tags.
        Id replaceTags(Iterable!Tag replacement)
        {
            return new Id(name, Tags.of(replacement), baseUnit, description, type);
        }

        /// Return an ID for the same meter with a different base unit.
        Id withBaseUnit(Nullable!string newBaseUnit)
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
        Iterable!Tag getTagsAsIterable() nothrow @nogc
        {
            return tags;
        }

        /// The value of the named dimension, or null if absent.
        Nullable!string getTag(string key)
        {
            if (key is null)
                return Nullable!string.init;
            foreach (tag; tags.entries())
            {
                if (tag.getKey() == key)
                    return Nullable!string(tag.getValue());
            }
            return Nullable!string.init;
        }

        /// The meter's base unit, if set.
        Nullable!string getBaseUnit() const pure nothrow @nogc
        {
            return baseUnit;
        }

        /// The meter's description, if set.
        Nullable!string getDescription() const pure nothrow @nogc
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
