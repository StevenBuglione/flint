// Ported from spring-boot v4.2.0: core/spring-boot/src/test/java/org/springframework/boot/
// context/properties/bind/ArrayBinderTests.java: the tests boot_tests/collection_binder_test.d does not port (it holds
// bindToArrayWhenHasSpacesShouldTrim).
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: AssertJ assertions become D asserts; `Integer[]` and `int[]` are both `int[]`,
// `List<Integer>` is `flint.java.util.List!int`; the descriptors of nested element types are registered as Flint AOT
// registers them.
// Not ported: bindToArrayShouldUsePropertyEditor and bindToArrayWhenStringShouldUsePropertyEditor (java.beans
// PropertyEditor converting class names to `Class` objects).
module boot_tests.array_binder_upstream_test;

import boot_tests.upstream_support : NonIterableSource, binderOf, source;
import flint.boot.context.properties.bind : BindException, BindResult, Bindable;
import flint.java.util : List;

@safe:

@("bindToArrayShouldReturnArray") unittest
{
    const result = binderOf([source([["foo[0]", "1"], ["foo[1]", "2"], ["foo[2]", "3"]])]).bind!(int[])("foo").get();
    assert(result == [1, 2, 3]);
}

version (FlintBindHandler)
{
    // Gap: the Binder has no BindHandler.
    import boot_tests.binder_upstream_test : RecordingBindHandler;

    @("bindToCollectionShouldTriggerOnSuccess") unittest
    {
        auto handler = new RecordingBindHandler;
        binderOf([source([["foo[0]", "1"]])]).bind!(List!int)("foo", Bindable!(List!int).of(), handler);
        assert(handler.calls == ["onSuccess foo[0]", "onSuccess foo"]);
    }

    @("bindToArrayShouldTriggerOnSuccess") unittest
    {
        auto handler = new RecordingBindHandler;
        binderOf([source([["foo[0]", "1"]])]).bind!(int[])("foo", Bindable!(int[]).of(), handler);
        assert(handler.calls == ["onSuccess foo[0]", "onSuccess foo"]);
    }
}

@("bindToArrayShouldReturnPrimitiveArray") unittest
{
    const result = binderOf([source([["foo[0]", "1"], ["foo[1]", "2"], ["foo[2]", "3"]])]).bind!(int[])("foo").get();
    assert(result == [1, 2, 3]);
}

@("bindToArrayWhenNestedShouldReturnPopulatedArray") unittest
{
    auto result = binderOf!(int[])([
        source([["foo[0][0]", "1"], ["foo[0][1]", "2"], ["foo[1][0]", "3"], ["foo[1][1]", "4"]])
    ]).bind!(int[][])("foo").get();
    assert(result.length == 2 && result[0].length == 2 && result[1].length == 2);
    assert(result[0] == [1, 2]);
    assert(result[1] == [3, 4]);
}

version (FlintArrayOfClassElements)
{
    // Gap: an array of class references (`List!int[]`) cannot be bound: boxing it in `Any` is not @safe
    // (druntime's hashOf of a class array).
    @("bindToArrayWhenNestedListShouldReturnPopulatedArray") unittest
    {
        auto result = binderOf!(List!int)([
            source([["foo[0][0]", "1"], ["foo[0][1]", "2"], ["foo[1][0]", "3"], ["foo[1][1]", "4"]])
        ]).bind!(List!int[])("foo").get();
        assert(result.length == 2);
        assert(result[0].toArray() == [1, 2]);
        assert(result[1].toArray() == [3, 4]);
    }
}

@("bindToArrayWhenNotInOrderShouldReturnPopulatedArray") unittest
{
    const result = binderOf([source([["foo[1]", "2"], ["foo[0]", "1"], ["foo[2]", "3"]])]).bind!(int[])("foo").get();
    assert(result == [1, 2, 3]);
}

version (FlintUnboundIndexedElements)
{
    // Gap: binding stops at the first missing index instead of failing with UnboundConfigurationPropertiesException.
    import flint.boot.context.properties.bind : UnboundConfigurationPropertiesException;

    @("bindToArrayWhenNonSequentialShouldThrowException") unittest
    {
        try
        {
            binderOf([source([["foo[0]", "2"], ["foo[1]", "1"], ["foo[3]", "3"]])]).bind!(int[])("foo");
            assert(false, "expected a BindException");
        }
        catch (BindException ex)
        {
            auto cause = cast(UnboundConfigurationPropertiesException) ex.next;
            assert(cause !is null);
            auto unbound = cause.getUnboundProperties();
            assert(unbound.length == 1);
            assert(unbound[0].getName().toString() == "foo[3]");
            assert(unbound[0].getValue() == "3");
        }
    }
}

version (FlintNonIterableSourceBinding)
{
    // Gap: indexed elements are not bound from a source that cannot list its names (containsDescendantOf UNKNOWN).
    @("bindToArrayWhenNonIterableShouldReturnPopulatedArray") unittest
    {
        const result = binderOf([
            new NonIterableSource(source([["foo[1]", "2"], ["foo[0]", "1"], ["foo[2]", "3"]]))
        ]).bind!(int[])("foo").get();
        assert(result == [1, 2, 3]);
    }
}

@("bindToArrayWhenMultipleSourceShouldOnlyUseFirst") unittest
{
    const result = binderOf([
        source([["bar", "baz"]]), source([["foo[0]", "1"], ["foo[1]", "2"]]),
        source([["foo[0]", "7"], ["foo[1]", "8"], ["foo[2]", "9"]])
    ]).bind!(int[])("foo").get();
    assert(result == [1, 2]);
}

@("bindToArrayWhenHasExistingCollectionShouldReplaceAllContents") unittest
{
    int[] existing = [1000, 1001];
    const result = binderOf([source([["foo[0]", "1"]])]).bind!(int[])("foo", Bindable!(int[])
            .of().withExistingValue(existing)).get();
    assert(result == [1]);
}

@("bindToArrayWhenNoValueShouldReturnUnbound") unittest
{
    BindResult!(int[]) result = binderOf([source([["faf.bar", "1"]])]).bind!(int[])("foo");
    assert(!result.isBound());
}

@("bindToArrayWhenCommaListShouldReturnPopulatedArray") unittest
{
    const result = binderOf([source([["foo", "1,2,3"]])]).bind!(int[])("foo").get();
    assert(result == [1, 2, 3]);
}

@("bindToArrayWhenCommaListAndIndexedShouldOnlyUseFirst") unittest
{
    auto source1 = source([["foo", "1,2"]]);
    // Upstream also creates source2 (foo[0]=2, foo[1]=3) but never adds it.
    const result = binderOf([source1]).bind!(int[])("foo").get();
    assert(result == [1, 2]);
}

@("bindToArrayWhenIndexedAndCommaListShouldOnlyUseFirst") unittest
{
    auto source1 = source([["foo[0]", "1"], ["foo[1]", "2"]]);
    // Upstream also creates source2 (foo=2,3) but never adds it.
    const result = binderOf([source1]).bind!(int[])("foo").get();
    assert(result == [1, 2]);
}

version (FlintCharArrayConversion)
{
    // Gap: text does not convert to `char[]` (BindException: no converter for the type).
    @("bindToArrayShouldBindCharArray") unittest
    {
        const result = binderOf([source([["foo", "word"]])]).bind!(char[])("foo").get();
        assert(result == "word");
    }
}

@("bindToArrayWhenEmptyStringShouldReturnEmptyArray") unittest
{
    const result = binderOf([source([["foo", ""]])]).bind!(string[])("foo").get();
    assert(result.length == 0);
}

import boot_tests.support : RegisterTests;

mixin RegisterTests;
