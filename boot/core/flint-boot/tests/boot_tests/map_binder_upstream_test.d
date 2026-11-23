// Ported from spring-boot v4.2.0: core/spring-boot/src/test/java/org/springframework/boot/
// context/properties/bind/MapBinderTests.java: the tests boot_tests/collection_binder_test.d does not port.
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: AssertJ assertions become D asserts; `Map<K, V>` and `EnumMap` are D associative
// arrays `V[K]`, or `flint.java.util.Map` where a bean holds one or the values are classes (an associative array of
// class references cannot be boxed in @safe code), `List<V>` is `V[]` or `flint.java.util.List!V`;
// the descriptors of nested types are registered as Flint AOT registers them; a placeholder resolver over an
// Environment is one over a configuration property source holding the same inlined property.
// Not ported: bindToMapWithPropertyEditorForKey and bindToMapWithPropertyEditorForValue (java.beans PropertyEditor
// converting to `Class`), bindToMapWithWildcardShouldConvertToTheRightType (Java wildcard generics and
// java.net.InetAddress conversion).
module boot_tests.map_binder_upstream_test;

import boot_tests.support : assertThrows;
import boot_tests.upstream_support : binderOf, source;
import flint.boot.context.properties.bind : BindException, BindResult, Bindable, Binder,
    PropertySourcesPlaceholdersResolver;
import flint.boot.context.properties.source : ConfigurationPropertySource;
import flint.java.util : LinkedHashMap, List, Map;

@safe:

/// `MapBinderTests.ExampleEnum`.
enum ExampleEnum
{
    FOO_BAR,
    BAR_BAZ,
    BAZ_BOO
}

/// `MapBinderTests.JavaBean`.
final class JavaBean
{
    private string value;

    string getValue()
    {
        return value;
    }

    void setValue(string value)
    {
        this.value = value;
    }
}

/// `MapBinderTests.Foo`.
final class Foo
{
    private string pattern;

    /// Part of the upstream test fixture.
    this()
    {
    }

    /// Part of the upstream test fixture.
    this(string pattern)
    {
        this.pattern = pattern;
    }

    string getPattern()
    {
        return pattern;
    }

    void setPattern(string pattern)
    {
        this.pattern = pattern;
    }
}

/// `MapBinderTests.NestableFoo`.
final class NestableFoo
{
    private Map!(string, NestableFoo) foos;
    private string value;

    /// Part of the upstream test fixture.
    this()
    {
        foos = new LinkedHashMap!(string, NestableFoo);
    }

    Map!(string, NestableFoo) getFoos()
    {
        return foos;
    }

    string getValue()
    {
        return value;
    }

    void setValue(string value)
    {
        this.value = value;
    }
}

/// `MapBinderTests.BeanWithGetterException`.
final class BeanWithGetterException
{
    private string[string] values;
    private bool hasValues;

    void setValues(string[string] values)
    {
        this.values = values;
        hasValues = true;
    }

    string[string] getValues()
    {
        import flint.java.lang : NullPointerException;

        if (!hasValues)
            throw new NullPointerException("Collections.unmodifiableMap(null)");
        return values;
    }
}

private string[] javaBeanValues(List!JavaBean beans)
{
    string[] values;
    foreach (bean; beans.toArray())
        values ~= bean.getValue();
    return values;
}

version (FlintObjectMapValues)
{
    // Gap: a `Map<String, Object>` does not bind nested maps for nested names (there is no `Object` value binding).
    import flint.engine.aot.any : Any;

    @("bindToMapWithEmptyPrefix") unittest
    {
        auto result = binderOf([source([["foo.bar", "1"]])]).bind!(Any[string])("").get();
        assert(result["foo"].get!(Any[string])["bar"].get!string == "1");
    }

    @("bindToMapWhenMapValueIsObjectShouldBindNestedMapValue") unittest
    {
        auto result = binderOf([
            source([
                ["foo.nested.bar.baz", "1"], ["foo.nested.bar.bin", "2"], [
                    "foo.nested.far.baz", "3"
                ], ["foo.nested.far.bin", "4"], ["faf.nested.far.bin", "x"]
            ])
        ]).bind!(Any[string])("foo").get();
        auto nested = result["nested"].get!(Any[string]);
        assert(nested.length == 2);
        auto bar = nested["bar"].get!(Any[string]);
        assert(bar["baz"].get!string == "1" && bar["bin"].get!string == "2");
        auto far = nested["far"].get!(Any[string]);
        assert(far["baz"].get!string == "3" && far["bin"].get!string == "4");
    }

    @("bindToMapWhenMapValueIsObjectAndNoRootShouldBindNestedMapValue") unittest
    {
        auto result = binderOf([
            source([["commit.id", "abcdefg"], ["branch", "master"], ["foo", "bar"]])
        ]).bind!(Any[string])("").get();
        assert(result["commit"].get!(Any[string])["id"].get!string == "abcdefg");
        assert(result["branch"].get!string == "master");
        assert(result["foo"].get!string == "bar");
    }
}

@("bindToMapShouldConvertMapValue") unittest
{
    const result = binderOf([
        source([["foo.bar", "1"], ["foo.[baz]", "2"], ["foo[BiNg]", "3"], ["faf.bar", "x"]])
    ]).bind!(int[string])("foo").get();
    assert(result.length == 3);
    assert(result["bar"] == 1 && result["baz"] == 2 && result["BiNg"] == 3);
}

@("bindToMapShouldBindNestedMapValue") unittest
{
    auto result = binderOf!(int[string], int[string][string])([
        source([
            ["foo.nested.bar.baz", "1"], ["foo.nested.bar.bin", "2"], ["foo.nested.far.baz", "3"],
            ["foo.nested.far.bin", "4"], ["faf.nested.far.bin", "x"]
        ])
    ]).bind!(int[string][string][string])("foo").get();
    auto nested = result["nested"];
    assert(nested.length == 2);
    assert(nested["bar"] == ["baz": 1, "bin": 2]);
    assert(nested["far"] == ["baz": 3, "bin": 4]);
}

@("bindToMapWhenEmptyRootNameShouldBindMap") unittest
{
    const result = binderOf([source([["bar.baz", "1"], ["bar.bin", "2"]])]).bind!(int[string])("").get();
    assert(result.length == 2);
    assert(result["bar.baz"] == 1 && result["bar.bin"] == 2);
}

version (FlintMapKeysDifferingByDashes)
{
    // Gap: map keys that differ only by dashes (`b-az`, `ba-z`) collapse into one entry.
    @("bindToMapWhenMultipleInSameSourceCandidateShouldBindFirst") unittest
    {
        const result = binderOf([
            source([["foo.bar", "1"], ["foo.b-az", "2"], ["foo.ba-z", "3"], ["foo.bin", "4"]])
        ]).bind!(int[string])("foo").get();
        assert(result.length == 4);
        assert(result["bar"] == 1 && result["b-az"] == 2 && result["ba-z"] == 3 && result["bin"] == 4);
    }
}

@("bindToMapShouldRespectMapType") unittest
{
    import flint.java.util : HashMap;

    auto b = binderOf([source([["foo.bar", "1"]])]);
    const defaultMap = b.bind!(Map!(string, int))("foo").get();
    const customMap = b.bind!(HashMap!(string, int))("foo").get();
    assert(customMap !is null && typeid(customMap) != typeid(defaultMap));
}

version (FlintCustomCollectionTypes)
{
    // Gap: a property typed as a custom map class (a LinkedHashMap subclass) gets a plain Map, which the setter
    // cannot take ("Any holds Map!(string, string)").

    /// `MyCustomNoDefaultConstructorMap`.
    final class MyCustomNoDefaultConstructorMap : LinkedHashMap!(string, string)
    {
        /// Part of the upstream test fixture.
        this(string[string] entries)
        {
            foreach (key, value; entries)
                put(key, value);
        }
    }

    /// `MyCustomWithDefaultConstructorMap`.
    final class MyCustomWithDefaultConstructorMap : LinkedHashMap!(string, string)
    {
    }

    /// `ExampleCustomNoDefaultConstructorBean`.
    final class ExampleCustomNoDefaultConstructorBean
    {
        private MyCustomNoDefaultConstructorMap items;

        /// Part of the upstream test fixture.
        this()
        {
            items = new MyCustomNoDefaultConstructorMap(["foo": "bar"]);
        }

        MyCustomNoDefaultConstructorMap getItems()
        {
            return items;
        }

        void setItems(MyCustomNoDefaultConstructorMap items)
        {
            this.items = items;
        }
    }

    /// `ExampleCustomWithDefaultConstructorBean`.
    final class ExampleCustomWithDefaultConstructorBean
    {
        private MyCustomWithDefaultConstructorMap items;

        /// Part of the upstream test fixture.
        this()
        {
            items = new MyCustomWithDefaultConstructorMap;
        }

        MyCustomWithDefaultConstructorMap getItems()
        {
            return items;
        }

        void setItems(MyCustomWithDefaultConstructorMap items)
        {
            this.items.clear();
            this.items.putAll(items);
        }
    }

    @("bindToMapWithNoDefaultConstructor") unittest
    {
        auto result = binderOf!MyCustomNoDefaultConstructorMap([source([["foo.items.a", "b"]])])
            .bind!ExampleCustomNoDefaultConstructorBean("foo").get();
        assert(result.getItems().size() == 2);
        assert(result.getItems().get("foo") == "bar" && result.getItems().get("a") == "b");
    }

    @("bindToMapWithDefaultConstructor") unittest
    {
        // gh-12322
        auto result = binderOf!MyCustomWithDefaultConstructorMap([source([["foo.items.a", "b"]])])
            .bind!ExampleCustomWithDefaultConstructorBean("foo").get();
        assert(result.getItems().size() == 1 && result.getItems().get("a") == "b");
    }
}

@("bindToMapShouldBeGreedyForScalars") unittest
{
    const result = binderOf!ExampleEnum([
        source([
            ["foo.aaa.bbb.ccc", "foo-bar"], ["foo.bbb.ccc.ddd", "BAR_BAZ"],
            ["foo.ccc.ddd.eee", "bazboo"]
        ])
    ]).bind!(ExampleEnum[string])("foo").get();
    assert(result.length == 3);
    assert(result["aaa.bbb.ccc"] == ExampleEnum.FOO_BAR);
    assert(result["bbb.ccc.ddd"] == ExampleEnum.BAR_BAZ);
    assert(result["ccc.ddd.eee"] == ExampleEnum.BAZ_BOO);
}

@("bindToMapWithPlaceholdersShouldBeGreedyForScalars") unittest
{
    ConfigurationPropertySource[] environment = [source([["foo", "boo"]])];
    auto b = new Binder([
        cast(ConfigurationPropertySource) source([["foo.aaa.bbb.ccc", "baz-${foo}"]])
    ], new PropertySourcesPlaceholdersResolver(environment));
    b.getDescriptors().add(imported!"flint.engine.aot.descriptor".descriptorOf!ExampleEnum());
    const result = b.bind!(ExampleEnum[string])("foo").get();
    assert(result["aaa.bbb.ccc"] == ExampleEnum.BAZ_BOO);
}

@("bindToMapWithNoPropertiesShouldReturnUnbound") unittest
{
    BindResult!(ExampleEnum[string]) result = binderOf!ExampleEnum([source(null)]).bind!(ExampleEnum[string])("foo");
    assert(!result.isBound());
}

version (FlintBindHandler)
{
    // Gap: the Binder has no BindHandler.
    import boot_tests.binder_upstream_test : RecordingBindHandler;

    @("bindToMapShouldTriggerOnSuccess") unittest
    {
        auto handler = new RecordingBindHandler;
        binderOf([source([["foo.bar", "1"]])]).bind!(int[string])("foo", Bindable!(int[string]).of(), handler);
        assert(handler.calls == ["onSuccess foo.bar", "onSuccess foo"]);
    }

    @("bindToMapStringArrayShouldTriggerOnSuccess") unittest
    {
        auto handler = new RecordingBindHandler;
        binderOf!(string[])([source([["foo.bar", "a,b,c"]])]).bind!(string[][string])("foo",
                Bindable!(string[][string]).of(), handler);
        assert(handler.calls == ["onSuccess foo.bar", "onSuccess foo"]);
    }
}

@("bindToMapNonScalarCollectionShouldPopulateMap") unittest
{
    auto map = binderOf!(JavaBean, List!JavaBean, Map!(string, List!JavaBean))([
        source([["foo.bar[0].value", "a"], ["foo.bar[1].value", "b"], ["foo.bar[2].value", "c"]])
    ]).bind!(Map!(string, List!JavaBean))("foo").get();
    auto bar = map.get("bar");
    assert(bar !is null);
    assert(javaBeanValues(bar) == ["a", "b", "c"]);
}

@("bindToMapShouldNotTreatClassWithStringConstructorAsScalar") unittest
{
    auto map = binderOf!(Foo, Map!(string, Foo))([source([["foo.bar.pattern", "1"]])]).bind!(Map!(string,
            Foo))("foo").get();
    auto bar = map.get("bar");
    assert(bar !is null);
    assert(bar.getPattern() == "1");
}

version (FlintMapDotKeysForCollections)
{
    // Gap: for collection values the map key is the next name element only, so `foo.bar.baz[0]` binds under
    // `bar`, not `bar.baz`.
    @("bindToMapStringArrayWithDotKeysShouldPreserveDot") unittest
    {
        auto map = binderOf!(string[])([
            source([["foo.bar.baz[0]", "a"], ["foo.bar.baz[1]", "b"], ["foo.bar.baz[2]", "c"]])
        ]).bind!(string[][string])("foo").get();
        assert(map["bar.baz"] == ["a", "b", "c"]);
    }

    @("bindToMapStringArrayWithDotKeysAndCommaSeparatedShouldPreserveDot") unittest
    {
        auto map = binderOf!(string[])([source([["foo.bar.baz", "a,b,c"]])]).bind!(string[][string])("foo").get();
        assert(map["bar.baz"] == ["a", "b", "c"]);
    }

    @("bindToMapStringCollectionWithDotKeysShouldPreserveDot") unittest
    {
        auto map = binderOf!(List!string, Map!(string, List!string))([
            source([["foo.bar.baz[0]", "a"], ["foo.bar.baz[1]", "b"], ["foo.bar.baz[2]", "c"]])
        ]).bind!(Map!(string, List!string))("foo").get();
        assert(map.get("bar.baz").toArray() == ["a", "b", "c"]);
    }

    @("bindToMapNonScalarCollectionWithDotKeysShouldBind") unittest
    {
        auto map = binderOf!(JavaBean, List!JavaBean, Map!(string, List!JavaBean))([
            source([
                ["foo.bar.baz[0].value", "a"], ["foo.bar.baz[1].value", "b"],
                ["foo.bar.baz[2].value", "c"]
            ])
        ]).bind!(Map!(string, List!JavaBean))("foo").get();
        auto barBaz = map.get("bar.baz");
        assert(barBaz !is null);
        assert(javaBeanValues(barBaz) == ["a", "b", "c"]);
    }
}

@("bindToListOfMaps") unittest
{
    auto list = binderOf!(int[], int[][string])([
        source([["foo[0].a", "1,2,3"], ["foo[1].b", "4,5,6"]])
    ]).bind!(List!(int[][string]))("foo").get();
    assert(list.get(0)["a"] == [1, 2, 3]);
    assert(list.get(1)["b"] == [4, 5, 6]);
}

@("bindToMapWithNumberKeyAndCommaSeparated") unittest
{
    auto map = binderOf!(string[])([source([["foo[0]", "a,b,c"], ["foo[1]", "e,f,g"]])]).bind!(
            string[][int])("foo").get();
    assert(map[0] == ["a", "b", "c"]);
    assert(map[1] == ["e", "f", "g"]);
}

@("bindToMapWithNumberKeyAndIndexed") unittest
{
    auto map = binderOf!(int[])([source([["foo[0][0]", "8"], ["foo[0][1]", "9"]])]).bind!(int[][int])("foo").get();
    assert(map[0] == [8, 9]);
}

@("bindingWithSquareBracketMap") unittest
{
    const map = binderOf([source([["foo.[x [B] y]", "[ball]"]])]).bind!(string[string])("foo").get();
    assert(map["x [B] y"] == "[ball]");
}

@("nestedMapsShouldNotBindToNull") unittest
{
    auto foo = binderOf!(Map!(string, NestableFoo))([
        source([
            ["foo.value", "one"], ["foo.foos.foo1.value", "two"], ["foo.foos.foo2.value", "three"]
        ])
    ]).bind!NestableFoo("foo");
    assert(foo.get().getValue() !is null);
    auto foo1 = foo.get().getFoos().get("foo1");
    assert(foo1 !is null);
    assert(foo1.getValue() == "two");
    auto foo2 = foo.get().getFoos().get("foo2");
    assert(foo2 !is null);
    assert(foo2.getValue() == "three");
}

@("nestedMapsWhenEmptyStringShouldReturnEmptyMap") unittest
{
    auto foo = binderOf!(Map!(string, NestableFoo))([
        source([["foo.value", "one"], ["foo.foos", ""]])
    ]).bind!NestableFoo("foo");
    assert(foo.get().getValue() == "one");
    assert(foo.get().getFoos().isEmpty());
}

version (FlintBindConverterConversionService)
{
    // Gap: the Binder cannot be given a ConversionService with extra converters (String to Map).
    import flint.core.convert.support : DefaultConversionService;

    /// `MapConverter`: "a,b" to a map of each item to itself.
    private string[string] mapConverter(string source)
    {
        import std.algorithm.iteration : splitter;

        string[string] map;
        foreach (item; source.splitter(','))
            map[item] = item;
        return map;
    }

    private Binder withMapConverter(ConfigurationPropertySource[] sources,
            PropertySourcesPlaceholdersResolver placeholders = null)
    {
        auto conversionService = new DefaultConversionService();
        conversionService.addConverter!(string, string[string])(&mapConverter);
        return new Binder(sources, placeholders, null, conversionService);
    }

    @("bindToMapWithCustomConverter") unittest
    {
        const map = withMapConverter([source([["foo", "a,b"]])]).bind!(string[string])("foo").get();
        assert(("a" in map) !is null && ("b" in map) !is null);
    }

    @("bindToMapWithCustomConverterAndChildElements") unittest
    {
        // gh-11892
        auto map = withMapConverter([source([["foo", "boom"], ["foo.a", "a"], ["foo.b", "b"]])]).bind!(
                string[string])("foo").get();
        assert(map["a"] == "a" && map["b"] == "b");
    }

    @("bindToMapWithPlaceholdersShouldResolve") unittest
    {
        ConfigurationPropertySource[] environment = [source([["bar", "bc"]])];
        const map = withMapConverter([source([["foo", "a${bar},${bar}d"]])],
                new PropertySourcesPlaceholdersResolver(environment)).bind!(string[string])("foo").get();
        assert(("abc" in map) !is null && ("bcd" in map) !is null);
    }

    @("bindToCustomMapWithoutCtorAndConverterShouldResolve") unittest
    {
        static final class CustomMap : LinkedHashMap!(string, string)
        {
            private string source;

            this(string source)
            {
                this.source = source;
            }

            string getSource()
            {
                return source;
            }
        }

        static final class CustomMapWithoutDefaultCtor
        {
            private CustomMap customMap;

            this(CustomMap customMap)
            {
                this.customMap = customMap;
            }

            CustomMap getCustomMap()
            {
                return customMap;
            }
        }

        auto conversionService = new DefaultConversionService();
        conversionService.addConverter!(string, CustomMap)((string value) => new CustomMap(value));
        auto b = new Binder([cast(ConfigurationPropertySource) source([["foo.custom-map",
                    "value"]])], null, null, conversionService);
        auto result = b.bind!CustomMapWithoutDefaultCtor("foo").get();
        assert(result.getCustomMap().getSource() == "value");
    }
}

version (FlintScalarValueForMap)
{
    // Gap: a scalar value under a map's name (`foo=a,b`) is ignored (unbound) instead of failing for lack of a
    // String-to-Map converter.
    @("bindToMapWithNoConverterForValue") unittest
    {
        auto b = binderOf([source([["foo", "a,b"]])]);
        assertThrows!BindException(() { b.bind!(string[string])("foo"); });
    }
}

@("bindToImmutableMapShouldReturnPopulatedMap") unittest
{
    auto existing = ["a": "b"];
    const result = binderOf([source([["foo.values.c", "d"], ["foo.values.e", "f"]])]).bind!(
            string[string])("foo.values", Bindable!(string[string]).of().withExistingValue(existing)).get();
    assert(result.length == 3);
    assert(result["a"] == "b" && result["c"] == "d" && result["e"] == "f");
}

version (FlintGetterInvocation)
{
    // Gap: the binder calls the getter of a map property it is about to bind, and lets its exception escape.
    @("bindToBeanWithExceptionInGetterForExistingValue") unittest
    {
        auto result = binderOf!(string[string])([source([["foo.values.a", "b"]])]).bind!BeanWithGetterException("foo")
            .get();
        assert(result.getValues() == ["a": "b"]);
    }
}

@("bindToEnumMapShouldBind") unittest
{
    const result = binderOf!ExampleEnum([source([["props.foo-bar", "value"]])]).bind!(
            string[ExampleEnum])("props").get();
    assert(result.length == 1 && result[ExampleEnum.FOO_BAR] == "value");
}

import boot_tests.support : RegisterTests;

mixin RegisterTests;
