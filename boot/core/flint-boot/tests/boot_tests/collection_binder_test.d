// Ported from spring-boot v4.2.0: core/spring-boot/src/test/java/org/springframework/boot/context/properties/bind/CollectionBinderTests.java
// with ArrayBinderTests.java and MapBinderTests.java from the same directory.
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: `List<Integer>` is `int[]` or `flint.java.util.List!int`, `Map<String, ?>` is a D
// associative array or `flint.java.util.Map`; the BindHandler, PropertyEditor and non-sequential-index cases are
// not ported (Flint's binder has no handlers or editors yet, and stops at the first missing index).
module boot_tests.collection_binder_test;

import flint.boot.context.properties.bind : Bindable, Binder;
import flint.boot.context.properties.source : ConfigurationPropertySource, MapConfigurationPropertySource;
import flint.engine.aot.descriptor : descriptorOf;

@safe:

private MapConfigurationPropertySource source(string[2][] entries)
{
    return new MapConfigurationPropertySource("test", entries);
}

private Binder binder(MapConfigurationPropertySource[] sources...)
{
    ConfigurationPropertySource[] list;
    foreach (s; sources)
        list ~= s;
    return new Binder(list);
}

/// `CollectionBinderTests.JavaBean`, holding a value.
final class ValueBean
{
    private string value;

    /// The value.
    string getValue() const
    {
        return value;
    }

    /// Set the value.
    void setValue(string value)
    {
        this.value = value;
    }
}

/// A bean with a nested list (`BeanWithNestedCollection`).
final class BeanWithNestedCollection
{
    private string[] foos;

    /// The list.
    string[] getFoos()
    {
        return foos;
    }

    /// Set the list.
    void setFoos(string[] foos)
    {
        this.foos = foos;
    }
}

/// `MapBinderTests.ExampleEnum`.
enum ExampleEnum
{
    FOO_BAR,
    BAR_BAZ
}

private bool same(K, V)(const V[K] actual, const V[K] expected)
{
    if (actual.length != expected.length)
        return false;
    foreach (key, value; expected)
    {
        auto found = key in actual;
        if (found is null || *found != value)
            return false;
    }
    return true;
}

// ---- CollectionBinderTests and ArrayBinderTests -----------------------------------------------------------

@("bindToCollectionShouldReturnPopulatedCollection") unittest
{
    assert(binder(source([["foo[0]", "1"], ["foo[1]", "2"], ["foo[2]", "3"]])).bind!(int[])("foo").get() == [
        1, 2, 3
    ]);
}

@("bindToCollectionWhenNotInOrderShouldReturnPopulatedCollection") unittest
{
    assert(binder(source([["foo[1]", "2"], ["foo[0]", "1"], ["foo[2]", "3"]])).bind!(int[])("foo").get() == [
        1, 2, 3
    ]);
}

@("bindToCollectionWhenMultipleSourceShouldOnlyUseFirst") unittest
{
    auto first = source([["bar", "baz"], ["foo[0]", "1"], ["foo[1]", "2"]]);
    auto second = source([["foo[0]", "2"], ["foo[1]", "3"], ["foo[2]", "4"]]);
    assert(binder(first, second).bind!(int[])("foo").get() == [1, 2]);
}

@("bindToCollectionWhenHasExistingCollectionShouldReplaceAllContents") unittest
{
    auto result = binder(source([["foo[0]", "1"]])).bind!(int[])("foo", Bindable!(int[]).ofInstance([
        4, 5, 6
    ]));
    assert(result.get() == [1]);
}

@("bindToCollectionWhenNoValueShouldReturnUnbound") unittest
{
    assert(!binder(source([["faf.bar", "1"]])).bind!(int[])("foo").isBound());
}

@("bindToCollectionWhenCommaListShouldReturnPopulatedCollection") unittest
{
    assert(binder(source([["foo", "1,2,3"]])).bind!(int[])("foo").get() == [1, 2, 3]);
}

@("bindToCollectionWhenCommaListWithPlaceholdersShouldReturnPopulatedCollection") unittest
{
    assert(binder(source([["foo", "${bar}"], ["bar", "1,2,3"]])).bind!(int[])("foo").get() == [
        1, 2, 3
    ]);
}

@("bindToCollectionWhenCommaListAndIndexedShouldOnlyUseFirst") unittest
{
    auto first = source([["foo", "1,2"]]);
    auto second = source([["foo[0]", "2"], ["foo[1]", "3"]]);
    assert(binder(first, second).bind!(int[])("foo").get() == [1, 2]);
}

@("bindToCollectionWhenIndexedAndCommaListShouldOnlyUseFirst") unittest
{
    auto first = source([["foo[0]", "1"], ["foo[1]", "2"]]);
    auto second = source([["foo", "3,4"]]);
    assert(binder(first, second).bind!(int[])("foo").get() == [1, 2]);
}

@("bindToCollectionWhenEmptyStringShouldReturnEmptyCollection") unittest
{
    auto result = binder(source([["foo", ""]])).bind!(string[])("foo");
    assert(result.isBound() && result.get().length == 0);
}

@("bindToNonScalarCollectionShouldReturnPopulatedCollection") unittest
{
    auto b = binder(source([["foo[0].value", "a"], ["foo[1].value", "b"], ["foo[2].value", "c"]]));
    b.getDescriptors().add(descriptorOf!ValueBean());
    auto beans = b.bind!(ValueBean[])("foo").get();
    assert(beans.length == 3 && beans[0].getValue() == "a" && beans[2].getValue() == "c");
}

@("bindToListShouldAllowDuplicateValues") unittest
{
    assert(binder(source([["foo", "1,1,2"]])).bind!(int[])("foo").get() == [1, 1, 2]);
}

@("bindToBeanWithNestedCollectionShouldPopulateCollection") unittest
{
    auto b = binder(source([["foo.foos[0]", "a"], ["foo.foos[1]", "b"]]));
    b.getDescriptors().add(descriptorOf!(string[])());
    assert(b.bind!BeanWithNestedCollection("foo").get().getFoos() == ["a", "b"]);
}

@("bindToArrayWhenHasSpacesShouldTrim") unittest
{
    assert(binder(source([["foo", "1,  2,3"]])).bind!(int[])("foo").get() == [1, 2, 3]);
}

@("bindToCollectionShouldRespectCollectionType") unittest
{
    import flint.java.util : List;

    auto b = binder(source([["foo[0]", "1"], ["foo[1]", "2"]]));
    auto list = b.bind!(List!int)("foo").get();
    assert(list.size() == 2 && list.get(0) == 1 && list.get(1) == 2);
}

// ---- MapBinderTests -----------------------------------------------------------------------------------------

@("bindToMapShouldReturnPopulatedMap") unittest
{
    const result = binder(source([["foo.bar", "1"], ["foo.[baz]", "2"], ["foo[BiNg]", "3"]])).bind!(
            string[string])("foo").get();
    assert(same(result, ["bar": "1", "baz": "2", "BiNg": "3"]));
}

@("bindToMapShouldConvertMapValue") unittest
{
    const result = binder(source([["foo.bar", "1"], ["foo.[baz]", "2"]])).bind!(int[string])("foo").get();
    assert(same(result, ["bar": 1, "baz": 2]));
}

@("bindToMapWhenMultipleCandidateShouldBindFirst") unittest
{
    auto first = source([["foo.bar", "1"], ["foo.baz", "2"]]);
    auto second = source([["foo.baz", "3"], ["foo.bing", "4"]]);
    assert(binder(first, second).bind!(int[string])("foo").get() == ["bar": 1, "baz": 2, "bing": 4]);
}

@("bindToMapWhenHasExistingMapShouldReplaceOnlyNewContents") unittest
{
    auto existing = ["bar": 1000, "baz": 1001];
    const result = binder(source([["foo.bar", "1"]])).bind!(int[string])("foo",
            Bindable!(int[string]).ofInstance(existing)).get();
    assert(same(result, ["bar": 1, "baz": 1001]));
}

@("bindToMapWhenNoValueShouldReturnUnbound") unittest
{
    assert(!binder(source([["faf.bar", "1"]])).bind!(int[string])("foo").isBound());
}

@("bindToMapWhenEmptyStringShouldReturnEmptyMap") unittest
{
    auto result = binder(source([["foo", ""]])).bind!(string[string])("foo");
    assert(result.isBound() && result.get().length == 0);
}

@("bindToMapShouldConvertKey") unittest
{
    auto b = binder(source([["foo.foo-bar", "1"], ["foo.bar-baz", "2"]]));
    b.getDescriptors().add(descriptorOf!ExampleEnum());
    assert(b.bind!(int[ExampleEnum])("foo").get() == [
        ExampleEnum.FOO_BAR: 1,
        ExampleEnum.BAR_BAZ: 2
    ]);
}

@("bindToMapShouldBeGreedyForStrings") unittest
{
    const result = binder(source([["foo.aaa.bbb.ccc", "b-ccc"], ["foo.bbb.ccc.ddd", "a-ddd"]])).bind!(
            string[string])("foo").get();
    assert(same(result, ["aaa.bbb.ccc": "b-ccc", "bbb.ccc.ddd": "a-ddd"]));
}

@("bindingWithSquareBracketMap") unittest
{
    const result = binder(source([["foo.[x.y]", "a"], ["foo.[z]", "b"]])).bind!(string[string])("foo").get();
    assert(same(result, ["x.y": "a", "z": "b"]));
}

@("bindToMapShouldBindToMapValue") unittest
{
    auto b = binder(source([["foo.bar.baz", "1"], ["foo.bar.bin", "2"], ["foo.far.baz", "3"]]));
    b.getDescriptors().add(descriptorOf!(int[string])());
    auto result = b.bind!(int[string][string])("foo").get();
    assert(result["bar"] == ["baz": 1, "bin": 2] && result["far"] == ["baz": 3] && result.length == 2);
}

@("bindToPropertiesShouldBeEquivalentToMapOfStringString") unittest
{
    import flint.java.util : Map;

    auto map = binder(source([["foo.bar.baz", "1"], ["foo.bing", "2"]])).bind!(Map!(string, string))("foo").get();
    assert(map.get("bar.baz") == "1" && map.get("bing") == "2");
}

// ---- Flint: Optional ------------------------------------------------------------------------------------------

@("flint.bindOptional") unittest
{
    import flint.java.util : Optional;

    auto bound = binder(source([["server.port", "8081"]])).bind!(Optional!int)("server.port");
    assert(bound.get().isPresent() && bound.get().get() == 8081);
    assert(!binder(source(null)).bind!(Optional!int)("server.port").isBound());
}

import boot_tests.support : RegisterTests;

mixin RegisterTests;
