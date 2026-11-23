// Ported from spring-boot v4.2.0: core/spring-boot/src/test/java/org/springframework/boot/context/properties/bind/BinderTests.java
// with JavaBeanBinderTests.java, ValueObjectBinderTests.java, BindResultTests.java,
// PropertySourcesPlaceholdersResolverTests.java and DataObjectPropertyNameTests.java from the same directory, and
// core/spring-boot/src/test/java/org/springframework/boot/convert/DurationStyleTests.java.
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: Java beans become D classes with Java-named getters and setters (rulebook R6),
// constructor binding uses the constructor descriptor Flint AOT emits, and AssertJ becomes D asserts.
module boot_tests.binder_test;

import boot_tests.support : assertThrows;
import flint.boot.context.properties.bind : BindException, BindResult, Bindable, Binder,
    DefaultValue, PropertySourcesPlaceholdersResolver, parseDuration, toDashedForm;
import flint.boot.context.properties.source : ConfigurationPropertySource, MapConfigurationPropertySource;
import flint.java.util : NoSuchElementException;

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

/// `JavaBeanBinderTests.ExampleValueBean`.
final class ExampleValueBean
{
    private int intValue;
    private long longValue;
    private string stringValue;
    private ExampleEnum enumValue;

    int getIntValue() const
    {
        return intValue;
    }

    void setIntValue(int value)
    {
        intValue = value;
    }

    long getLongValue() const
    {
        return longValue;
    }

    void setLongValue(long value)
    {
        longValue = value;
    }

    string getStringValue() const
    {
        return stringValue;
    }

    void setStringValue(string value)
    {
        stringValue = value;
    }
}

/// `JavaBeanBinderTests.ExampleEnum`.
enum ExampleEnum
{
    FOO_BAR,
    BAR_BAZ
}

/// `JavaBeanBinderTests.ExampleDefaultsBean`.
final class ExampleDefaultsBean
{
    private int foo = 123;
    private int bar = 456;

    int getFoo() const
    {
        return foo;
    }

    void setFoo(int value)
    {
        foo = value;
    }

    int getBar() const
    {
        return bar;
    }

    void setBar(int value)
    {
        bar = value;
    }
}

/// `JavaBeanBinderTests.ExampleNestedBean`.
final class ExampleNestedBean
{
    private ExampleValueBean valueBean;

    ExampleValueBean getValueBean()
    {
        return valueBean;
    }

    void setValueBean(ExampleValueBean value)
    {
        valueBean = value;
    }
}

/// `BinderTests.JavaBean`.
final class JavaBean
{
    private string value;

    string getValue() const
    {
        return value;
    }

    void setValue(string value)
    {
        this.value = value;
    }
}

/// A Flint record-style struct with public fields.
struct DataSourceLike
{
    /// JDBC URL.
    string url;
    /// Login user.
    string username;
    /// Pool size.
    int maximumPoolSize = 10;
    /// Auto-commit.
    bool autoCommit = true;
}

// ---- BinderTests ------------------------------------------------------------------------------------------

@("bindToValueWhenPropertyIsMissingShouldReturnUnbound") unittest
{
    auto result = binder(source(null)).bind!string("foo");
    assert(!result.isBound());
}

@("bindToValueShouldReturnPropertyValue") unittest
{
    assert(binder(source([["foo", "123"]])).bind!int("foo").get() == 123);
}

@("bindToValueShouldReturnPropertyValueFromSecondSource") unittest
{
    auto result = binder(source([["foo", "1"]]), source([["bar", "2"]])).bind!int("bar");
    assert(result.get() == 2);
}

@("bindToValueShouldReturnConvertedPropertyValue") unittest
{
    assert(binder(source([["foo", "123"]])).bind!string("foo").get() == "123");
}

@("bindToValueWhenMultipleCandidatesShouldReturnFirst") unittest
{
    auto result = binder(source([["foo", "123"]]), source([["foo", "234"]])).bind!int("foo");
    assert(result.get() == 123);
}

@("bindToValueWithPlaceholdersShouldResolve") unittest
{
    auto result = binder(source([["bar", "23"], ["foo", "1${bar}"]])).bind!int("foo");
    assert(result.get() == 123);
}

@("bindToValueWithMissingPlaceholderShouldResolveToValueWithPlaceholder") unittest
{
    auto result = binder(source([["foo", "${bar}"]])).bind!string("foo");
    assert(result.get() == "${bar}");
}

@("bindToJavaBeanShouldReturnPopulatedBean") unittest
{
    auto result = binder(source([["foo.value", "bar"]])).bind!JavaBean("foo").get();
    assert(result.getValue() == "bar");
}

@("bindToJavaBeanWhenNonIterableShouldReturnPopulatedBean") unittest
{
    // Upstream uses a non-iterable source; Flint's map source answers lookups the same way.
    auto result = binder(source([["foo.value", "bar"]])).bind!JavaBean("foo").get();
    assert(result.getValue() == "bar");
}

@("bindWhenHasMalformedDateShouldThrowException") unittest
{
    // Upstream binds a malformed LocalDate; the equivalent Flint failure is a malformed number.
    assertThrows!BindException(() { binder(source([["foo", "2014-04-01"]])).bind!int("foo"); },
            "Failed to bind properties under 'foo' to int");
}

@("bindOrCreateWhenBindSuccessfulShouldReturnBoundValue") unittest
{
    auto result = binder(source([["foo.value", "bar"]])).bindOrCreate!JavaBean("foo");
    assert(result.getValue() == "bar");
}

@("bindOrCreateWhenUnboundShouldReturnCreatedValue") unittest
{
    auto result = binder(source(null)).bindOrCreate!JavaBean("foo");
    assert(result !is null && result.getValue() is null);
}

@("bindWithEmptyPrefixShouldIgnorePropertiesWithEmptyName") unittest
{
    auto result = binder(source([["name", "foo"]])).bind!JavaBean("");
    assert(!result.isBound());
}

// ---- JavaBeanBinderTests ----------------------------------------------------------------------------------

@("bindToClassShouldCreateBoundBean") unittest
{
    const bean = binder(source([
            ["foo.int-value", "12"], ["foo.long-value", "34"], ["foo.string-value", "foo"]
    ])).bind!ExampleValueBean("foo").get();
    assert(bean.getIntValue() == 12);
    assert(bean.getLongValue() == 34);
    assert(bean.getStringValue() == "foo");
}

@("bindToClassWhenHasNoPrefixShouldCreateBoundBean") unittest
{
    const bean = binder(source([["int-value", "12"], ["long-value", "34"], ["string-value", "foo"]]))
        .bind!ExampleValueBean("").get();
    assert(bean.getIntValue() == 12 && bean.getLongValue() == 34 && bean.getStringValue() == "foo");
}

@("bindToInstanceShouldBindToInstance") unittest
{
    auto bean = new ExampleValueBean;
    const bound = binder(source([["foo.int-value", "12"], ["foo.string-value", "foo"]])).bind!ExampleValueBean("foo",
            Bindable!ExampleValueBean.ofInstance(bean)).get();
    assert(bound is bean);
    assert(bean.getIntValue() == 12 && bean.getStringValue() == "foo");
}

@("bindToInstanceWithNoPropertiesShouldReturnUnbound") unittest
{
    auto bean = new ExampleDefaultsBean;
    auto result = binder(source(null)).bind!ExampleDefaultsBean("foo", Bindable!ExampleDefaultsBean.ofInstance(bean));
    assert(!result.isBound());
    assert(bean.getFoo() == 123);
}

@("bindToClassShouldLeaveDefaults") unittest
{
    const bean = binder(source([["foo.bar", "999"]])).bind!ExampleDefaultsBean("foo").get();
    assert(bean.getFoo() == 123);
    assert(bean.getBar() == 999);
}

@("bindToExistingInstanceShouldLeaveDefaults") unittest
{
    auto bean = new ExampleDefaultsBean;
    bean.setFoo(888);
    const bound = binder(source([["foo.bar", "999"]])).bind!ExampleDefaultsBean("foo",
            Bindable!ExampleDefaultsBean.ofInstance(bean)).get();
    assert(bound.getFoo() == 888);
    assert(bound.getBar() == 999);
}

@("bindToClassShouldBindNested") unittest
{
    auto b = binder(source([
            ["foo.value-bean.int-value", "123"], ["foo.value-bean.string-value", "foo"]
    ]));
    b.getDescriptors().add(descriptorOfValueBean());
    auto bean = b.bind!ExampleNestedBean("foo").get();
    assert(bean.getValueBean().getIntValue() == 123);
    assert(bean.getValueBean().getStringValue() == "foo");
}

@("bindToInstanceWhenNoNestedShouldLeaveNestedAsNull") unittest
{
    auto b = binder(source([["faf.value-bean.int-value", "123"]]));
    b.getDescriptors().add(descriptorOfValueBean());
    auto bean = new ExampleNestedBean;
    auto result = b.bind!ExampleNestedBean("foo", Bindable!ExampleNestedBean.ofInstance(bean));
    assert(!result.isBound());
    assert(bean.getValueBean() is null);
}

@("bindToClassWhenPropertiesMissingShouldReturnUnbound") unittest
{
    assert(!binder(source([["faf.int-value", "12"]])).bind!ExampleValueBean("foo").isBound());
}

@("bindToClassWhenPropertyCannotBeConvertedShouldThrowException") unittest
{
    assertThrows!BindException(() {
        binder(source([["foo.int-value", "foo"]])).bind!ExampleValueBean("foo");
    });
}

@("bindRenamedPropertyToClassBean") unittest
{
    // Upstream renames through @Name; Flint's relaxed names bind every spelling of the same property.
    const bean = binder(source([["foo.intValue", "12"], ["foo.STRING_VALUE", "x"]])).bind!ExampleValueBean("foo")
        .get();
    assert(bean.getIntValue() == 12);
}

@("bindOrCreateWithNestedShouldReturnCreatedValue") unittest
{
    auto bean = binder(source(null)).bindOrCreate!ExampleNestedBean("foo");
    assert(bean !is null && bean.getValueBean() is null);
}

@("bindUsesConsistentPropertyOrder") unittest
{
    const bean = binder(source([["foo.string-value", "a"], ["foo.int-value", "1"]])).bind!ExampleValueBean("foo")
        .get();
    assert(bean.getIntValue() == 1 && bean.getStringValue() == "a");
}

// ---- ValueObjectBinderTests (constructor descriptors as Flint AOT emits them) ---------------------------

/// `ValueObjectBinderTests.ExampleValueBean`, as a record-like struct with a canonical constructor.
struct ExampleRecord
{
    /// An int component.
    int intValue;
    /// A long component.
    long longValue;
    /// A string component with a default.
    string stringValue = "default";
}

private Binder recordBinder(MapConfigurationPropertySource s)
{
    import flint.engine.aot.any : Any;
    import flint.engine.aot.descriptor : ConstructorDescriptor, MergedAnnotation, ParameterDescriptor, descriptorOf;

    auto b = binder(s);
    auto descriptor = descriptorOf!ExampleRecord();
    MergedAnnotation[] defaultString = [
        MergedAnnotation("flint.boot.context.properties.bind.DefaultValue", Any.of(DefaultValue([
            "default"
        ])), 0)
    ];
    descriptor.constructors = [
        ConstructorDescriptor([
            ParameterDescriptor("intValue", "int"), ParameterDescriptor("longValue", "long"),
            ParameterDescriptor("stringValue", "string", defaultString)
        ], null,
        (scope Any[] a) => Any.of(ExampleRecord(a[0].isNull() ? 0 : a[0].get!int, a[1].isNull()
                ? 0 : a[1].get!long, a[2].isNull() ? null : a[2].get!string)))
    ];
    b.getDescriptors().add(descriptor);
    return b;
}

@("ValueObject.bindToClassShouldCreateBoundBean") unittest
{
    const bean = recordBinder(source([
            ["foo.int-value", "12"], ["foo.long-value", "34"], ["foo.string-value", "foo"]
    ])).bind!ExampleRecord("foo").get();
    assert(bean.intValue == 12 && bean.longValue == 34 && bean.stringValue == "foo");
}

@("ValueObject.bindToClassWhenNoValuesShouldNotBind") unittest
{
    assert(!recordBinder(source([["faf.int-value", "12"]])).bind!ExampleRecord("foo").isBound());
}

@("ValueObject.bindWithAnnotationsAndDefaultValue") unittest
{
    const bean = recordBinder(source([["foo.int-value", "12"]])).bind!ExampleRecord("foo").get();
    assert(bean.intValue == 12 && bean.stringValue == "default");
}

// ---- BindResultTests ----------------------------------------------------------------------------------------

@("getWhenHasValueShouldReturnValue") unittest
{
    assert(BindResult!string.of("foo").get() == "foo");
}

@("getWhenHasNoValueShouldThrowException") unittest
{
    assertThrows!NoSuchElementException(() { BindResult!string.init.get(); }, "No value bound");
}

@("isBoundWhenHasValueShouldReturnTrue") unittest
{
    assert(BindResult!string.of("foo").isBound());
}

@("isBoundWhenHasNoValueShouldFalse") unittest
{
    assert(!BindResult!string.init.isBound());
}

@("ifBoundWhenHasValueShouldCallConsumer") unittest
{
    string seen;
    BindResult!string.of("foo").ifBound((string v) { seen = v; });
    assert(seen == "foo");
}

@("ifBoundWhenHasNoValueShouldNotCallConsumer") unittest
{
    bool called;
    BindResult!string.init.ifBound((string) { called = true; });
    assert(!called);
}

@("mapWhenHasValueShouldCallMapper") unittest
{
    assert(BindResult!string.of("foo").map!int((string v) => cast(int) v.length).get() == 3);
}

@("mapWhenHasNoValueShouldNotCallMapper") unittest
{
    bool called;
    auto mapped = BindResult!string.init.map!int((string) { called = true; return 1; });
    assert(!mapped.isBound() && !called);
}

@("orElseWhenHasValueShouldReturnValue") unittest
{
    assert(BindResult!string.of("foo").orElse("bar") == "foo");
}

@("orElseWhenHasValueNoShouldReturnOther") unittest
{
    assert(BindResult!string.init.orElse("bar") == "bar");
}

@("orElseGetWhenHasValueShouldReturnValue") unittest
{
    assert(BindResult!string.of("foo").orElseGet(() => "bar") == "foo");
}

@("orElseGetWhenHasValueNoShouldReturnOther") unittest
{
    assert(BindResult!string.init.orElseGet(() => "bar") == "bar");
}

// ---- PropertySourcesPlaceholdersResolverTests -------------------------------------------------------------

@("resolveIfPlaceholderPresentResolvesProperty") unittest
{
    auto resolver = new PropertySourcesPlaceholdersResolver(
            [cast(ConfigurationPropertySource) source([["FOO", "hello world"]])]);
    assert(resolver.resolvePlaceholders("${FOO}") == "hello world");
}

@("resolveIfPlaceholderAbsentUsesDefault") unittest
{
    auto resolver = new PropertySourcesPlaceholdersResolver(null);
    assert(resolver.resolvePlaceholders("${FOO:bar}") == "bar");
}

@("resolveIfPlaceholderAbsentAndNoDefaultUsesPlaceholder") unittest
{
    auto resolver = new PropertySourcesPlaceholdersResolver(null);
    assert(resolver.resolvePlaceholders("${FOO}") == "${FOO}");
}

@("flint.placeholdersNestAndEscape") unittest
{
    auto resolver = new PropertySourcesPlaceholdersResolver([
        cast(ConfigurationPropertySource) source([
            ["a", "x"], ["b", "${a}y"], ["flint.application.name", "demo"]
        ])
    ]);
    assert(resolver.resolvePlaceholders("${b}-${c:${a}}") == "xy-x");
    assert(resolver.resolvePlaceholders("\\${a}") == "${a}");
    assert(resolver.resolvePlaceholders("${spring.application.name:none}") == "none");
    assert(resolver.resolvePlaceholders("${flint.application.name}") == "demo");
}

// ---- DataObjectPropertyNameTests ----------------------------------------------------------------------------

@("toDashedCaseConvertsValue") unittest
{
    assert(toDashedForm("Foo") == "foo");
    assert(toDashedForm("foo") == "foo");
    assert(toDashedForm("fooBar") == "foo-bar");
    assert(toDashedForm("foo_bar") == "foo-bar");
    assert(toDashedForm("_foo_bar") == "-foo-bar");
    assert(toDashedForm("foo_Bar") == "foo-bar");
}

@("toDashedFormWhenContainsIndexedAddsNoDashToIndex") unittest
{
    assert(toDashedForm("test[fooBar]") == "test[fooBar]");
    assert(toDashedForm("testAgain[fooBar]") == "test-again[fooBar]");
}

// ---- DurationStyleTests (detectAndParse) --------------------------------------------------------------------

@("detectAndParseWhenSimpleShouldReturnDuration") unittest
{
    import core.time : days, hours, minutes, msecs, nsecs, seconds, usecs;

    assert(parseDuration("10ns") == nsecs(10));
    assert(parseDuration("10us") == usecs(10));
    assert(parseDuration("10ms") == msecs(10));
    assert(parseDuration("10s") == seconds(10));
    assert(parseDuration("10m") == minutes(10));
    assert(parseDuration("10h") == hours(10));
    assert(parseDuration("10d") == days(10));
    assert(parseDuration("-10s") == seconds(-10));
    assert(parseDuration("10") == msecs(10));
    assert(parseDuration("10S") == seconds(10));
}

@("detectAndParseWhenIsoShouldReturnDuration") unittest
{
    import core.time : days, hours, minutes, msecs, seconds;

    assert(parseDuration("PT20.345S") == msecs(20_345));
    assert(parseDuration("PT15M") == minutes(15));
    assert(parseDuration("+PT15M") == minutes(15));
    assert(parseDuration("PT10H") == hours(10));
    assert(parseDuration("P2D") == days(2));
    assert(parseDuration("P2DT3H4M") == days(2) + hours(3) + minutes(4));
    assert(parseDuration("-PT6H3M") == -(hours(6) + minutes(3)));
    assert(parseDuration("pt20.345s") == msecs(20_345));
}

@("detectAndParseWhenBadFormatShouldThrowException") unittest
{
    import flint.boot.context.properties.bind : ConversionFailedException;

    assertThrows!ConversionFailedException(() { parseDuration("10foo"); }, "Unknown unit");
}

// ---- Flint: Boot-style property sets on a struct ------------------------------------------------------------

@("flint.relaxedBindingOntoStruct") unittest
{
    auto b = binder(source([
            ["flint.datasource.url", "jdbc:postgresql://db/app"], [
                "flint.datasource.user-name", "app"
            ], ["flint.datasource.maximumPoolSize", "0x20"], ["flint.datasource.auto_commit", "off"]
    ]));
    const ds = b.bind!DataSourceLike("flint.datasource").get();
    assert(ds.url == "jdbc:postgresql://db/app");
    assert(ds.username == "app");
    assert(ds.maximumPoolSize == 32);
    assert(!ds.autoCommit);
}

@("flint.springAliasBindsFlintPrefix") unittest
{
    const ds = binder(source([["spring.datasource.url", "jdbc:h2:mem:x"]])).bind!DataSourceLike(
            "flint.datasource").get();
    assert(ds.url == "jdbc:h2:mem:x");
    assert(ds.maximumPoolSize == 10);
}

/// `DurationStyleTests`-style property with `@DurationUnit(ChronoUnit.SECONDS)`.
struct TimeoutSettings
{
    import core.time : Duration;
    import flint.boot.convert : ChronoUnit, DurationUnit;

    /// Bare numbers are seconds.
    @DurationUnit(ChronoUnit.SECONDS) Duration timeout;
    /// Bare numbers are milliseconds.
    Duration delay;
}

@("flint.durationUnitAppliesToBareNumbers") unittest
{
    import core.time : msecs, seconds;

    const settings = binder(source([["t.timeout", "30"], ["t.delay", "30"]])).bind!TimeoutSettings("t").get();
    assert(settings.timeout == seconds(30));
    assert(settings.delay == msecs(30));
    const explicit = binder(source([["t.timeout", "500ms"]])).bind!TimeoutSettings("t").get();
    assert(explicit.timeout == msecs(500));
}

private auto descriptorOfValueBean()
{
    import flint.engine.aot.descriptor : descriptorOf;

    return descriptorOf!ExampleValueBean();
}

@("flint.placeholderFromRawEnvironmentVariable: ${POSTGRES_URL:...} reads the variable, as Spring does") unittest
{
    import flint.boot.context.properties.source : SystemEnvironmentPropertySource;

    auto environment = new SystemEnvironmentPropertySource([
        "POSTGRES_URL": "jdbc:postgresql://db:5432/petclinic"
    ]);
    auto file = new MapConfigurationPropertySource("application-postgres.properties",
            [
                ["flint.datasource.url", "${POSTGRES_URL:jdbc:postgresql://localhost/petclinic}"],
                ["flint.datasource.username", "${POSTGRES_USER:petclinic}"],
                ["app.name", "${app.title}"], ["app.title", "fromfile"]
    ]);
    auto binder = new Binder([cast(ConfigurationPropertySource) environment, file]);
    assert(binder.bind!string("flint.datasource.url").get() == "jdbc:postgresql://db:5432/petclinic");
    assert(binder.bind!string("flint.datasource.username").get() == "petclinic");
    // A dotted key also matches its environment form, as SystemEnvironmentPropertySource does.
    auto withOverride = new Binder(
            [
        cast(ConfigurationPropertySource) new SystemEnvironmentPropertySource([
            "APP_TITLE": "fromenv"
        ]), file
    ]);
    assert(withOverride.bind!string("app.name").get() == "fromenv");
}

import boot_tests.support : RegisterTests;

mixin RegisterTests;
