// Ported from spring-boot v4.2.0: core/spring-boot/src/test/java/org/springframework/boot/convert/LenientStringToEnumConverterFactoryTests.java
// with diagnostics/analyzer/BindFailureAnalyzerTests.java (bindExceptionForUnknownValueInEnumListsValidValuesInAction).
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: conversion goes through the Binder's converter on Flint AOT descriptors; the
// ConversionService and Locale variants (canConvert, Turkish locale) have no counterpart and are excluded.
module boot_tests.enum_binding_test;

import boot_tests.support : assertThrows;
import flint.boot.context.properties.bind : BindException, Binder, convert;
import flint.boot.context.properties.source : ConfigurationPropertySource, MapConfigurationPropertySource;
import flint.engine.aot.descriptor : descriptorOf;

@safe:

/// `TestEnum`.
enum TestEnum
{
    ONE,
    TWO,
    THREE_AND_FOUR
}

/// `TestOnOffEnum`.
enum TestOnOffEnum
{
    ONE,
    TWO,
    ON,
    OFF
}

/// `TestTrueFalseEnum`.
enum TestTrueFalseEnum
{
    ONE,
    TWO,
    TRUE,
    FALSE
}

/// `Fruit` of `BindFailureAnalyzerTests`.
enum Fruit
{
    APPLE,
    BANANA,
    ORANGE
}

private E conv(E)(string text)
{
    return convert(text, descriptorOf!E()).get!E;
}

@("convertFromStringToEnumWhenExactMatchShouldConvertValue") unittest
{
    assert(convert("", descriptorOf!TestEnum()).isNull());
    assert(conv!TestEnum("ONE") == TestEnum.ONE);
    assert(conv!TestEnum("TWO") == TestEnum.TWO);
    assert(conv!TestEnum("THREE_AND_FOUR") == TestEnum.THREE_AND_FOUR);
}

@("convertFromStringToEnumWhenFuzzyMatchShouldConvertValue") unittest
{
    assert(conv!TestEnum("one") == TestEnum.ONE);
    assert(conv!TestEnum("tWo") == TestEnum.TWO);
    foreach (spelling; ["three_and_four", "threeandfour", "three-and-four", "threeAndFour"])
        assert(conv!TestEnum(spelling) == TestEnum.THREE_AND_FOUR, spelling);
}

@("convertFromStringToEnumWhenYamlBooleanShouldConvertValue") unittest
{
    assert(conv!TestOnOffEnum("one") == TestOnOffEnum.ONE);
    assert(conv!TestOnOffEnum("two") == TestOnOffEnum.TWO);
    assert(conv!TestOnOffEnum("true") == TestOnOffEnum.ON);
    assert(conv!TestOnOffEnum("false") == TestOnOffEnum.OFF);
    assert(conv!TestOnOffEnum("TRUE") == TestOnOffEnum.ON);
    assert(conv!TestOnOffEnum("FALSE") == TestOnOffEnum.OFF);
    assert(conv!TestOnOffEnum("fA_lsE") == TestOnOffEnum.OFF);
    assert(conv!TestTrueFalseEnum("one") == TestTrueFalseEnum.ONE);
    assert(conv!TestTrueFalseEnum("true") == TestTrueFalseEnum.TRUE);
    assert(conv!TestTrueFalseEnum("FALSE") == TestTrueFalseEnum.FALSE);
}

/// A bean with an enum property.
final class FruitBean
{
    private Fruit fruit;

    /// The fruit.
    Fruit getFruit() const
    {
        return fruit;
    }

    /// Set the fruit.
    void setFruit(Fruit fruit)
    {
        this.fruit = fruit;
    }
}

private Binder binder(string[2][] entries)
{
    return new Binder([
        cast(ConfigurationPropertySource) new MapConfigurationPropertySource("test", entries)
    ]);
}

@("flint.bindEnumPropertyOntoBean") unittest
{
    auto b = binder([["test.foo.fruit", "banana"]]);
    b.getDescriptors().add(descriptorOf!Fruit());
    assert(b.bind!FruitBean("test.foo").get().getFruit() == Fruit.BANANA);
}

@("bindExceptionForUnknownValueInEnumListsValidValuesInAction") unittest
{
    import flint.boot.diagnostics : FailureAnalyzer;
    import flint.boot.diagnostics.analyzer : BindFailureAnalyzer;
    import std.algorithm.searching : canFind;

    auto b = binder([["test.foo.fruit", "apple,strawberry"]]);
    b.getDescriptors().add(descriptorOf!Fruit());
    BindException failure;
    try
        b.bind!FruitBean("test.foo");
    catch (BindException caught)
        failure = caught;
    assert(failure !is null);
    FailureAnalyzer analyzer = new BindFailureAnalyzer;
    const action = analyzer.analyze(failure).getAction();
    foreach (fruit; ["APPLE", "BANANA", "ORANGE"])
        assert(action.canFind(fruit), action);
}

import boot_tests.support : RegisterTests;

mixin RegisterTests;
