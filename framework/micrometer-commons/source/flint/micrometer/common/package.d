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
// Ported from micrometer-commons 1.18.0: io/micrometer/common/KeyValue.java
// Ported from micrometer-commons 1.18.0: io/micrometer/common/ImmutableKeyValue.java
// Ported from micrometer-commons 1.18.0: io/micrometer/common/KeyValues.java
// Modified by the Flint authors.
module flint.micrometer.common;

import flint.engine.aot.objects : objectToString, statelessInstance;
import flint.engine.aot.text : decodeUtf8;
import flint.java.lang : Comparable, IllegalArgumentException, Iterable, JavaObject,
    NullPointerException, UnsupportedOperationException, javaEquals, javaHashCode, stringHashCode;
import flint.java.util : Iterator, NoSuchElementException, stableSort;
import flint.java.util.function_ : Function;
import flint.java.util.stream : Stream;

@safe:

private alias KeyValueIterable = Iterable!KeyValue;

/// One dimension of an observation (R1, R3, R6).
interface KeyValue : Comparable!KeyValue
{
    /// The conventional value for a dimension that is absent.
    enum string NONE_VALUE = "none";

    string getKey();
    string getValue();

    /// Create an immutable pair.
    static KeyValue of(string key, string value)
    {
        return new ImmutableKeyValue(key, value);
    }

    /// Extract a key and value using Java function objects.
    static KeyValue of(E)(E element, Function!(E, string) keyExtractor, Function!(E, string) valueExtractor)
    {
        return of!E(element, keyExtractor is null ? null : &keyExtractor.apply, valueExtractor is null
                ? null : &valueExtractor.apply);
    }

    /// Extract a key and value through scoped delegates (R9).
    static KeyValue of(E)(E element, scope string delegate(E) @safe keyExtractor,
            scope string delegate(E) @safe valueExtractor)
    {
        if (keyExtractor is null)
            throw new NullPointerException("keyExtractor");
        auto key = keyExtractor(element);
        if (valueExtractor is null)
            throw new NullPointerException("valueExtractor");
        return of(key, valueExtractor(element));
    }

    private static int comparePair(KeyValue pair, KeyValue other)
    {
        if (other is null)
            throw new NullPointerException("pair");
        return compareKeys(pair.getKey(), other.getKey());
    }

    /// Compare values by key, as in Java's default method (R3).
    mixin template Defaults(alias Value = KeyValue, alias compare = comparePair)
    {
        override int compareTo(Value other)
        {
            return compare(this, other);
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
private final class ImmutableKeyValue : KeyValue
{
    private immutable string key;
    private immutable string value;

    /// Store the non-null key and value.
    this(string key, string value)
    {
        if (key is null || value is null)
            throw new NullPointerException("key and value must be non-null");
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

    /// Compare the key and value of two immutable values.
    bool equals(Object other)
    {
        auto pair = cast(ImmutableKeyValue) other;
        return this is pair || (pair !is null && key == pair.getKey() && value == pair.getValue());
    }

    /// Hash the key and value using Java's string hash.
    int hashCode() nothrow @nogc
    {
        return 31 * stringHashCode(key) + stringHashCode(value);
    }

    /// Format this dimension as `keyValue(key=value)`.
    override string toString() const
    {
        return "keyValue(" ~ key ~ "=" ~ value ~ ")";
    }

    mixin KeyValue.Defaults;
    mixin JavaObject;
}

/// Immutable key values in key order. Later instances of a key replace earlier ones.
abstract class KeyValues : KeyValueIterable
{
    // Only this module constructs KeyValues. EmptyKeyValues uses the existing stateless Java singleton path.
    private this() nothrow @nogc
    {
    }

    protected abstract KeyValue[] entries() nothrow @nogc;

    /// Return the shared empty set.
    static KeyValues empty() nothrow @nogc
    {
        return statelessInstance!EmptyKeyValues();
    }

    /// Normalize the contents of an iterable.
    static KeyValues of(KeyValueIterable values)
    {
        if (values is null)
            return empty();
        if (auto existing = cast(KeyValues) values)
            return existing;
        return fromIterable(values);
    }

    /// Accept iterables whose element type implements KeyValue (R10).
    static KeyValues of(T)(Iterable!T values) if (is(T : KeyValue) && !is(T == KeyValue))
    {
        return fromIterable(values);
    }

    private static KeyValues fromIterable(T)(Iterable!T values)
    {
        if (values is null)
            return empty();
        KeyValue[] items;
        foreach (pair; values)
            items ~= requireValue(pair);
        return fromOwned(items);
    }

    /// Extract and normalize key values from a collection of elements.
    static KeyValues of(E)(Iterable!E elements, Function!(E, string) keyExtractor, Function!(E,
            string) valueExtractor)
    {
        return empty().and!E(elements, keyExtractor, valueExtractor);
    }

    /// Extract and normalize key values using scoped delegates (R9).
    static KeyValues of(E)(Iterable!E elements, scope string delegate(E) @safe keyExtractor,
            scope string delegate(E) @safe valueExtractor)
    {
        return empty().and!E(elements, keyExtractor, valueExtractor);
    }

    /// Create a set holding one dimension.
    static KeyValues of(string key, string value)
    {
        return new StoredKeyValues([KeyValue.of(key, value)]);
    }

    /// Create a set from alternating keys and values.
    static KeyValues of(scope const(string)[] keyValues...)
    {
        if (keyValues.length == 0 || (keyValues.length == 1 && keyValues[0] is null))
            return empty();
        if (keyValues.length % 2 != 0)
            throw new IllegalArgumentException("size must be even, it is a set of key=value pairs");

        auto items = new KeyValue[keyValues.length / 2];
        foreach (index, ref item; items)
            item = KeyValue.of(keyValues[index * 2], keyValues[index * 2 + 1]);
        return fromOwned(items);
    }

    /// Normalize a sequence of pair objects.
    static KeyValues of(scope KeyValue[] values...)
    {
        if (values.length == 0 || (values.length == 1 && values[0] is null))
            return empty();
        auto items = new KeyValue[values.length];
        foreach (index, pair; values)
            items[index] = requireValue(pair);
        return fromOwned(items);
    }

    /// Merge two iterables. The second supplies the value of any repeated key.
    static KeyValues concat(KeyValueIterable values, KeyValueIterable otherKeyValues)
    {
        return of(values).and(otherKeyValues);
    }

    /// Concatenate iterables of compatible KeyValue types (R10).
    static KeyValues concat(A, B)(Iterable!A values, Iterable!B otherKeyValues)
            if (is(A : KeyValue) && is(B : KeyValue) && !(is(A == KeyValue) && is(B == KeyValue)))
    {
        return of(values).and(otherKeyValues);
    }

    /// Merge an iterable with alternating keys and values.
    static KeyValues concat(KeyValueIterable values, scope const(string)[] keyValues...)
    {
        return of(values).and(keyValues);
    }

    /// Add string pairs to an iterable of a KeyValue subtype (R7, R10).
    static KeyValues concat(T)(Iterable!T values, scope const(string)[] keyValues...)
            if (is(T : KeyValue) && !is(T == KeyValue))
    {
        return of(values).and(keyValues);
    }

    /// Merge this set with the given iterable.
    final KeyValues and(KeyValueIterable values)
    {
        return merge(of(values));
    }

    /// Merge an iterable of a KeyValue subtype (R10).
    KeyValues and(T)(Iterable!T values) if (is(T : KeyValue) && !is(T == KeyValue))
    {
        return merge(of(values));
    }

    /// Merge key values extracted through Java function objects.
    KeyValues and(E)(Iterable!E elements, Function!(E, string) keyExtractor, Function!(E, string) valueExtractor)
    {
        return and!E(elements, keyExtractor is null ? null : &keyExtractor.apply,
                valueExtractor is null ? null : &valueExtractor.apply);
    }

    /// Merge key values extracted through scoped delegates (R9).
    KeyValues and(E)(Iterable!E elements, scope string delegate(E) @safe keyExtractor,
            scope string delegate(E) @safe valueExtractor)
    {
        if (elements is null)
            return this;
        KeyValue[] items;
        foreach (element; elements)
            items ~= KeyValue.of!E(element, keyExtractor, valueExtractor);
        return merge(fromOwned(items));
    }

    /// Add or replace one dimension.
    final KeyValues and(string key, string value)
    {
        return merge(of(key, value));
    }

    /// Merge additional key/value pairs.
    final KeyValues and(scope const(string)[] keyValues...)
    {
        return merge(of(keyValues));
    }

    /// Merge additional pair objects.
    final KeyValues and(scope KeyValue[] values...)
    {
        return merge(of(values));
    }

    final override Iterator!KeyValue iterator()
    {
        return new KeyValuesIterator(entries());
    }

    final
    {
        mixin Iterable!KeyValue.Defaults;
    }

    final override int opApply(scope int delegate(KeyValue) @safe visit)
    {
        foreach (item; entries())
        {
            if (const result = visit(item))
                return result;
        }
        return 0;
    }

    /// Stream the dimensions in key order.
    final Stream!KeyValue stream()
    {
        // Both the array and its entries stay owned by this collection.
        return Stream!KeyValue.ofArray(entries());
    }

    /// Compare normalized keys and values in order.
    final bool equals(Object other)
    {
        auto values = cast(KeyValues) other;
        if (this is values)
            return true;
        if (values is null)
            return false;
        auto left = entries();
        auto right = values.entries();
        if (left.length != right.length)
            return false;
        foreach (index, item; left)
        {
            if (!javaEquals(item, right[index]))
                return false;
        }
        return true;
    }

    /// Hash the values in key order.
    final int hashCode()
    {
        int result = 1;
        foreach (item; entries())
            result = 31 * result + javaHashCode(item);
        return result;
    }

    /// Format the key values in key order.
    abstract override string toString() const;

    mixin JavaObject;

    private KeyValues merge(KeyValues other)
    {
        auto first = entries();
        auto second = other.entries();
        const left = first.length;
        const right = second.length;
        if (right == 0 || equals(other))
            return this;
        if (left == 0)
            return other;

        auto output = new KeyValue[left + right];
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
        return new StoredKeyValues(output[0 .. length + right - j]);
    }

    private static KeyValue requireValue(KeyValue pair)
    {
        if (pair is null)
            throw new NullPointerException("pair");
        return pair;
    }

    private static KeyValues fromOwned(KeyValue[] items)
    {
        if (items.length == 0)
            return empty();
        foreach (index; 1 .. items.length)
        {
            if (items[index - 1].compareTo(items[index]) >= 0)
            {
                stableSort!KeyValue(items, (a, b) => a.compareTo(b));
                return new StoredKeyValues(deduplicate(items));
            }
        }
        return new StoredKeyValues(items);
    }

    private static KeyValue[] deduplicate(KeyValue[] items)
    {
        size_t length;
        foreach (index; 1 .. items.length)
        {
            if (items[index - 1].getKey() != items[index].getKey())
                items[length++] = items[index - 1];
        }
        items[length++] = items[$ - 1];
        items[length .. $] = null;
        return items[0 .. length];
    }
}

private final class EmptyKeyValues : KeyValues
{
    override string toString() const
    {
        return "[]";
    }

    protected override KeyValue[] entries() nothrow @nogc
    {
        return null;
    }
}

private final class StoredKeyValues : KeyValues
{
    private KeyValue[] items;
    // A Java KeyValue may provide its own Object.toString. The callback renders those values without changing this set.
    private string delegate() @safe format;

    this(KeyValue[] items) nothrow @nogc
    {
        this.items = items;
        format = &formatKeyValues;
    }

    override string toString() const
    {
        return format();
    }

    private string formatKeyValues()
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

    protected override KeyValue[] entries() nothrow @nogc
    {
        return items;
    }
}

private final class KeyValuesIterator : Iterator!KeyValue
{
    private KeyValue[] remaining;

    this(KeyValue[] items) nothrow @nogc
    {
        remaining = items;
    }

    override bool hasNext() nothrow @nogc
    {
        return remaining.length != 0;
    }

    override KeyValue next()
    {
        if (!hasNext())
            throw new NoSuchElementException("no more key values");
        auto item = remaining[0];
        remaining = remaining[1 .. $];
        return item;
    }

    override void remove()
    {
        throw new UnsupportedOperationException("cannot remove items from key values");
    }
}
