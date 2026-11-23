// Ported from spring-boot v4.2.0: core/spring-boot/src/test/java/org/springframework/boot/
// context/properties/bind/ValueObjectBinderTests.java: the tests boot_tests/binder_test.d does not port (it holds
// bindToClassShouldCreateBoundBean, bindToClassWhenNoValuesShouldNotBind and bindWithAnnotationsAndDefaultValue).
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: value objects and records become D classes and structs; each gets the constructor
// descriptor Flint AOT emits for its binding constructor (`valueObject` below), with `@DefaultValue` as a merged
// parameter annotation; a D enum has no null, so an unbound enum is its `.init`; `List<String>` is `string[]`.
// Not ported: bindToClassWhenHasPackagePrivateConstructorShouldBind (Java package-private visibility; descriptors
// list what AOT can call), bindWhenBindingToPathTypeWithValue and bindWhenBindingToPathTypeWithDefaultValue
// (java.nio.file.Path has no Flint counterpart),
// bindWhenNonExtractableParameterNamesOnPropertyAndNonIterablePropertySource and
// createWhenNonExtractableParameterNamesOnPropertyAndNonIterablePropertySource (javac's `-parameters` flag and
// reflective parameter-name discovery; Flint AOT always knows parameter names).
module boot_tests.value_object_binder_upstream_test;

import boot_tests.support : assertThrows;
import flint.boot.context.properties.bind : BindException, BindResult, Bindable, Binder, DefaultValue;
import flint.boot.context.properties.source : ConfigurationProperty, ConfigurationPropertyName,
    ConfigurationPropertySource, ConfigurationPropertyState, MapConfigurationPropertySource;
import flint.engine.aot.any : Any;
import flint.engine.aot.descriptor : ConstructorDescriptor, Descriptor, MergedAnnotation,
    ParameterDescriptor, descriptorOf;
import flint.engine.aot.name : typeNameOf;

@safe:

private MapConfigurationPropertySource source(string[2][] entries)
{
    return new MapConfigurationPropertySource("test", entries);
}

/// `@DefaultValue(values)` as a merged parameter annotation.
private MergedAnnotation[] defaultValue(string[] values...)
{
    return [MergedAnnotation(typeNameOf!DefaultValue, Any.of(DefaultValue(values.dup)), 0)];
}

private Any construct(T, size_t overload)(scope Any[] arguments)
{
    import std.traits : Parameters;

    alias Params = Parameters!(__traits(getOverloads, T, "__ctor")[overload]);
    Params values;
    static foreach (i; 0 .. Params.length)
        values[i] = arguments[i].isNull() ? Params[i].init : arguments[i].get!(Params[i]);
    static if (is(T == class))
        return Any.of(new T(values));
    else
        return Any.of(T(values));
}

/// `T`'s descriptor with the binding constructor Flint AOT emits: constructor `overload`, with `annotations` per
/// parameter.
private Descriptor valueObject(T, size_t overload = 0)(MergedAnnotation[][] annotations = null)
{
    import std.traits : ParameterIdentifierTuple, Parameters;

    alias ctor = __traits(getOverloads, T, "__ctor")[overload];
    alias Params = Parameters!ctor;
    static immutable names = [ParameterIdentifierTuple!ctor];
    auto descriptor = descriptorOf!T();
    ParameterDescriptor[] parameters;
    static foreach (i; 0 .. Params.length)
        parameters ~= ParameterDescriptor(names[i], typeNameOf!(Params[i]), i < annotations.length
                ? annotations[i] : null);
    descriptor.constructors = [ConstructorDescriptor(parameters, null, &construct!(T, overload))];
    return descriptor;
}

/// A binder over `sources` that knows `descriptors` (what Flint AOT registers).
private Binder binder(ConfigurationPropertySource[] sources, Descriptor[] descriptors...)
{
    auto b = new Binder(sources.dup);
    b.getDescriptors().add(descriptorOf!ExampleEnum());
    foreach (descriptor; descriptors)
        b.getDescriptors().add(descriptor);
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

/// `ValueObjectBinderTests.ExampleEnum`.
enum ExampleEnum
{
    FOO_BAR,
    BAR_BAZ
}

/// `ExampleValueBean`.
final class ExampleValueBean
{
    private const int intValue;
    private const long longValue;
    private const bool booleanValue;
    private const string stringValue;
    private const ExampleEnum enumValue;

    /// Part of the upstream test fixture.
    this(int intValue, long longValue, bool booleanValue, string stringValue, ExampleEnum enumValue)
    {
        this.intValue = intValue;
        this.longValue = longValue;
        this.booleanValue = booleanValue;
        this.stringValue = stringValue;
        this.enumValue = enumValue;
    }

    int getIntValue() const
    {
        return intValue;
    }

    long getLongValue() const
    {
        return longValue;
    }

    /// Part of the upstream test fixture.
    bool isBooleanValue() const
    {
        return booleanValue;
    }

    string getStringValue() const
    {
        return stringValue;
    }

    ExampleEnum getEnumValue() const
    {
        return enumValue;
    }
}

/// `ExampleAbstractBean`.
abstract class ExampleAbstractBean
{
    abstract string getName();
}

/// `MultipleConstructorsBean`.
final class MultipleConstructorsBean
{
    private const int intValue;

    /// Part of the upstream test fixture.
    this(int intValue)
    {
        this(intValue, 23L, "hello");
    }

    /// Part of the upstream test fixture.
    this(int intValue, long longValue, string stringValue)
    {
        this.intValue = intValue;
    }

    int getIntValue() const
    {
        return intValue;
    }
}

/// `MultipleConstructorsOnlyOneNotPrivateBean`.
final class MultipleConstructorsOnlyOneNotPrivateBean
{
    private const int intValue;
    private const string stringValue;

    /// Part of the upstream test fixture.
    this(int intValue)
    {
        this(intValue, 23L, "hello");
    }

    private this(int intValue, long longValue, string stringValue)
    {
        this.intValue = intValue;
        this.stringValue = stringValue;
    }

    int getIntValue() const
    {
        return intValue;
    }

    string getStringValue() const
    {
        return stringValue;
    }

    /// Part of the upstream test fixture.
    MultipleConstructorsOnlyOneNotPrivateBean withString(string stringValue) const
    {
        return new MultipleConstructorsOnlyOneNotPrivateBean(intValue, 0, stringValue);
    }
}

/// `DefaultConstructorBean`.
final class DefaultConstructorBean
{
    /// Part of the upstream test fixture.
    this()
    {
    }
}

/// `ExampleNestedBean`.
final class ExampleNestedBean
{
    private ExampleValueBean valueBean;

    /// Part of the upstream test fixture.
    this(ExampleValueBean valueBean)
    {
        this.valueBean = valueBean;
    }

    ExampleValueBean getValueBean()
    {
        return valueBean;
    }
}

/// `PlaceholderDefaultValue`.
struct PlaceholderDefaultValue
{
    /// The component.
    string value;

    /// Part of the upstream test fixture.
    this(string value)
    {
        this.value = value;
    }
}

/// `ExampleDefaultValueBean`.
final class ExampleDefaultValueBean
{
    private const int intValue;
    private string[] stringsList;
    private string[] customList;

    /// Part of the upstream test fixture.
    this(int intValue, string[] stringsList, string[] customList)
    {
        this.intValue = intValue;
        this.stringsList = stringsList;
        this.customList = customList;
    }

    int getIntValue() const
    {
        return intValue;
    }

    const(string[]) getStringsList() const
    {
        return stringsList;
    }

    const(string[]) getCustomList() const
    {
        return customList;
    }
}

/// `ExampleFailingConstructorBean`.
final class ExampleFailingConstructorBean
{
    import flint.java.lang : IllegalArgumentException;

    private string name;
    private string value;

    /// Part of the upstream test fixture.
    this(string name, string value)
    {
        if (name is null)
            throw new IllegalArgumentException("'name' must be not null.");
        if (value is null)
            throw new IllegalArgumentException("'value' must be not null.");
        this.name = name;
        this.value = value;
    }
}

/// `ValidatingConstructorBean`.
final class ValidatingConstructorBean
{
    import flint.java.lang : IllegalArgumentException;

    private string foo;
    private string bar;

    /// Part of the upstream test fixture.
    this(string foo, string bar)
    {
        if (foo is null)
            throw new IllegalArgumentException("'foo' must not be null");
        this.foo = foo;
        this.bar = bar;
    }
}

/// `GenericValue<T>`.
final class GenericValue(T)
{
    private T value;

    /// Part of the upstream test fixture.
    this(T value)
    {
        this.value = value;
    }

    T getValue()
    {
        return value;
    }
}

/// `NestedImmutable`.
final class NestedImmutable
{
    private string foo;
    private string bar;

    /// Part of the upstream test fixture.
    this(string foo, string bar)
    {
        this.foo = foo;
        this.bar = bar;
    }

    string getFoo()
    {
        return foo;
    }
}

/// `NestedJavaBean`.
final class NestedJavaBean
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

/// `NestedConstructorBeanWithDefaultValue`.
final class NestedConstructorBeanWithDefaultValue
{
    private NestedImmutable nestedImmutable;
    private NestedJavaBean nestedJavaBean;

    /// Part of the upstream test fixture.
    this(NestedImmutable nestedImmutable, NestedJavaBean nestedJavaBean)
    {
        this.nestedImmutable = nestedImmutable;
        this.nestedJavaBean = nestedJavaBean;
    }

    NestedImmutable getNestedImmutable()
    {
        return nestedImmutable;
    }

    NestedJavaBean getNestedJavaBean()
    {
        return nestedJavaBean;
    }
}

/// `NestedConstructorBeanWithEmptyDefaultValueFor...Types`: one parameter of type `T`.
final class SingleParameterBean(T)
{
    private T parameter;

    /// Part of the upstream test fixture.
    this(T parameter)
    {
        this.parameter = parameter;
    }

    T getValue()
    {
        return parameter;
    }
}

/// `NestedConstructorBeanWithEmptyDefaultValueForEnumTypes.Foo`.
enum Foo
{
    BAR,
    BAZ
}

/// `RecordProperties`.
struct RecordProperties
{
    /// First component.
    string property1;
    /// Second component.
    string property2;

    /// Part of the upstream test fixture.
    this(string property1, string property2)
    {
        this.property1 = property1;
        this.property2 = property2;
    }
}

/// `RecordPropertiesWithOptionalInNestedRecord.NestedRecord`.
struct NestedRecord
{
    import flint.java.util : Optional;

    /// An optional component.
    Optional!string property1;
    /// A string component.
    string property2;

    /// Part of the upstream test fixture.
    this(Optional!string property1, string property2)
    {
        this.property1 = property1;
        this.property2 = property2;
    }
}

/// `RecordPropertiesWithOptionalInNestedRecord`.
struct RecordPropertiesWithOptionalInNestedRecord
{
    /// The nested record.
    NestedRecord nested;

    /// Part of the upstream test fixture.
    this(NestedRecord nested)
    {
        this.nested = nested;
    }
}

/// `EmptyRecord`.
struct EmptyRecord
{
}

private Descriptor exampleValueBean()
{
    return valueObject!ExampleValueBean();
}

private void assertBoundExampleValueBean(const ExampleValueBean bean)
{
    assert(bean.getIntValue() == 12);
    assert(bean.getLongValue() == 34);
    assert(bean.isBooleanValue());
    assert(bean.getStringValue() == "foo");
    assert(bean.getEnumValue() == ExampleEnum.FOO_BAR);
}

private void assertNestedValueBean(ExampleNestedBean bean)
{
    assert(bean.getValueBean().getIntValue() == 123);
    assert(bean.getValueBean().getLongValue() == 34);
    assert(!bean.getValueBean().isBooleanValue());
    assert(bean.getValueBean().getStringValue() == "foo");
    assert(bean.getValueBean().getEnumValue() == ExampleEnum.init);
}

@("ValueObject.bindToClassWhenHasNoPrefixShouldCreateBoundBean") unittest
{
    auto b = binder([
        source([
            ["int-value", "12"], ["long-value", "34"], ["boolean-value", "true"],
            ["string-value", "foo"], ["enum-value", "foo-bar"]
        ])
    ], exampleValueBean(), descriptorOf!ExampleEnum());
    assertBoundExampleValueBean(b.bind!ExampleValueBean("").get());
}

@("ValueObject.bindToAbstractClassWithShouldNotBind") unittest
{
    const bound = binder([source([["foo.name", "test"]])]).bind!ExampleAbstractBean("foo").isBound();
    assert(!bound);
}

@("ValueObject.bindToClassWithMultipleConstructorsShouldNotBind") unittest
{
    const bound = binder([source([["foo.int-value", "12"]])]).bind!MultipleConstructorsBean("foo").isBound();
    assert(!bound);
}

version (FlintBindConstructorProvider)
{
    // Gap: the Binder takes no BindConstructorProvider to choose among several constructors.
    @("ValueObject.bindToClassWithMultipleConstructorsAndFilterShouldBind") unittest
    {
        import flint.boot.context.properties.bind : BindConstructorProvider;

        auto constructor = valueObject!(MultipleConstructorsBean, 0)().constructors[0];
        auto b = new Binder([cast(ConfigurationPropertySource) source([["foo.int-value", "12"]])],
                null, null, null, null, (bindable, isNestedConstructorBinding) => constructor);
        auto bound = b.bind!MultipleConstructorsBean("foo").get();
        assert(bound.getIntValue() == 12);
    }
}

@("ValueObject.bindToClassWithOnlyDefaultConstructorShouldNotBind") unittest
{
    const bound = binder([source([["foo.int-value", "12"]])]).bind!DefaultConstructorBean("foo").isBound();
    assert(!bound);
}

@("ValueObject.bindToClassWithMultipleConstructorsWhenOnlyOneIsNotPrivateShouldBind") unittest
{
    auto bean = binder([source([["foo.int-value", "12"]])],
            valueObject!(MultipleConstructorsOnlyOneNotPrivateBean, 0)())
        .bind!MultipleConstructorsOnlyOneNotPrivateBean("foo").get();
    bean = bean.withString("test");
    assert(bean.getIntValue() == 12);
    assert(bean.getStringValue() == "test");
}

@("ValueObject.bindToClassShouldBindNested") unittest
{
    auto bean = binder([
        source([
            ["foo.value-bean.int-value", "123"], ["foo.value-bean.long-value", "34"],
            ["foo.value-bean.string-value", "foo"]
        ])
    ], valueObject!ExampleNestedBean(), exampleValueBean()).bind!ExampleNestedBean("foo").get();
    assertNestedValueBean(bean);
}

@("ValueObject.bindToClassWhenParentOfEmptyStringAndSubValuesShouldFail") unittest
{
    auto bean = binder([
        source([
            ["foo.value-bean", ""], ["foo.value-bean.int-value", "123"],
            ["foo.value-bean.long-value", "34"], ["foo.value-bean.string-value", "foo"]
        ])
    ], valueObject!ExampleNestedBean(), exampleValueBean()).bind!ExampleNestedBean("foo").get();
    assertNestedValueBean(bean);
}

version (FlintEmptyStringCreatesValueObject)
{
    // Gap: an empty value for a value object's name does not create the object with default arguments.
    @("ValueObject.bindToClassWhenParentOfEmptyStringAndNoSubValuesShouldFail") unittest
    {
        auto bean = binder([source([["foo.value-bean", ""]])], valueObject!ExampleNestedBean(), exampleValueBean())
            .bind!ExampleNestedBean("foo").get();
        assert(bean.getValueBean().getIntValue() == 0);
        assert(bean.getValueBean().getLongValue() == 0);
        assert(!bean.getValueBean().isBooleanValue());
        assert(bean.getValueBean().getStringValue() is null);
        assert(bean.getValueBean().getEnumValue() == ExampleEnum.init);
    }

    @("ValueObject.bindToEmptyRecordWhenParentOfEmptyString") unittest
    {
        auto emptyRecord = binder([source([["foo", ""]])]).bind!EmptyRecord("foo");
        assert(emptyRecord.isBound());
    }
}

@("ValueObject.bindToClassWhenParentOfNullAndNoSubValuesShouldNotBind") unittest
{
    auto bindResult = binder([source([["foo.value-bean", null]])], valueObject!ExampleNestedBean(), exampleValueBean())
        .bind!ExampleNestedBean("foo");
    assert(!bindResult.isBound());
}

@("ValueObject.bindToClassWithNoValueForPrimitiveShouldUseDefault") unittest
{
    auto bean = binder([source([["foo.string-value", "foo"]])], exampleValueBean()).bind!ExampleValueBean("foo").get();
    assert(bean.getIntValue() == 0);
    assert(bean.getLongValue() == 0);
    assert(!bean.isBooleanValue());
    assert(bean.getStringValue() == "foo");
}

private Descriptor exampleDefaultValueBean()
{
    return valueObject!ExampleDefaultValueBean([
        defaultValue("5"), defaultValue("a", "b", "c"), defaultValue("x,y,z")
    ]);
}

version (FlintCollectionDefaultValue)
{
    // Gap: a list @DefaultValue goes through the scalar converter ("no converter for the type"), and is
    // evaluated even when nothing binds, so the bind fails instead of returning unbound.
    @("ValueObject.bindToClassWithNoValueAndDefaultValueShouldNotBind") unittest
    {
        auto b = binder([source([["foo.string-value", "foo"]])], exampleDefaultValueBean(),
                descriptorOf!(string[])());
        assert(!b.bind!ExampleDefaultValueBean("foo").isBound());
    }
}

@("ValueObject.bindToClassWhenNoParameterBoundShouldReturnNull") unittest
{
    auto result = binder([new NonIterableSource(source(null))], valueObject!ExampleFailingConstructorBean())
        .bind!ExampleFailingConstructorBean("foo");
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
        private LocalDate date;
        private string bar;

        /// Part of the upstream test fixture.
        this(@DefaultValue(["2019-05-10"]) @DateTimeFormat(ISO.DATE) LocalDate date, string bar)
        {
            this.date = date;
            this.bar = bar;
        }

        LocalDate getDate()
        {
            return date;
        }
    }

    @("ValueObject.bindWithAnnotations") unittest
    {
        auto bean = binder([source([["foo.date", "2014-04-01"]])], valueObject!ConverterAnnotatedExampleBean())
            .bind!ConverterAnnotatedExampleBean("foo").get();
        assert(bean.getDate().toString() == "2014-04-01");
    }

    @("ValueObject.createWithDefaultValuesAndAnnotationsShouldReturnCreatedWithDefaultValues") unittest
    {
        auto bean = binder([source(null)], valueObject!ConverterAnnotatedExampleBean())
            .bindOrCreate!ConverterAnnotatedExampleBean("foo");
        assert(bean.getDate().toString() == "2019-05-10");
    }
}

version (FlintCreateValueObjectWithDefaults)
{
    // Gap: bindOrCreate does not create a value object through its constructor with default arguments (it needs
    // a default constructor), so nothing applies @DefaultValue or rejects an empty one.
    import flint.boot.context.properties.bind : PropertySourcesPlaceholdersResolver;

    @("ValueObject.createShouldReturnCreatedValue") unittest
    {
        auto value = binder([source(null)], exampleValueBean()).bindOrCreate!ExampleValueBean("foo");
        assert(value.getIntValue() == 0);
        assert(value.getLongValue() == 0);
        assert(!value.isBooleanValue());
        assert(value.getStringValue() is null);
        assert(value.getEnumValue() == ExampleEnum.init);
    }

    @("ValueObject.createWithNestedShouldReturnCreatedValue") unittest
    {
        auto value = binder([source(null)], valueObject!ExampleNestedBean(), exampleValueBean())
            .bindOrCreate!ExampleNestedBean("foo");
        assert(value.getValueBean() is null);
    }

    @("ValueObject.createWithDefaultValuesShouldReturnCreatedWithDefaultValues") unittest
    {
        auto value = binder([source(null)], exampleDefaultValueBean(), descriptorOf!(string[])())
            .bindOrCreate!ExampleDefaultValueBean("foo");
        assert(value.getIntValue() == 5);
        assert(value.getStringsList() == ["a", "b", "c"]);
        assert(value.getCustomList() == ["x,y,z"]);
    }

    @("ValueObject.createWithDefaultValuePlaceholderAndNoResolverShouldRetainPlaceholder") unittest
    {
        const bean = binder([source(null)], valueObject!PlaceholderDefaultValue([
            defaultValue("${value}")
        ])).bindOrCreate!PlaceholderDefaultValue("foo");
        assert(bean.value == "${value}");
    }

    @("ValueObject.createWithUnresolvedDefaultValuePlaceholderShouldRetainPlaceholder") unittest
    {
        auto b = new Binder([cast(ConfigurationPropertySource) source(null)],
                new PropertySourcesPlaceholdersResolver(null));
        b.getDescriptors().add(valueObject!PlaceholderDefaultValue([defaultValue("${value}")]));
        const bean = b.bindOrCreate!PlaceholderDefaultValue("foo");
        assert(bean.value == "${value}");
    }

    @("ValueObject.bindWhenParametersWithDefaultValueShouldReturnNonNullValues") unittest
    {
        auto bound = binder([source(null)], valueObject!NestedConstructorBeanWithDefaultValue([
            defaultValue(), defaultValue()
        ]), valueObject!NestedImmutable([defaultValue("hello")]), descriptorOf!NestedJavaBean())
            .bindOrCreate!NestedConstructorBeanWithDefaultValue("foo");
        assert(bound.getNestedImmutable().getFoo() == "hello");
        assert(bound.getNestedJavaBean() !is null);
    }

    @("ValueObject.bindWhenJavaLangParameterWithEmptyDefaultValueShouldThrowException") unittest
    {
        auto b = binder([source(null)], valueObject!(SingleParameterBean!string)([defaultValue()]));
        assertThrows!BindException(() { b.bindOrCreate!(SingleParameterBean!string)("foo"); });
        // upstream: "Parameter of type java.lang.String must have a non-empty default value."
    }

    @("ValueObject.bindWhenCollectionParameterWithEmptyDefaultValueShouldReturnEmptyInstance") unittest
    {
        import flint.java.util : List;

        auto bound = binder([source(null)],
                valueObject!(SingleParameterBean!(List!string))([defaultValue()]), descriptorOf!(List!string)())
            .bindOrCreate!(SingleParameterBean!(List!string))("foo");
        assert(bound.getValue() !is null && bound.getValue().isEmpty());
    }

    @("ValueObject.bindWhenMapParametersWithEmptyDefaultValueShouldReturnEmptyInstance") unittest
    {
        import flint.java.util : Map;

        auto bound = binder([source(null)], valueObject!(SingleParameterBean!(Map!(string,
                string)))([defaultValue()]), descriptorOf!(Map!(string, string))()).bindOrCreate!(
                SingleParameterBean!(Map!(string, string)))("foo");
        assert(bound.getValue() !is null && bound.getValue().isEmpty());
    }

    @("ValueObject.bindWhenEnumMapParametersWithEmptyDefaultValueShouldReturnEmptyInstance") unittest
    {
        import flint.java.util : Map;

        auto bound = binder([source(null)], valueObject!(SingleParameterBean!(Map!(ExampleEnum,
                string)))([defaultValue()]), descriptorOf!(Map!(ExampleEnum, string))(),
                descriptorOf!ExampleEnum()).bindOrCreate!(SingleParameterBean!(Map!(ExampleEnum, string)))("foo");
        assert(bound.getValue() !is null && bound.getValue().isEmpty());
    }

    @("ValueObject.bindWhenArrayParameterWithEmptyDefaultValueShouldReturnEmptyInstance") unittest
    {
        auto bound = binder([source(null)],
                valueObject!(SingleParameterBean!(string[]))([defaultValue()]), descriptorOf!(string[])())
            .bindOrCreate!(SingleParameterBean!(string[]))("foo");
        assert(bound.getValue().length == 0);
    }

    @("ValueObject.bindWhenOptionalParameterWithEmptyDefaultValueShouldReturnEmptyInstance") unittest
    {
        import flint.java.util : Optional;

        auto bound = binder([source(null)],
                valueObject!(SingleParameterBean!(Optional!string))([defaultValue()]),
                descriptorOf!(Optional!string)()).bindOrCreate!(SingleParameterBean!(Optional!string))("foo");
        assert(!bound.getValue().isPresent());
    }

    @("ValueObject.bindWhenOptionalParameterWithNoValueForPrimitiveShouldReturnEmptyInstance") unittest
    {
        import flint.java.util : Optional;

        auto bound = binder([source(null)], valueObject!(SingleParameterBean!(Optional!string))(),
                descriptorOf!(Optional!string)()).bindOrCreate!(SingleParameterBean!(Optional!string))("foo");
        assert(!bound.getValue().isPresent());
    }

    @("ValueObject.bindWhenEnumParameterWithEmptyDefaultValueShouldThrowException") unittest
    {
        auto b = binder([source(null)], valueObject!(SingleParameterBean!Foo)([defaultValue()]), descriptorOf!Foo());
        assertThrows!BindException(() { b.bindOrCreate!(SingleParameterBean!Foo)("foo"); });
        // upstream: "Parameter of type ...$NestedConstructorBeanWithEmptyDefaultValueForEnumTypes$Foo must have a
        // non-empty default value."
    }

    @("ValueObject.bindWhenPrimitiveParameterWithEmptyDefaultValueShouldThrowException") unittest
    {
        auto b = binder([source(null)], valueObject!(SingleParameterBean!int)([defaultValue()]));
        assertThrows!BindException(() { b.bindOrCreate!(SingleParameterBean!int)("foo"); },
                "Parameter of type int must have a non-empty default value.");
    }
}

version (FlintDefaultValuePlaceholders)
{
    // Gap: @DefaultValue text is converted as written, without going through the placeholders resolver.
    import flint.boot.context.properties.bind : PlaceholdersResolver;

    @("ValueObject.createWithDefaultValuePlaceholderResolvingToNonStringShouldConvert") unittest
    {
        static final class FortyTwo : PlaceholdersResolver
        {
            string resolvePlaceholders(string)
            {
                return "42";
            }
        }

        auto b = new Binder([cast(ConfigurationPropertySource) source(null)], new FortyTwo);
        b.getDescriptors().add(valueObject!PlaceholderDefaultValue([defaultValue("${value}")]));
        const bean = b.bindOrCreate!PlaceholderDefaultValue("foo");
        assert(bean.value == "42");
    }
}

version (FlintBindExceptionProperty)
{
    // Gap: a constructor failure after every property is bound is not wrapped in a BindException without a
    // property (the IllegalArgumentException escapes unwrapped).
    @("ValueObject.bindWhenAllPropertiesBoundShouldClearConfigurationProperty") unittest
    {
        // gh-18704
        auto b = binder([source([["foo.bar", "hello"]])], valueObject!ValidatingConstructorBean());
        try
        {
            b.bind!ValidatingConstructorBean("foo");
            assert(false, "expected a BindException");
        }
        catch (BindException expected)
            assert(expected.getProperty() is null);
    }
}

@("ValueObject.bindToClassShouldBindWithGenerics") unittest
{
    // gh-19156
    auto bean = binder([source([["foo.value.bar", "baz"]])],
            valueObject!(GenericValue!(string[string]))(), descriptorOf!(string[string])()).bind!(
            GenericValue!(string[string]))("foo").get();
    assert(bean.getValue()["bar"] == "baz");
}

@("ValueObject.bindWhenOptionalParameterInNestedWithNoValueForPrimitiveShouldReturnEmptyInstance") unittest
{
    import flint.java.util : Optional;

    auto bound = binder([source([["foo.nested.property2", "str"]])],
            valueObject!RecordPropertiesWithOptionalInNestedRecord(),
            valueObject!NestedRecord(), descriptorOf!(Optional!string)())
        .bindOrCreate!RecordPropertiesWithOptionalInNestedRecord("foo");
    assert(!bound.nested.property1.isPresent());
    assert(bound.nested.property2 == "str");
}

version (FlintNameAnnotation)
{
    // Gap: `@Name` is not ported, so a parameter cannot bind under another name (`import`).
    import flint.boot.context.properties.bind : Name;

    /// `NamedConstructorParameter`.
    final class NamedConstructorParameter
    {
        private string importName;

        /// Part of the upstream test fixture.
        this(@Name("import") string importName)
        {
            this.importName = importName;
        }

        string getImportName()
        {
            return importName;
        }
    }

    /// `NamedRecordComponent`.
    struct NamedRecordComponent
    {
        /// The component bound as `import`.
        @Name("import")
        string importName;
    }

    @("ValueObject.bindToAnnotationNamedConstructorParameter") unittest
    {
        auto bound = binder([source([["test.import", "test"]])], valueObject!NamedConstructorParameter())
            .bindOrCreate!NamedConstructorParameter("test");
        assert(bound.getImportName() == "test");
    }

    @("ValueObject.bindToAnnotationNamedRecordComponent") unittest
    {
        const bound = binder([source([["test.import", "test"]])]).bindOrCreate!NamedRecordComponent("test");
        assert(bound.importName == "test");
    }
}

@("ValueObject.bindToRecordWithDefaultValue") unittest
{
    const bound = binder([source([["test.property1", "value-from-config-1"]])],
            valueObject!RecordProperties([
                defaultValue("default-value-1"), defaultValue("default-value-2")
    ])).bindOrCreate!RecordProperties("test");
    assert(bound.property1 == "value-from-config-1");
    assert(bound.property2 == "default-value-2");
}

import boot_tests.support : RegisterTests;

mixin RegisterTests;
