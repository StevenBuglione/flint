// Ported from spring-boot v4.2.0: core/spring-boot/src/test/java/org/springframework/boot/
// context/properties/bind/BindConverterTests.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: Boot's BindConverter is the binder's `convert(text, descriptor)`; a
// `ResolvableType` is the target's Flint AOT descriptor; Spring's ConverterNotFoundException is Flint's
// ConversionFailedException ("no converter for the type").
// Not ported (java.beans PropertyEditors and Java class loading):
// createWhenPropertyEditorInitializerIsNullShouldCreate,
// createWhenPropertyEditorInitializerIsNotNullShouldUseToInitialize, canConvertWhenHasDefaultEditorShouldReturnTrue,
// canConvertWhenHasCustomEditorShouldReturnTrue, canConvertWhenHasEditorByConventionShouldReturnTrue,
// canConvertWhenHasEditorForCollectionElementShouldReturnTrue, canConvertWhenHasEditorForArrayElementShouldReturnTrue,
// convertWhenHasDefaultEditorShouldConvert, convertWhenHasCustomEditorShouldConvert,
// convertWhenHasEditorByConventionShouldConvert, convertWhenHasEditorForCollectionElementShouldConvert,
// convertWhenHasEditorForArrayElementShouldConvert, convertWhenUsingTypeConverterConversionServiceFromMultipleThreads
// and convertWhenConversionFailsThrowsConversionFailedExceptionRatherThanConverterNotFoundException (`Class` from a
// class name).
module boot_tests.bind_converter_test;

import boot_tests.support : assertThrows;
import flint.boot.context.properties.bind : ConversionFailedException, convert;
import flint.engine.aot.descriptor : Descriptor, TypeKind, descriptorOf;

@safe:

/// `BindConverterTests.SampleType`.
final class SampleType
{
    private string text;

    string getText()
    {
        return text;
    }
}

@("convertWhenNotPropertyEditorAndConversionServiceCannotConvertShouldThrowException") unittest
{
    assertThrows!ConversionFailedException(() { convert("test", descriptorOf!SampleType()); });
}

@("fallsBackToApplicationConversionService") unittest
{
    import core.time : Duration;

    auto result = convert("10s", new Descriptor("core.time.Duration", TypeKind.struct_));
    assert(!result.isNull());
    assert(result.get!Duration
            .total!"seconds" == 10);
}

version (FlintBindConverterConversionService)
{
    // Gap: the converter cannot be given other ConversionServices (or Spring converters), and has no canConvert.
    import flint.boot.context.properties.bind : BindConverter;
    import flint.core.convert.support : GenericConversionService;
    import flint.java.io : File;

    /// `BindConverterTests.SampleTypeConverter`.
    final class SampleTypeConverter
    {
        /// Part of the upstream test fixture.
        SampleType convert(string source)
        {
            auto result = new SampleType;
            result.text = source;
            return result;
        }
    }

    private BindConverter getBindConverter(SampleTypeConverter converter)
    {
        auto service = new GenericConversionService();
        service.addConverter!(string, SampleType)(&converter.convert);
        return BindConverter.get([service], null);
    }

    @("canConvertWhenConversionServiceCanConvertShouldReturnTrue") unittest
    {
        auto bindConverter = getBindConverter(new SampleTypeConverter);
        assert(bindConverter.canConvert("test", descriptorOf!SampleType()));
    }

    @("canConvertWhenNotPropertyEditorAndConversionServiceCannotConvertShouldReturnFalse") unittest
    {
        auto bindConverter = BindConverter.get(null, null);
        assert(!bindConverter.canConvert("test", descriptorOf!SampleType()));
    }

    @("convertWhenConversionServiceCanConvertShouldConvert") unittest
    {
        auto bindConverter = getBindConverter(new SampleTypeConverter);
        auto converted = bindConverter.convert("test", descriptorOf!SampleType()).get!SampleType;
        assert(converted !is null);
        assert(converted.getText() == "test");
    }

    @("convertWhenConvertingToFileShouldExcludeFileEditor") unittest
    {
        // For back compatibility we want true file conversion and not an accidental classpath resource reference.
        // See gh-12163
        auto bindConverter = BindConverter.get([new GenericConversionService()], null);
        auto result = bindConverter.convert(".", descriptorOf!File()).get!File;
        assert(result !is null);
        assert(result.getPath() == ".");
    }
}

import boot_tests.support : RegisterTests;

mixin RegisterTests;
