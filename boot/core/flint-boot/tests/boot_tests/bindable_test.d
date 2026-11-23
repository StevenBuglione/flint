// Ported from spring-boot v4.2.0: core/spring-boot/src/test/java/org/springframework/boot/
// context/properties/bind/BindableTests.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: AssertJ assertions become D asserts; one unittest per upstream @Test. Flint's
// `Bindable!T` carries its type statically and holds an existing value instead of a `Supplier`, so `getValue()` is
// the value itself and `of(Class)`/`of(ResolvableType)` are both `Bindable!T.of()`.
// Not ported (Java typing with no D counterpart: the target type is the template argument, checked at compile time,
// and D has no boxing): ofClassWhenTypeIsNullShouldThrowException, ofTypeWhenTypeIsNullShouldThrowException,
// ofClassShouldSetType, ofTypeShouldSetType, ofTypeWhenExistingValueIsNotInstanceOfTypeShouldThrowException,
// ofTypeWhenPrimitiveWithExistingValueWrapperShouldNotThrowException, getBoxedTypeWhenNotBoxedShouldReturnType,
// getBoxedTypeWhenPrimitiveShouldReturnBoxedType and getBoxedTypeWhenPrimitiveArrayShouldReturnBoxedType.
module boot_tests.bindable_test;

import flint.boot.context.properties.bind : Bindable;

@safe:

@("ofInstanceShouldSetTypeAndExistingValue") unittest
{
    const instance = "foo";
    static assert(is(typeof(Bindable!string.ofInstance(instance).getValue()) == string));
    auto value = Bindable!string.ofInstance(instance);
    assert(value.hasExistingValue());
    assert(value.getValue() == "foo");
}

@("ofClassWithExistingValueShouldSetTypeAndExistingValue") unittest
{
    auto value = Bindable!string.of().withExistingValue("foo");
    assert(value.hasExistingValue());
    assert(value.getValue() == "foo");
}

@("ofTypeWithExistingValueShouldSetTypeAndExistingValue") unittest
{
    auto value = Bindable!string.of().withExistingValue("foo");
    assert(value.hasExistingValue());
    assert(value.getValue() == "foo");
}

version (FlintBindableApi)
{
    // Gap: Bindable carries no annotations, bind restrictions, supplied value or bind method, and its equality is
    // D's field-wise struct equality (the existing value takes part).
    import flint.boot.context.properties.bind : BindMethod, BindRestriction;
    import flint.engine.aot.descriptor : MergedAnnotation;
    import flint.engine.aot.any : Any;
    import flint.java.lang : IllegalStateException;
    import boot_tests.support : assertThrows;

    /// `BindableTests.TestAnnotation`.
    struct TestAnnotation
    {
    }

    /// `BindableTests.JavaBeanOrValueObject`.
    final class JavaBeanOrValueObject
    {
        private string property;

        /// Part of the upstream test fixture.
        this(string property)
        {
            this.property = property;
        }

        string getProperty()
        {
            return property;
        }

        void setProperty(string property)
        {
            this.property = property;
        }
    }

    private MergedAnnotation annotation(A)(A value)
    {
        import flint.engine.aot.name : typeNameOf;

        return MergedAnnotation(typeNameOf!A, Any.of(value), 0);
    }

    @("getAnnotationsShouldReturnEmptyArray") unittest
    {
        assert(Bindable!string.of().getAnnotations().length == 0);
    }

    @("withAnnotationsShouldSetAnnotations") unittest
    {
        const a = annotation(TestAnnotation());
        assert(Bindable!string.of().withAnnotations(a).getAnnotations() == [a]);
    }

    @("getAnnotationWhenMatchShouldReturnAnnotation") unittest
    {
        const a = annotation(TestAnnotation());
        assert(Bindable!string.of().withAnnotations(a).getAnnotation!TestAnnotation() !is null);
    }

    @("getAnnotationWhenNoMatchShouldReturnNull") unittest
    {
        static struct Bean
        {
        }

        const a = annotation(TestAnnotation());
        assert(Bindable!string.of().withAnnotations(a).getAnnotation!Bean() is null);
    }

    @("toStringShouldShowDetails") unittest
    {
        import std.algorithm.searching : canFind;

        auto bindable = Bindable!string.of().withExistingValue("foo").withAnnotations(annotation(TestAnnotation()));
        assert(bindable.toString().canFind("type = string, value = 'provided', annotations = array<Annotation>["
                ~ "@boot_tests.bindable_test.TestAnnotation()]"));
    }

    @("equalsAndHashCode") unittest
    {
        const a = annotation(TestAnnotation());
        auto bindable1 = Bindable!string.of().withExistingValue("foo").withAnnotations(a);
        auto bindable2 = Bindable!string.of().withExistingValue("foo").withAnnotations(a);
        const bindable3 = Bindable!string.of().withExistingValue("fof").withAnnotations(a);
        assert(hashOf(bindable1) == hashOf(bindable2));
        assert(bindable1 == bindable1 && bindable1 == bindable2);
        assert(bindable1 == bindable3);
    }

    @("withExistingValueDoesNotForgetAnnotations") unittest
    {
        // gh-18218
        const a = annotation(TestAnnotation());
        auto bindable = Bindable!string.of().withAnnotations(a).withExistingValue("");
        assert(bindable.getAnnotations() == [a]);
    }

    @("withSuppliedValueDoesNotForgetAnnotations") unittest
    {
        // gh-18218
        const a = annotation(TestAnnotation());
        auto bindable = Bindable!string.of().withAnnotations(a).withSuppliedValue(() => "");
        assert(bindable.getAnnotations() == [a]);
    }

    @("hasBindRestrictionWhenDefaultReturnsFalse") unittest
    {
        import std.traits : EnumMembers;

        auto bindable = Bindable!string.of();
        foreach (bindRestriction; EnumMembers!BindRestriction)
            assert(!bindable.hasBindRestriction(bindRestriction));
    }

    @("withBindRestrictionAddsBindRestriction") unittest
    {
        auto bindable = Bindable!string.of();
        auto restricted = bindable.withBindRestrictions(BindRestriction.NO_DIRECT_PROPERTY);
        assert(!bindable.hasBindRestriction(BindRestriction.NO_DIRECT_PROPERTY));
        assert(restricted.hasBindRestriction(BindRestriction.NO_DIRECT_PROPERTY));
    }

    @("whenTypeCouldUseJavaBeanOrValueObjectJavaBeanBindingCanBeSpecified") unittest
    {
        const bindMethod = Bindable!JavaBeanOrValueObject.of().withBindMethod(BindMethod.JAVA_BEAN).getBindMethod();
        assert(bindMethod == BindMethod.JAVA_BEAN);
    }

    @("whenTypeCouldUseJavaBeanOrValueObjectExistingValueForcesJavaBeanBinding") unittest
    {
        const bindMethod = Bindable!JavaBeanOrValueObject.of()
            .withExistingValue(new JavaBeanOrValueObject("value")).getBindMethod();
        assert(bindMethod == BindMethod.JAVA_BEAN);
    }

    @("whenBindingIsValueObjectExistingValueThrowsException") unittest
    {
        assertThrows!IllegalStateException(() {
            Bindable!JavaBeanOrValueObject.of().withBindMethod(BindMethod.VALUE_OBJECT)
                .withExistingValue(new JavaBeanOrValueObject("value"));
        });
    }

    @("whenBindableHasExistingValueValueObjectBindMethodThrowsException") unittest
    {
        assertThrows!IllegalStateException(() {
            Bindable!JavaBeanOrValueObject.of().withExistingValue(new JavaBeanOrValueObject("value"))
                .withBindMethod(BindMethod.VALUE_OBJECT);
        });
    }

    @("whenBindableHasSuppliedValueValueObjectBindMethodThrowsException") unittest
    {
        assertThrows!IllegalStateException(() {
            Bindable!JavaBeanOrValueObject.of().withSuppliedValue(() => new JavaBeanOrValueObject("value"))
                .withBindMethod(BindMethod.VALUE_OBJECT);
        });
    }
}

import boot_tests.support : RegisterTests;

mixin RegisterTests;
