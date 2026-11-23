// Ported from spring-boot v4.2.0: core/spring-boot/src/test/java/org/springframework/boot/
// context/properties/bind/JavaBeanBinderTests.java: the tests boot_tests/binder_test.d does not port.
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: Java beans become D classes with public Java-named getters and setters
// (rulebook R6); `List`, `Set`, `Collection` and `Map` are `flint.java.util`'s; the descriptors of nested types are
// registered with the binder as Flint AOT's generated code does, and a constructor-bound type gets the constructor
// descriptor AOT emits. A Java method cannot be called `is` in D, so ExampleWithInvalidAccessors keeps only `get`.
// Not ported: bindWhenValueIsConvertedWithPropertyEditorShouldBind (java.beans PropertyEditor converting to a
// `Class`), beanPropertiesPreferMatchingType (overrides JavaBeanBinder.Bean's reflective method ordering),
// bindWhenHasPackagePrivateSetterShouldBind (Java reflection reaching a package-private setter; Flint descriptors
// list public members) and bindWhenHasBridgeMethods (Java generic bridge methods).
module boot_tests.java_bean_binder_upstream_test;

import boot_tests.support : assertThrows;
import flint.boot.context.properties.bind : BindException, BindResult, Bindable, Binder;
import flint.boot.context.properties.source : ConfigurationProperty, ConfigurationPropertyName,
    ConfigurationPropertySource, ConfigurationPropertyState, MapConfigurationPropertySource;
import flint.engine.aot.descriptor : descriptorOf;
import flint.java.util : ArrayList, Collection, LinkedHashMap, LinkedHashSet, List, Map, Set;

@safe:

private MapConfigurationPropertySource source(string[2][] entries)
{
    return new MapConfigurationPropertySource("test", entries);
}

/// A binder over `sources` that knows the descriptors of the types `Nested`.
private Binder binder(Nested...)(ConfigurationPropertySource[] sources...)
{
    auto b = new Binder(sources.dup);
    static foreach (T; Nested)
        b.getDescriptors().add(descriptorOf!T());
    return b;
}

/// `MockConfigurationPropertySource.nonIterable()`.
final class NonIterableSource : ConfigurationPropertySource
{
    private MapConfigurationPropertySource map;

    /// Part of the upstream test fixture.
    this(MapConfigurationPropertySource map)
    {
        this.map = map;
    }

    ConfigurationProperty getConfigurationProperty(ConfigurationPropertyName name)
    {
        return map.getConfigurationProperty(name);
    }

    /// Part of the upstream test fixture.
    ConfigurationPropertyState containsDescendantOf(ConfigurationPropertyName)
    {
        return ConfigurationPropertyState.UNKNOWN;
    }

    /// Part of the upstream test fixture.
    ConfigurationPropertyName[] iterator()
    {
        return null;
    }

    string getUnderlyingSourceName()
    {
        return map.getUnderlyingSourceName();
    }
}

/// `JavaBeanBinderTests.ExampleEnum`.
enum ExampleEnum
{
    FOO_BAR,
    BAR_BAZ
}

/// `ExampleValueBean`.
class ExampleValueBean
{
    private int intValue;
    private long longValue;
    private string stringValue;
    private ExampleEnum enumValue;

    int getIntValue()
    {
        return intValue;
    }

    void setIntValue(int intValue)
    {
        this.intValue = intValue;
    }

    long getLongValue()
    {
        return longValue;
    }

    void setLongValue(long longValue)
    {
        this.longValue = longValue;
    }

    string getStringValue()
    {
        return stringValue;
    }

    void setStringValue(string stringValue)
    {
        this.stringValue = stringValue;
    }

    ExampleEnum getEnumValue()
    {
        return enumValue;
    }

    void setEnumValue(ExampleEnum enumValue)
    {
        this.enumValue = enumValue;
    }
}

/// `ExampleMapBean`.
final class ExampleMapBean
{
    private Map!(ExampleEnum, int) map;

    Map!(ExampleEnum, int) getMap()
    {
        return map;
    }

    void setMap(Map!(ExampleEnum, int) map)
    {
        this.map = map;
    }
}

/// `ExampleListBean`.
final class ExampleListBean
{
    private List!ExampleEnum list;

    List!ExampleEnum getList()
    {
        return list;
    }

    void setList(List!ExampleEnum list)
    {
        this.list = list;
    }
}

/// `ExampleSetBean`.
final class ExampleSetBean
{
    private Set!ExampleEnum set;

    Set!ExampleEnum getSet()
    {
        return set;
    }

    void setSet(Set!ExampleEnum set)
    {
        this.set = set;
    }
}

/// `ExampleCollectionBean`.
final class ExampleCollectionBean
{
    private Collection!ExampleEnum collection;

    Collection!ExampleEnum getCollection()
    {
        return collection;
    }

    void setCollection(Collection!ExampleEnum collection)
    {
        this.collection = collection;
    }
}

/// `ExampleMapBeanWithoutSetter`.
final class ExampleMapBeanWithoutSetter
{
    private Map!(ExampleEnum, int) map;

    /// Part of the upstream test fixture.
    this()
    {
        map = new LinkedHashMap!(ExampleEnum, int);
    }

    Map!(ExampleEnum, int) getMap()
    {
        return map;
    }
}

/// `ExampleListBeanWithoutSetter`.
final class ExampleListBeanWithoutSetter
{
    private List!ExampleEnum list;

    /// Part of the upstream test fixture.
    this()
    {
        list = new ArrayList!ExampleEnum;
    }

    List!ExampleEnum getList()
    {
        return list;
    }
}

/// `ExampleSetBeanWithoutSetter`.
final class ExampleSetBeanWithoutSetter
{
    private Set!ExampleEnum set;

    /// Part of the upstream test fixture.
    this()
    {
        set = new LinkedHashSet!ExampleEnum;
    }

    Set!ExampleEnum getSet()
    {
        return set;
    }
}

/// `ExampleCollectionBeanWithoutSetter`.
final class ExampleCollectionBeanWithoutSetter
{
    private Collection!ExampleEnum collection;

    /// Part of the upstream test fixture.
    this()
    {
        collection = new ArrayList!ExampleEnum;
    }

    Collection!ExampleEnum getCollection()
    {
        return collection;
    }
}

/// `ExampleNestedBean`.
class ExampleNestedBean
{
    private ExampleValueBean valueBean;

    ExampleValueBean getValueBean()
    {
        return valueBean;
    }

    void setValueBean(ExampleValueBean valueBean)
    {
        this.valueBean = valueBean;
    }
}

/// `ExampleNestedBeanWithoutSetter`.
final class ExampleNestedBeanWithoutSetter
{
    private ExampleValueBean valueBean;

    /// Part of the upstream test fixture.
    this()
    {
        valueBean = new ExampleValueBean;
    }

    ExampleValueBean getValueBean()
    {
        return valueBean;
    }
}

/// `ExampleNestedBeanWithoutSetterOrType`.
final class ExampleNestedBeanWithoutSetterOrType
{
    private ExampleValueBean valueBean;

    /// Part of the upstream test fixture.
    this()
    {
        valueBean = new ExampleValueBean;
    }

    Object getValueBean()
    {
        return valueBean;
    }
}

/// `ExampleImmutableNestedBeanWithoutSetter.NestedImmutable`.
final class NestedImmutable
{
    string getFoo()
    {
        return "foo";
    }
}

/// `ExampleImmutableNestedBeanWithoutSetter`.
final class ExampleImmutableNestedBeanWithoutSetter
{
    private NestedImmutable nested;

    /// Part of the upstream test fixture.
    this()
    {
        nested = new NestedImmutable;
    }

    NestedImmutable getNested()
    {
        return nested;
    }
}

/// `ExampleNestedSubclassBean.ExampleValueSubclassBean`.
final class ExampleValueSubclassBean : ExampleValueBean
{
    private int subIntValue;

    int getSubIntValue()
    {
        return subIntValue;
    }

    void setSubIntValue(int intValue)
    {
        this.subIntValue = intValue;
    }
}

/// `ExampleNestedSubclassBean`.
final class ExampleNestedSubclassBean : ExampleNestedBean
{
    private ExampleValueSubclassBean subclassValueBean;

    override ExampleValueSubclassBean getValueBean()
    {
        return subclassValueBean;
    }

    void setValueBean(ExampleValueSubclassBean valueBean)
    {
        this.subclassValueBean = valueBean;
    }
}

/// `ExampleWithNonDefaultConstructor`.
final class ExampleWithNonDefaultConstructor
{
    private string value;

    /// Part of the upstream test fixture.
    this(string value)
    {
        this.value = value;
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

/// `ExampleSuperClassBean`.
class ExampleSuperClassBean
{
    private int intValue;

    int getIntValue()
    {
        return intValue;
    }

    void setIntValue(int intValue)
    {
        this.intValue = intValue;
    }
}

/// `ExampleSubclassBean`.
final class ExampleSubclassBean : ExampleSuperClassBean
{
    private long longValue;

    long getLongValue()
    {
        return longValue;
    }

    void setLongValue(long longValue)
    {
        this.longValue = longValue;
    }
}

/// `ExampleMismatchBean`.
final class ExampleMismatchBean
{
    private int value;

    string getValue()
    {
        import std.conv : to;

        return value.to!string;
    }

    void setValue(int value)
    {
        this.value = value;
    }
}

/// `ExampleWithThrowingGetters`.
final class ExampleWithThrowingGetters
{
    import flint.java.lang : RuntimeException;

    private int value;

    int getValue()
    {
        return value;
    }

    void setValue(int value)
    {
        this.value = value;
    }

    List!string getNames()
    {
        throw new RuntimeException();
    }

    ExampleValueBean getNested()
    {
        throw new RuntimeException();
    }
}

/// `ExampleWithSelfReference`.
final class ExampleWithSelfReference
{
    private int value;
    private ExampleWithSelfReference self;

    int getValue()
    {
        return value;
    }

    void setValue(int value)
    {
        this.value = value;
    }

    ExampleWithSelfReference getSelf()
    {
        return self;
    }

    void setSelf(ExampleWithSelfReference self)
    {
        this.self = self;
    }
}

/// `ExampleWithInvalidAccessors` (without `is()`, a D keyword).
final class ExampleWithInvalidAccessors
{
    import flint.java.lang : IllegalArgumentException;

    private string name;

    string getName()
    {
        return name;
    }

    void setName(string name)
    {
        this.name = name;
    }

    /// Part of the upstream test fixture.
    string get()
    {
        throw new IllegalArgumentException("should not be invoked");
    }
}

/// `ExampleWithStaticAccessors`.
final class ExampleWithStaticAccessors
{
    private static string name;
    private int counter;

    static string getName()
    {
        return name;
    }

    static void setName(string name)
    {
        ExampleWithStaticAccessors.name = name;
    }

    int getCounter()
    {
        return counter;
    }

    void setCounter(int counter)
    {
        this.counter = counter;
    }
}

/// `GenericValue<T>`.
final class GenericValue(T)
{
    private T value;

    T getValue()
    {
        return value;
    }

    void setValue(T value)
    {
        this.value = value;
    }
}

/// `ExampleWithGenericMap`.
final class ExampleWithGenericMap
{
    private Map!(string, GenericValue!int) integers;
    private Map!(string, GenericValue!bool) booleans;

    /// Part of the upstream test fixture.
    this()
    {
        integers = new LinkedHashMap!(string, GenericValue!int);
        booleans = new LinkedHashMap!(string, GenericValue!bool);
    }

    Map!(string, GenericValue!int) getIntegers()
    {
        return integers;
    }

    Map!(string, GenericValue!bool) getBooleans()
    {
        return booleans;
    }
}

/// `PropertyWithOverloadedSetter`.
final class PropertyWithOverloadedSetter
{
    private string property;

    void setProperty(int property)
    {
        import std.conv : to;

        this.property = property.to!string;
    }

    void setProperty(string property)
    {
        this.property = property;
    }

    string getProperty()
    {
        return property;
    }
}

/// `JavaBeanWithGetSetIs`.
final class JavaBeanWithGetSetIs
{
    private string[] names;

    string[] getNames()
    {
        return names;
    }

    void setNames(string[] names)
    {
        this.names = names;
    }

    /// Part of the upstream test fixture.
    bool isNames()
    {
        return names.length > 0;
    }
}

/// `JavaBeanWithGetIs`.
final class JavaBeanWithGetIs
{
    private List!string names;

    /// Part of the upstream test fixture.
    this()
    {
        names = new ArrayList!string;
    }

    /// Part of the upstream test fixture.
    bool isNames()
    {
        return !names.isEmpty();
    }

    List!string getNames()
    {
        return names;
    }
}

private ExampleEnum[] elements(Collection!ExampleEnum collection)
{
    return collection is null ? null : collection.toArray();
}

private void assertEnumMap(Map!(ExampleEnum, int) map)
{
    assert(map.keySet().toArray() == [ExampleEnum.FOO_BAR, ExampleEnum.BAR_BAZ]);
    assert(map.get(ExampleEnum.FOO_BAR) == 1 && map.get(ExampleEnum.BAR_BAZ) == 2);
}

@("bindToClassShouldBindToMap") unittest
{
    auto bean = binder!(ExampleEnum, Map!(ExampleEnum, int))(source([
            ["foo.map.foo-bar", "1"], ["foo.map.bar-baz", "2"]
    ])).bind!ExampleMapBean("foo").get();
    assertEnumMap(bean.getMap());
}

@("bindToClassShouldBindToList") unittest
{
    auto bean = binder!(ExampleEnum, List!ExampleEnum)(source([
            ["foo.list[0]", "foo-bar"], ["foo.list[1]", "bar-baz"]
    ])).bind!ExampleListBean("foo").get();
    assert(elements(bean.getList()) == [ExampleEnum.FOO_BAR, ExampleEnum.BAR_BAZ]);
}

version (FlintUnboundIndexedElements)
{
    // Gap: binding stops at the first missing index instead of failing with UnboundConfigurationPropertiesException.
    import flint.boot.context.properties.bind : UnboundConfigurationPropertiesException;

    @("bindToListIfUnboundElementsPresentShouldThrowException") unittest
    {
        auto b = binder!(ExampleEnum, List!ExampleEnum)(source([
                ["foo.list[0]", "foo-bar"], ["foo.list[2]", "bar-baz"]
        ]));
        try
        {
            b.bind!ExampleListBean("foo");
            assert(false, "expected a BindException");
        }
        catch (BindException expected)
            assert(cast(UnboundConfigurationPropertiesException) expected.next !is null);
    }
}

@("bindToClassShouldBindToSet") unittest
{
    auto bean = binder!(ExampleEnum, Set!ExampleEnum)(source([
            ["foo.set[0]", "foo-bar"], ["foo.set[1]", "bar-baz"]
    ])).bind!ExampleSetBean("foo").get();
    assert(elements(bean.getSet()) == [ExampleEnum.FOO_BAR, ExampleEnum.BAR_BAZ]);
}

version (FlintCollectionInterfaceBinding)
{
    // Gap: a property typed `Collection<E>` cannot be bound (its descriptor has no collection builders).
    @("bindToClassShouldBindToCollection") unittest
    {
        auto bean = binder!(ExampleEnum, Collection!ExampleEnum)(source([
                ["foo.collection[0]", "foo-bar"], ["foo.collection[1]", "bar-baz"]
        ])).bind!ExampleCollectionBean("foo").get();
        assert(elements(bean.getCollection()) == [ExampleEnum.FOO_BAR, ExampleEnum.BAR_BAZ]);
    }
}

version (FlintDelimiter)
{
    // Gap: `@Delimiter` is not ported; collections split on `,` only.
    import flint.boot.convert : Delimiter;

    /// `ExampleCollectionBeanWithDelimiter`.
    final class ExampleCollectionBeanWithDelimiter
    {
        @Delimiter("|")
        private Collection!ExampleEnum collection;

        Collection!ExampleEnum getCollection()
        {
            return collection;
        }

        void setCollection(Collection!ExampleEnum collection)
        {
            this.collection = collection;
        }
    }

    @("bindToClassShouldBindToCollectionWithDelimiter") unittest
    {
        auto bean = binder!(ExampleEnum, Collection!ExampleEnum)(source([
                ["foo.collection", "foo-bar|bar-baz"]
        ])).bind!ExampleCollectionBeanWithDelimiter("foo").get();
        assert(elements(bean.getCollection()) == [ExampleEnum.FOO_BAR, ExampleEnum.BAR_BAZ]);
    }
}

@("bindToClassWhenHasNoSetterShouldBindToMap") unittest
{
    auto bean = binder!(ExampleEnum, Map!(ExampleEnum, int))(source([
            ["foo.map.foo-bar", "1"], ["foo.map.bar-baz", "2"]
    ])).bind!ExampleMapBeanWithoutSetter("foo").get();
    assertEnumMap(bean.getMap());
}

version (FlintBindIntoExistingCollection)
{
    // Gap: a collection property without a setter is not bound into the collection its getter returns.
    @("bindToClassWhenHasNoSetterShouldBindToList") unittest
    {
        auto bean = binder!(ExampleEnum, List!ExampleEnum)(source([
                ["foo.list[0]", "foo-bar"], ["foo.list[1]", "bar-baz"]
        ])).bind!ExampleListBeanWithoutSetter("foo").get();
        assert(elements(bean.getList()) == [ExampleEnum.FOO_BAR, ExampleEnum.BAR_BAZ]);
    }

    @("bindToClassWhenHasNoSetterShouldBindToSet") unittest
    {
        auto bean = binder!(ExampleEnum, Set!ExampleEnum)(source([
                ["foo.set[0]", "foo-bar"], ["foo.set[1]", "bar-baz"]
        ])).bind!ExampleSetBeanWithoutSetter("foo").get();
        assert(elements(bean.getSet()) == [ExampleEnum.FOO_BAR, ExampleEnum.BAR_BAZ]);
    }

    @("bindToClassWhenHasNoSetterShouldBindToCollection") unittest
    {
        auto bean = binder!(ExampleEnum, Collection!ExampleEnum)(source([
                ["foo.collection[0]", "foo-bar"], ["foo.collection[1]", "bar-baz"]
        ])).bind!ExampleCollectionBeanWithoutSetter("foo").get();
        assert(elements(bean.getCollection()) == [ExampleEnum.FOO_BAR, ExampleEnum.BAR_BAZ]);
    }

    @("bindWhenBeanWithGetIsMethodsFoundDoesNotUseIsGetter") unittest
    {
        auto bean = binder!(List!string)(source([["test.names", "spring,boot"]])).bind!JavaBeanWithGetIs("test").get();
        assert(bean.getNames().toArray() == ["spring", "boot"]);
    }
}

version (FlintBindNestedByInstanceType)
{
    // Gap: a getter typed `Object` is not bound through the runtime type of the instance it returns.
    @("bindToClassWhenIterableShouldBindNestedBasedOnInstance") unittest
    {
        auto bean = binder!ExampleValueBean(source([
                ["foo.value-bean.int-value", "123"], ["foo.value-bean.string-value", "foo"]
        ])).bind!ExampleNestedBeanWithoutSetterOrType("foo").get();
        auto valueBean = cast(ExampleValueBean) bean.getValueBean();
        assert(valueBean.getIntValue() == 123);
        assert(valueBean.getStringValue() == "foo");
    }
}

@("bindToClassWhenNotIterableShouldNotBindNestedBasedOnInstance") unittest
{
    // If we can't tell that binding will happen, we don't want to randomly invoke getters on the class and cause
    // side effects
    auto bean = binder!ExampleValueBean(new NonIterableSource(source([
                ["foo.value-bean.int-value", "123"], ["foo.value-bean.string-value", "foo"]
    ]))).bind!ExampleNestedBeanWithoutSetterOrType("foo");
    assert(!bean.isBound());
}

@("bindToClassWhenHasNoSetterShouldBindNested") unittest
{
    auto bean = binder!ExampleValueBean(source([
            ["foo.value-bean.int-value", "123"], ["foo.value-bean.string-value", "foo"]
    ])).bind!ExampleNestedBeanWithoutSetter("foo").get();
    assert(bean.getValueBean().getIntValue() == 123);
    assert(bean.getValueBean().getStringValue() == "foo");
}

version (FlintReadOnlyPropertyFailure)
{
    // Gap: a bound value for a getter-only property is ignored instead of failing ("No setter found").
    @("bindToClassWhenHasNoSetterAndImmutableShouldThrowException") unittest
    {
        auto b = binder!NestedImmutable(source([["foo.nested.foo", "bar"]]));
        assertThrows!BindException(() { b.bind!ExampleImmutableNestedBeanWithoutSetter("foo"); });
    }
}

version (FlintInheritedBeanProperties)
{
    // Gap: a bean's descriptor lists only the properties its own class declares, not inherited ones.
    @("bindToClassWithOverriddenPropertyShouldSetSubclassProperty") unittest
    {
        auto bean = binder!(ExampleValueBean, ExampleValueSubclassBean)(source([
                ["foo.value-bean.int-value", "123"], ["foo.value-bean.sub-int-value", "456"]
        ])).bind!ExampleNestedSubclassBean("foo").get();
        assert(bean.getValueBean() !is null);
        assert(bean.getValueBean().getIntValue() == 123);
        assert(bean.getValueBean().getSubIntValue() == 456);
    }
}

@("bindToClassWhenNoDefaultConstructorShouldBind") unittest
{
    import flint.engine.aot.any : Any;
    import flint.engine.aot.descriptor : ConstructorDescriptor, ParameterDescriptor;

    auto b = binder(source([["foo.value", "bar"]]));
    auto descriptor = descriptorOf!ExampleWithNonDefaultConstructor();
    descriptor.constructors = [
        ConstructorDescriptor([ParameterDescriptor("value", "string")], null,
                (scope Any[] a) => Any.of(new ExampleWithNonDefaultConstructor(a[0].isNull() ? null : a[0].get!string)))
    ];
    b.getDescriptors().add(descriptor);
    auto bean = b.bind!ExampleWithNonDefaultConstructor("foo");
    assert(bean.isBound());
    auto boundBean = bean.get();
    assert(boundBean.getValue() == "bar");
}

@("bindToInstanceWhenNoDefaultConstructorShouldBind") unittest
{
    auto bean = new ExampleWithNonDefaultConstructor("faf");
    const boundBean = binder(source([["foo.value", "bar"]])).bind!ExampleWithNonDefaultConstructor("foo",
            Bindable!ExampleWithNonDefaultConstructor.of().withExistingValue(bean)).get();
    assert(boundBean is bean);
    assert(bean.getValue() == "bar");
}

version (FlintInheritedBeanProperties)
{
    // Gap: a bean's descriptor lists only the properties its own class declares (intValue stays 0).
    @("bindToClassShouldBindHierarchy") unittest
    {
        auto bean = binder(source([["foo.int-value", "123"], ["foo.long-value", "456"]])).bind!ExampleSubclassBean(
                "foo").get();
        assert(bean.getIntValue() == 123);
        assert(bean.getLongValue() == 456);
    }
}

version (FlintBindHandler)
{
    // Gap: the Binder has no BindHandler (IgnoreErrorsBindHandler).
    import flint.boot.context.properties.bind.handler : IgnoreErrorsBindHandler;

    @("bindToClassWhenPropertyCannotBeConvertedAndIgnoreErrorsShouldNotSetValue") unittest
    {
        auto handler = new IgnoreErrorsBindHandler();
        auto bean = binder!ExampleEnum(source([
                ["foo.int-value", "12"], ["foo.long-value", "bang"], ["foo.string-value", "foo"],
                ["foo.enum-value", "foo-bar"]
        ])).bind!ExampleValueBean("foo", Bindable!ExampleValueBean.of(), handler).get();
        assert(bean.getIntValue() == 12);
        assert(bean.getLongValue() == 0);
        assert(bean.getStringValue() == "foo");
        assert(bean.getEnumValue() == ExampleEnum.FOO_BAR);
    }
}

version (FlintMismatchedAccessorTypes)
{
    // Gap: the property takes the getter's type, so the value is converted to string and the int setter fails.
    @("bindToClassWhenMismatchedGetSetShouldBind") unittest
    {
        auto bean = binder(source([["foo.value", "123"]])).bind!ExampleMismatchBean("foo").get();
        assert(bean.getValue() == "123");
    }
}

version (FlintNonIterableSourceBinding)
{
    // Gap: a JavaBean is not bound from a source that cannot list its names (containsDescendantOf UNKNOWN).
    @("bindToClassShouldNotInvokeExtraMethods") unittest
    {
        auto bean = binder(new NonIterableSource(source([["foo.value", "123"]]))).bind!ExampleWithThrowingGetters(
                "foo").get();
        assert(bean.getValue() == 123);
    }
}

@("bindToClassWithSelfReferenceShouldBind") unittest
{
    auto bean = binder(source([["foo.value", "123"]])).bind!ExampleWithSelfReference("foo").get();
    assert(bean.getValue() == 123);
}

@("bindToInstanceWithExistingValueShouldReturnUnbound") unittest
{
    auto existingValue = new ExampleNestedBean;
    auto valueBean = new ExampleValueBean;
    existingValue.setValueBean(valueBean);
    auto result = binder!ExampleValueBean(source(null)).bind!ExampleNestedBean("foo",
            Bindable!ExampleNestedBean.of().withExistingValue(existingValue));
    assert(!result.isBound());
}

version (FlintJavaTimeConversion)
{
    // Gap: there is no LocalDate converter honouring `@DateTimeFormat`.
    import flint.format.annotation : DateTimeFormat, ISO;
    import flint.java.time : LocalDate;

    /// `ConverterAnnotatedExampleBean`.
    final class ConverterAnnotatedExampleBean
    {
        @DateTimeFormat(ISO.DATE)
        private LocalDate date;

        LocalDate getDate()
        {
            return date;
        }

        void setDate(LocalDate date)
        {
            this.date = date;
        }
    }

    @("bindWithAnnotations") unittest
    {
        auto bean = binder(source([["foo.date", "2014-04-01"]])).bind!ConverterAnnotatedExampleBean("foo").get();
        assert(bean.getDate().toString() == "2014-04-01");
    }
}

@("bindToClassShouldIgnoreInvalidAccessors") unittest
{
    auto bean = binder(source([["foo.name", "something"]])).bind!ExampleWithInvalidAccessors("foo").get();
    assert(bean.getName() == "something");
}

@("bindToClassShouldIgnoreStaticAccessors") unittest
{
    auto bean = binder(source([["foo.name", "invalid"], ["foo.counter", "42"]])).bind!ExampleWithStaticAccessors(
            "foo").get();
    assert(ExampleWithStaticAccessors.getName() is null);
    assert(bean.getCounter() == 42);
}

@("bindToClassShouldCacheWithGenerics") unittest
{
    // gh-16821
    auto bean = binder!(GenericValue!int, GenericValue!bool, Map!(string, GenericValue!int),
            Map!(string, GenericValue!bool))(source([
            ["foo.integers[a].value", "1"], ["foo.booleans[b].value", "true"]
    ])).bind!ExampleWithGenericMap("foo").get();
    auto a = bean.getIntegers().get("a");
    assert(a !is null);
    assert(a.getValue() == 1);
    auto b = bean.getBooleans().get("b");
    assert(b !is null);
    assert(b.getValue());
}

version (FlintOverloadedSetters)
{
    // Gap: with overloaded setters the first declared (int) is used, so binding a string fails.
    @("bindToClassWithOverloadedSetterShouldUseSetterThatMatchesField") unittest
    {
        // gh-16206
        auto bean = binder(source([["foo.property", "some string"]])).bind!PropertyWithOverloadedSetter("foo").get();
        assert(bean.getProperty() == "some string");
    }
}

version (FlintGetSetIsAccessors)
{
    // Gap: a bean with getNames, setNames and isNames is left unbound.
    @("bindWhenBeanWithGetSetIsMethodsFoundUsesGetterThatMatchesSetter") unittest
    {
        // gh-23007
        auto bean = binder(source([["test.names", "spring,boot"]])).bind!JavaBeanWithGetSetIs("test").get();
        assert(bean.getNames() == ["spring", "boot"]);
    }
}

import boot_tests.support : RegisterTests;

mixin RegisterTests;
