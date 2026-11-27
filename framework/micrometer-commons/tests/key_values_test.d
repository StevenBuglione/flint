/*
 * Copyright 2022 the original author or authors.
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
// Ported from micrometer-commons 1.18.0: micrometer-commons/src/test/java/io/micrometer/common/KeyValuesTest.java
// Modified by the Flint authors.
module micrometer_key_values_test;

import core.memory : GC;
import flint.java.lang : IllegalArgumentException, Iterable, NullPointerException;
import flint.java.util : Arrays, Collections, Map, MapEntry;
import flint.java.util.function_ : Function;
import flint.java.util.function_.consumer : Consumer;
import flint.micrometer.common : KeyValue, KeyValues;
import std.exception : assertThrown;

@safe:

private void assertKeyValues(KeyValues values, scope const(string)[] expected...)
{
    auto iter = values.iterator();
    for (size_t index = 0; index < expected.length; index += 2)
    {
        assert(iter.hasNext());
        auto pair = iter.next();
        assert(pair.getKey() == expected[index]);
        assert(pair.getValue() == expected[index + 1]);
    }
    assert(!iter.hasNext());
}

@("dedup")
unittest
{
    assertKeyValues(KeyValues.of("k1", "v1", "k2", "v2"), "k1", "v1", "k2", "v2");
    assertKeyValues(KeyValues.of("k1", "v1", "k1", "v2"), "k1", "v2");
    assertKeyValues(KeyValues.of("k3", "v3", "k1", "v1", "k1", "v2"), "k1", "v2", "k3", "v3");
    assertKeyValues(KeyValues.of("k2", "v2", "k1", "v1", "k2", "v3"), "k1", "v1", "k2", "v3");
}

@("keyValuesEquality")
unittest
{
    auto values = KeyValues.of(KeyValue.of("k1", "v1"), KeyValue.of("k1", "v1"), KeyValue.of("k2", "v2"));
    assert(values.equals(KeyValues.of("k2", "v2", "k1", "v1")));
    assert(!values.equals(KeyValues.of("k1", "v1", "k2", "different")));
}

@("keyValuesHashCode")
unittest
{
    auto values = KeyValues.of(KeyValue.of("k1", "v1"), KeyValue.of("k1", "v1"), KeyValue.of("k2", "v2"));
    assert(values.hashCode() == KeyValues.of("k1", "v1", "k2", "v2").hashCode());
}

@("keyValuesToString")
unittest
{
    auto values = KeyValues.of(KeyValue.of("k1", "v1"), KeyValue.of("k1", "v1"), KeyValue.of("k2", "v2"));
    assert(values.toString() == "[keyValue(k1=v1),keyValue(k2=v2)]");
}

@("nullKeyValueIterableShouldProduceEmptyKeyValues")
unittest
{
    assert(KeyValues.of(cast(Iterable!KeyValue) null) is KeyValues.empty());
}

@("nullKeyValueStringArrayShouldProduceEmptyKeyValues")
unittest
{
    assert(KeyValues.of(cast(string[]) null) is KeyValues.empty());
}

@("nullKeyValuesShouldProduceEmptyKeyValues")
unittest
{
    assert(KeyValues.of(cast(string) null) is KeyValues.empty());
}

@("nullKeyValueArrayShouldProduceEmptyKeyValues")
unittest
{
    assert(KeyValues.of(cast(KeyValue[]) null) is KeyValues.empty());
}

@("nullKeyValueShouldProduceEmptyKeyValues")
unittest
{
    assert(KeyValues.of(cast(KeyValue) null) is KeyValues.empty());
}

@("emptyKeyValueIterableShouldProduceEmptyKeyValues")
unittest
{
    assert(KeyValues.of(Collections.emptyList!KeyValue()) is KeyValues.empty());
}

@("emptyKeyValueStringArrayShouldProduceEmptyKeyValues")
unittest
{
    assert(KeyValues.of(new string[0]) is KeyValues.empty());
}

@("emptyKeyValueArrayShouldProduceEmptyKeyValues")
unittest
{
    assert(KeyValues.of(new KeyValue[0]) is KeyValues.empty());
}

@("createsListWithSingleKeyValue")
unittest
{
    assertKeyValues(KeyValues.of("k1", "v1"), "k1", "v1");
}

@("concatOnTwoKeyValuesWithSameKeyAreMergedIntoOneKeyValue")
unittest
{
    assertKeyValues(KeyValues.concat(KeyValues.of("k", "v1"), "k", "v2"), "k", "v2");
}

@("concatWhenKeyValuesAreNullShouldReturnCurrentInstance")
unittest
{
    auto source = KeyValues.of("t1", "v1");
    assert(KeyValues.concat(source, cast(string) null) is source);
}

@("zipOnTwoKeyValuesWithSameKeyAreMergedIntoOneKeyValue")
unittest
{
    assertKeyValues(KeyValues.of("t1", "v1", "t1", "v2"), "t1", "v2");
}

@("andKeyValueShouldReturnNewInstanceWithAddedKeyValues")
unittest
{
    auto source = KeyValues.of("t1", "v1");
    auto merged = source.and("t2", "v2");
    assert(merged !is source);
    assertKeyValues(source, "t1", "v1");
    assertKeyValues(merged, "t1", "v1", "t2", "v2");
}

@("andKeyValuesShouldReturnNewInstanceWithAddedKeyValues")
unittest
{
    auto source = KeyValues.of("t1", "v1");
    auto merged = source.and("t2", "v2", "t3", "v3");
    assert(merged !is source);
    assertKeyValues(source, "t1", "v1");
    assertKeyValues(merged, "t1", "v1", "t2", "v2", "t3", "v3");
}

@("andKeyValuesWhenKeyValuesAreOddShouldThrowException")
unittest
{
    assertThrown!IllegalArgumentException(KeyValues.of("t1", "v1").and("t2"));
}

@("andKeyValuesStringArrayWhenKeyValuesAreEmptyShouldReturnCurrentInstance")
unittest
{
    auto source = KeyValues.of("t1", "v1");
    assert(source.and(new string[0]) is source);
}

@("andKeyValuesStringArrayWhenKeyValuesArrayIsNullShouldReturnCurrentInstance")
unittest
{
    auto source = KeyValues.of("t1", "v1");
    assert(source.and(cast(string[]) null) is source);
}

@("andKeyValuesStringArrayWhenKeyValuesAreNullShouldReturnCurrentInstance")
unittest
{
    auto source = KeyValues.of("t1", "v1");
    assert(source.and(cast(string) null) is source);
}

@("andKeyValuesShouldReturnANewInstanceWithKeyValues")
unittest
{
    auto source = KeyValues.of("t1", "v1");
    auto merged = source.and(KeyValue.of("t2", "v2"));
    assert(merged !is source);
    assertKeyValues(source, "t1", "v1");
    assertKeyValues(merged, "t1", "v1", "t2", "v2");
}

@("andKeyValuesWhenKeyValuesAreEmptyShouldReturnCurrentInstance")
unittest
{
    auto source = KeyValues.of("t1", "v1");
    assert(source.and(new KeyValue[0]) is source);
}

@("andKeyValuesWhenKeyValuesArrayIsNullShouldReturnCurrentInstance")
unittest
{
    auto source = KeyValues.of("t1", "v1");
    assert(source.and(cast(KeyValue[]) null) is source);
}

@("andKeyValuesWhenKeyValueIsNullShouldReturnCurrentInstance")
unittest
{
    auto source = KeyValues.of("t1", "v1");
    assert(source.and(cast(KeyValue) null) is source);
}

@("andKeyValuesMultipleTimesShouldWork")
unittest
{
    auto source = KeyValues.empty().and(KeyValue.of("t1", "v1"));
    auto once = source.and(KeyValue.of("t1", "v1"));
    assert(once.equals(source));
    assert(once.and(KeyValue.of("t1", "v1")).equals(source));
}

@("andIterableShouldReturnNewInstanceWithKeyValues")
unittest
{
    auto source = KeyValues.of("t1", "v1");
    auto merged = source.and(Arrays.asList!KeyValue(KeyValue.of("t2", "v2")));
    assert(merged !is source);
    assertKeyValues(source, "t1", "v1");
    assertKeyValues(merged, "t1", "v1", "t2", "v2");
}

@("andIterableWhenIterableIsNullShouldReturnCurrentInstance")
unittest
{
    auto source = KeyValues.of("t1", "v1");
    assert(source.and(cast(Iterable!KeyValue) null) is source);
}

@("andWhenAlreadyContainsKeyShouldReplaceValue")
unittest
{
    auto source = KeyValues.of("t1", "v1");
    auto merged = source.and("t2", "v2", "t1", "v3");
    assertKeyValues(source, "t1", "v1");
    assertKeyValues(merged, "t1", "v3", "t2", "v2");
}

@("iteratorShouldIterateKeyValues")
unittest
{
    assertKeyValues(KeyValues.of("t1", "v1"), "t1", "v1");
}

@("stream")
unittest
{
    auto values = KeyValues.of(KeyValue.of("k1", "v1"), KeyValue.of("k1", "v1"), KeyValue.of("k2", "v2"));
    assert(values.stream().count() == 2);
}

@("streamShouldStreamKeyValues")
unittest
{
    auto items = KeyValues.of("t1", "v1").stream().toList();
    assert(items.size() == 1);
    assert(items.get(0).getKey() == "t1");
    assert(items.get(0).getValue() == "v1");
}

@("concatIterableShouldReturnNewInstanceWithAddedKeyValues")
unittest
{
    auto source = KeyValues.of("t1", "v1");
    auto merged = KeyValues.concat(source, Arrays.asList!KeyValue(KeyValue.of("t2", "v2")));
    assert(merged !is source);
    assertKeyValues(source, "t1", "v1");
    assertKeyValues(merged, "t1", "v1", "t2", "v2");
}

@("concatStringsShouldReturnNewInstanceWithAddedKeyValues")
unittest
{
    auto source = KeyValues.of("t1", "v1");
    auto merged = KeyValues.concat(source, "t2", "v2");
    assert(merged !is source);
    assertKeyValues(source, "t1", "v1");
    assertKeyValues(merged, "t1", "v1", "t2", "v2");
}

@("zipShouldReturnNewInstanceWithKeyValues")
unittest
{
    assertKeyValues(KeyValues.of("t1", "v1", "t2", "v2"), "t1", "v1", "t2", "v2");
}

@("ofIterableShouldReturnNewInstanceWithKeyValues")
unittest
{
    assertKeyValues(KeyValues.of(Arrays.asList!KeyValue(KeyValue.of("t1", "v1"))), "t1", "v1");
}

@("ofIterableWhenIterableIsKeyValuesShouldReturnSameInstance")
unittest
{
    auto source = KeyValues.of("t1", "v1");
    assert(KeyValues.of(source) is source);
}

@("ofKeyValueShouldReturnNewInstance")
unittest
{
    assertKeyValues(KeyValues.of("t1", "v1"), "t1", "v1");
}

@("ofKeyValuesShouldReturnNewInstance")
unittest
{
    assertKeyValues(KeyValues.of("t1", "v1", "t2", "v2"), "t1", "v1", "t2", "v2");
}

@("emptyShouldNotContainKeyValues")
unittest
{
    assert(!KeyValues.empty().iterator().hasNext());
}

@("andEmptyDoesNotAllocate")
unittest
{
    auto values = KeyValues.of("a", "b");
    auto empty = KeyValues.empty();
    const before = GC.stats().allocatedInCurrentThread;
    const combined = values.and(empty);
    assert(GC.stats().allocatedInCurrentThread == before);
    assert(combined is values);
}

@("ofEmptyDoesNotAllocate")
unittest
{
    auto empty = KeyValues.empty();
    const before = GC.stats().allocatedInCurrentThread;
    const copy = KeyValues.of(empty);
    assert(GC.stats().allocatedInCurrentThread == before);
    assert(copy is empty);
}

@("KeyValues own their array and preserve the input order of duplicate keys")
unittest
{
    KeyValue[] input = [
        KeyValue.of("b", "before"), KeyValue.of("a", "one"), KeyValue.of("b", "after")
    ];
    auto values = KeyValues.of(input);
    assert(input[0].getValue() == "before");
    input[0] = KeyValue.of("a", "mutated");
    assertKeyValues(values, "a", "one", "b", "after");
}

@("KeyValues sort in Java UTF-16 key order")
unittest
{
    assertKeyValues(KeyValues.of("\uE000", "bmp", "\U00010000", "supplementary"), "\U00010000",
            "supplementary", "\uE000", "bmp");
    assert(KeyValue.of("a", "").compareTo(KeyValue.of("a\U00010000z", "")) == -3);
    assert(KeyValue.of("\U00010000", "").compareTo(KeyValue.of("\U00010002", "")) == -2);
}

@("KeyValue distinguishes empty strings from null")
unittest
{
    assertThrown!NullPointerException(KeyValue.of(null, ""));
    assertThrown!NullPointerException(KeyValue.of("", null));
    assertKeyValues(KeyValues.of("", ""), "", "");
}

@("ofExtractingFromElementsReturnsKeyValues")
unittest
{
    alias Entry = MapEntry!(string, string);
    auto map = Map!(string, string).of("micrometer", "tracing", "can", "trace");
    auto values = KeyValues.of!Entry(map.entrySet(), entry => entry.getKey(), entry => entry.getValue());
    assertKeyValues(values, "can", "trace", "micrometer", "tracing");
}

@("andExtractingFromElementsReturnsKeyValues")
unittest
{
    alias Entry = MapEntry!(string, string);
    auto map = Map!(string, string).of("micrometer", "tracing", "can", "trace");
    auto values = KeyValues.of("no", "way").and!Entry(map.entrySet(), entry => entry.getKey(),
            entry => entry.getValue());
    assertKeyValues(values, "can", "trace", "micrometer", "tracing", "no", "way");
}

private final class WrappedValue : KeyValue
{
    private KeyValue pair;

    this(string key, string value)
    {
        pair = KeyValue.of(key, value);
    }

    override string getKey()
    {
        return pair.getKey();
    }

    override string getValue()
    {
        return pair.getValue();
    }

    mixin KeyValue.Defaults;
}

@("KeyValue collection overloads accept subtype iterables")
unittest
{
    auto specific = Arrays.asList!WrappedValue(new WrappedValue("x", "right"));
    auto source = KeyValues.of("x", "left");
    assertKeyValues(KeyValues.of(specific), "x", "right");
    assertKeyValues(source.and(specific), "x", "right");
    assertKeyValues(KeyValues.concat(source, specific), "x", "right");
    assertKeyValues(KeyValues.concat(specific, source), "x", "left");
    assertKeyValues(KeyValues.concat(specific, "x", "last"), "x", "last");
}

private final class StringExtractor : Function!(string, string)
{
    private string delegate(string) @safe extract;

    this(string delegate(string) @safe extract)
    {
        this.extract = extract;
    }

    override string apply(string value)
    {
        return extract(value);
    }
}

@("Java function objects work through all extractor entry points")
unittest
{
    Function!(string, string) key = new StringExtractor((_) => "region");
    Function!(string, string) value = new StringExtractor((name) => name);
    auto pair = KeyValue.of("west", key, value);
    assert(pair.getKey() == "region" && pair.getValue() == "west");
    auto regions = Arrays.asList!string("west");
    assertKeyValues(KeyValues.of(regions, key, value), "region", "west");
    assertKeyValues(KeyValues.of("method", "POST").and(regions, key, value), "method", "POST", "region", "west");
}

@("forEach rejects a null action even when empty")
unittest
{
    static assert(!__traits(compiles, KeyValues.empty().forEach(null)));
    void delegate(KeyValue) @safe absentDelegate;
    Consumer!KeyValue absentConsumer;
    assertThrown!NullPointerException(KeyValues.empty().forEach(absentDelegate));
    assertThrown!NullPointerException(KeyValues.empty().forEach(absentConsumer));
}
