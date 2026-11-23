// Ported from spring-boot v4.2.0: core/spring-boot/src/test/java/org/springframework/boot/
// context/properties/bind/BinderTests.java with BindResultTests.java and PropertySourcesPlaceholdersResolverTests.java
// from the same directory: the tests boot_tests/binder_test.d does not port.
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: Java beans become D classes with Java-named getters and setters (rulebook R6),
// AssertJ becomes D asserts, Mockito's BindHandler mock is a recording handler, and `Bindable.of(X.class)` is
// `bind!X`.
// Not ported: BinderTests createWhenSourcesIsNullArrayShouldThrowException and
// createWhenSourcesIsNullIterableShouldThrowException (a null D slice is the empty list),
// bindToValueWithCustomPropertyEditorShouldReturnConvertedValue (java.beans PropertyEditor) and
// bindToBeanWithUnresolvableGenerics (Java raw generic types); PropertySourcesPlaceholdersResolverTests
// placeholderResolverIfEnvironmentNullShouldThrowException (Flint's resolver is built from configuration property
// sources, never from an Environment).
module boot_tests.binder_upstream_test;

import boot_tests.support : assertThrows;
import flint.boot.context.properties.bind : BindResult, Bindable, Binder;
import flint.boot.context.properties.source : ConfigurationProperty, ConfigurationPropertyName,
    ConfigurationPropertySource, ConfigurationPropertyState, MapConfigurationPropertySource;
import flint.java.lang : IllegalArgumentException;

@safe:

private Binder binder(ConfigurationPropertySource[] sources...)
{
    return new Binder(sources.dup);
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

/// `BinderTests.CycleBean1`.
final class CycleBean1
{
    private CycleBean2 two;

    CycleBean2 getTwo()
    {
        return two;
    }

    void setTwo(CycleBean2 two)
    {
        this.two = two;
    }
}

/// `BinderTests.CycleBean2`.
final class CycleBean2
{
    private CycleBean1 one;

    CycleBean1 getOne()
    {
        return one;
    }

    void setOne(CycleBean1 one)
    {
        this.one = one;
    }
}

/// `JavaBeanWithPublicConstructor`.
final class JavaBeanWithPublicConstructor
{
    private string value;

    /// Part of the upstream test fixture.
    this()
    {
    }

    /// Part of the upstream test fixture.
    this(string value)
    {
        setValue(value);
    }

    string getValue() const
    {
        return value;
    }

    void setValue(string value)
    {
        this.value = value;
    }
}

/// `MockConfigurationPropertySource.nonIterable()`: answers lookups but cannot list its names.
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

private JavaBeanWithPublicConstructor bindToJavaBeanWithPublicConstructor(Binder b)
{
    return b.bindOrCreate!JavaBeanWithPublicConstructor("foo");
}

private MapConfigurationPropertySource publicConstructorSource()
{
    return new MapConfigurationPropertySource("test", [
        ["foo", "constructor"], ["foo.value", "setter"]
    ]);
}

// ---- BinderTests ------------------------------------------------------------------------------------------

version (FlintBootNullArgumentChecks)
{
    // Gap: the Binder does not check its arguments for null (a null source or name fails later, unexplained).
    import flint.engine.aot.any : Any;
    import flint.engine.aot.descriptor : descriptorOf;

    @("createWhenArraySourcesContainsNullElementShouldThrowException") unittest
    {
        assertThrows!IllegalArgumentException(() {
            new Binder([cast(ConfigurationPropertySource) null]);
        }, "'sources' must not contain null elements");
    }

    @("createWhenIterableSourcesContainsNullElementShouldThrowException") unittest
    {
        ConfigurationPropertySource[] sources = [null];
        assertThrows!IllegalArgumentException(() { new Binder(sources); }, "'sources' must not contain null elements");
    }

    @("bindWhenNameIsNullShouldThrowException") unittest
    {
        Any instance;
        assertThrows!IllegalArgumentException(() {
            binder().bind(cast(ConfigurationPropertyName) null, descriptorOf!string(), instance);
        }, "'name' must not be null");
    }

    @("bindWhenTargetIsNullShouldThrowException") unittest
    {
        Any instance;
        assertThrows!IllegalArgumentException(() {
            binder().bind(ConfigurationPropertyName.of("foo"), null, instance);
        }, "'target' must not be null");
    }
}

version (FlintBindHandler)
{
    // Gap: the Binder has no BindHandler (onStart, onSuccess, onCreate callbacks, ValidationBindHandler).
    import flint.boot.context.properties.bind : BindContext, BindHandler;

    /// Mockito's `mockBindHandler()`: answers with its argument and records the calls.
    class RecordingBindHandler : BindHandler
    {
        /// Part of the upstream test fixture.
        string[] calls;

        /// Part of the upstream test fixture.
        Bindable!T onStart(T)(ConfigurationPropertyName, Bindable!T target, BindContext)
        {
            return target;
        }

        /// Part of the upstream test fixture.
        Object onSuccess(ConfigurationPropertyName name, Object, BindContext, Object result)
        {
            calls ~= "onSuccess " ~ name.toString();
            return result;
        }

        /// Part of the upstream test fixture.
        Object onCreate(ConfigurationPropertyName name, Object, BindContext, Object result)
        {
            calls ~= "onCreate " ~ name.toString();
            return result;
        }
    }

    @("bindToValueShouldTriggerOnSuccess") unittest
    {
        auto handler = new RecordingBindHandler;
        binder(new MapConfigurationPropertySource("test", [["foo", "1"]])).bind!int("foo",
                Bindable!int.of(), handler);
        assert(handler.calls == ["onSuccess foo"]);
    }

    @("bindOrCreateWhenNotBoundShouldTriggerOnCreate") unittest
    {
        auto handler = new RecordingBindHandler;
        binder().bindOrCreate!JavaBean("foo", Bindable!JavaBean.of(), handler);
        assert(handler.calls == ["onCreate foo"]);
    }

    @("bindToJavaBeanShouldTriggerOnSuccess") unittest
    {
        auto handler = new RecordingBindHandler;
        binder(new MapConfigurationPropertySource("test", [["foo.value", "bar"]])).bind!JavaBean("foo",
                Bindable!JavaBean.of(), handler);
        assert(handler.calls == ["onSuccess foo.value", "onSuccess foo"]);
    }

    @("bindWhenHasCustomDefaultHandlerShouldTriggerOnSuccess") unittest
    {
        auto handler = new RecordingBindHandler;
        auto b = new Binder([
            cast(ConfigurationPropertySource) new MapConfigurationPropertySource("test", [
                ["foo.value", "bar"]
            ])
        ], null, null, handler);
        b.bind!JavaBean("foo");
        assert(handler.calls == ["onSuccess foo.value", "onSuccess foo"]);
    }

    @("bindToValidatedBeanWithResourceAndNonEnumerablePropertySource") unittest
    {
        import flint.boot.context.properties.bind.validation : ValidationBindHandler;
        import flint.core.io : Resource;
        import flint.validation.beanvalidation : LocalValidatorFactoryBean;

        static final class ResourceBean
        {
            private Resource resource;

            Resource getResource()
            {
                return resource;
            }

            void setResource(Resource resource)
            {
                this.resource = resource;
            }
        }

        auto validator = new LocalValidatorFactoryBean();
        binder(new NonIterableSource(new MapConfigurationPropertySource("test"))).bind!ResourceBean("foo",
                Bindable!ResourceBean.of(), new ValidationBindHandler(validator));
    }

    @("bindToJavaBeanWhenHandlerOnStartReturnsNullShouldReturnUnbound") unittest
    {
        static final class NullOnStart : BindHandler
        {
            Bindable!T onStart(T)(ConfigurationPropertyName, Bindable!T, BindContext)
            {
                return Bindable!T.init;
            }
        }

        auto result = binder(new MapConfigurationPropertySource("test", [["foo.value", "bar"]])).bind!JavaBean("foo",
                Bindable!JavaBean.of(), new NullOnStart);
        assert(!result.isBound());
    }
}

@("bindToJavaBeanWhenHasPropertyWithSameNameShouldStillBind") unittest
{
    // gh-10945
    auto source = new MapConfigurationPropertySource("test");
    source.put("foo", "boom");
    source.put("foo.value", "bar");
    auto result = binder(source).bind!JavaBean("foo").get();
    assert(result.getValue() == "bar");
}

version (FlintBindableApi)
{
    // Gap: Bindable carries no annotations, bind restrictions or bind method, and there is no LocalDate converter.
    import flint.boot.context.properties.bind : BindRestriction;
    import flint.format.annotation : DateTimeFormat, ISO;
    import flint.java.time : LocalDate;

    @("bindWhenHasAnnotationsShouldChangeConvertedValue") unittest
    {
        auto result = binder(new MapConfigurationPropertySource("test", [
                ["foo", "2014-04-01T01:30:00.000-05:00"]
        ])).bind!LocalDate("foo", Bindable!LocalDate.of().withAnnotations(DateTimeFormat(ISO.DATE_TIME))).get();
        assert(result.toString() == "2014-04-01");
    }

    @("bindToJavaBeanWithPublicConstructorWhenHasBindRestriction") unittest
    {
        auto b = binder(publicConstructorSource());
        auto result = b.bindOrCreate!JavaBeanWithPublicConstructor("foo",
                Bindable!JavaBeanWithPublicConstructor.of().withBindRestrictions(BindRestriction.NO_DIRECT_PROPERTY));
        assert(result.getValue() == "setter");
    }
}

@("bindToBeanWithCycle") unittest
{
    auto source = new MapConfigurationPropertySource("test");
    auto b = binder(new NonIterableSource(source));
    b.bind!CycleBean1("foo", Bindable!CycleBean1.of());
}

version (FlintStringConstructorConversion)
{
    // Gap: a value is not converted through the target's public single-String constructor (Spring's
    // ObjectToObjectConverter), so `foo=constructor` does not bind; the setter binding wins.
    @("bindToJavaBeanWithPublicConstructor") unittest
    {
        auto result = bindToJavaBeanWithPublicConstructor(binder(publicConstructorSource()));
        assert(result.getValue() == "constructor");
    }
}

// ---- BindResultTests ----------------------------------------------------------------------------------------

version (FlintBootNullArgumentChecks)
{
    // Gap: BindResult does not reject a null consumer or mapper.
    @("ifBoundWhenConsumerIsNullShouldThrowException") unittest
    {
        auto result = BindResult!string.of("foo");
        assertThrows!IllegalArgumentException(() { result.ifBound(null); }, "'consumer' must not be null");
    }

    @("mapWhenMapperIsNullShouldThrowException") unittest
    {
        auto result = BindResult!string.of("foo");
        assertThrows!IllegalArgumentException(() { result.map!string(null); }, "'mapper' must not be null");
    }
}

version (FlintBindResultApi)
{
    // Gap: BindResult has no orElseThrow, and `of(null)` is a bound null instead of the unbound result.
    import flint.java.io : IOException;

    @("orElseThrowWhenHasValueShouldReturnValue") unittest
    {
        auto result = BindResult!string.of("foo");
        assert(result.orElseThrow(() => new IOException()) == "foo");
    }

    @("orElseThrowWhenHasNoValueShouldThrowException") unittest
    {
        auto result = BindResult!string.of(null);
        assertThrows!IOException(() { result.orElseThrow(() => new IOException()); });
    }

    @("ofWhenValueIsNullShouldReturnUnbound") unittest
    {
        auto result = BindResult!string.of(null);
        assert(!result.isBound());
        assert(result == BindResult!string.of(null));
    }
}

@("hashCodeAndEquals") unittest
{
    const result1 = BindResult!string.of("foo");
    const result2 = BindResult!string.of("foo");
    const result3 = BindResult!string.of("bar");
    const result4 = BindResult!string.init;
    assert(hashOf(result1) == hashOf(result2));
    assert(result1 == result1 && result1 == result2 && result1 != result3 && result1 != result4);
}

@("ofWhenHasValueShouldReturnBoundResultOfValue") unittest
{
    auto result = BindResult!string.of("foo");
    assert(result.isBound());
    assert(result.get() == "foo");
}

// ---- PropertySourcesPlaceholdersResolverTests -------------------------------------------------------------

version (FlintPlaceholdersResolverHelper)
{
    // Gap: the resolver cannot be given a PropertyPlaceholderHelper with other delimiters.
    import flint.boot.context.properties.bind : PropertySourcesPlaceholdersResolver;
    import flint.util : PropertyPlaceholderHelper;

    @("resolveIfHelperPresentShouldUseIt") unittest
    {
        ConfigurationPropertySource[] sources = [
            new MapConfigurationPropertySource("test", [["FOO", "hello world"]])
        ];
        auto helper = new PropertyPlaceholderHelper("$<", ">");
        auto resolver = new PropertySourcesPlaceholdersResolver(sources, helper);
        assert(resolver.resolvePlaceholders("$<FOO>") == "hello world");
    }
}

import boot_tests.support : RegisterTests;

mixin RegisterTests;
