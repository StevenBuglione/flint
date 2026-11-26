/*
 * Ported from Jackson (jackson-core) 3.1.8 tests, https://github.com/FasterXML/jackson-core,
 * tag jackson-core-3.1.8, src/test/java/tools/jackson/core/unittest/json/JsonFactoryTest.java.
 *
 * Jackson JSON-processor.
 * Copyright (c) 2007- Tatu Saloranta, tatu.saloranta@iki.fi
 * Licensed under the Apache License, Version 2.0.
 *
 * Modified by the Flint authors: Flint always uses per-factory name canonicalization.
 */
module json_factory_copy_test;

import flint.jackson.core : JsonToken, ObjectWriteContext, StreamReadConstraints, StreamReadFeature,
    StreamWriteConstraints, StreamWriteFeature;
import flint.jackson.core.json : JsonFactory, JsonReadFeature, JsonWriteFeature;
import flint.jackson.core.util : ByteArrayBuilder;

@safe:

@("JsonFactoryTest.testCopy")
unittest
{
    auto defaults = new JsonFactory;
    assert(!defaults.isEnabled(JsonReadFeature.ALLOW_JAVA_COMMENTS));
    assert(!defaults.isEnabled(JsonWriteFeature.ESCAPE_NON_ASCII));

    auto readConstraints = StreamReadConstraints.defaults();
    readConstraints.maxNestingDepth = 19;
    auto writeConstraints = StreamWriteConstraints.builder().maxNestingDepth(31).build();
    auto factory = defaults.rebuild().enable(JsonReadFeature.ALLOW_JAVA_COMMENTS)
        .enable(JsonWriteFeature.ESCAPE_NON_ASCII)
        .enable(StreamReadFeature.STRICT_DUPLICATE_DETECTION).disable(StreamWriteFeature.FLUSH_PASSED_TO_STREAM)
        .streamReadConstraints(readConstraints)
        .streamWriteConstraints(writeConstraints).rootValueSeparator("/").build();
    auto copy = factory.copy();
    assert(copy !is factory);
    assert(copy.isEnabled(JsonReadFeature.ALLOW_JAVA_COMMENTS));
    assert(copy.isEnabled(JsonWriteFeature.ESCAPE_NON_ASCII));
    assert(copy.isEnabled(StreamReadFeature.STRICT_DUPLICATE_DETECTION));
    assert(!copy.isEnabled(StreamWriteFeature.FLUSH_PASSED_TO_STREAM));
    assert(copy.streamReadConstraints().maxNestingDepth == 19);
    assert(copy.streamWriteConstraints().getMaxNestingDepth() == 31);

    auto parser = copy.createParser("42");
    assert(parser.nextToken() == JsonToken.VALUE_NUMBER_INT);
    assert(parser.getIntValue() == 42);
    parser.close();

    auto output = new ByteArrayBuilder;
    auto generator = copy.createGenerator(ObjectWriteContext.empty(), output);
    generator.writeString("café");
    generator.writeNumber(21);
    generator.close();
    assert(output.toUtf8String() == "\"caf\\u00E9\"/21");
}

private string parsedPropertyName(JsonFactory factory)
{
    auto parser = factory.createParser(`{"label":1}`);
    assert(parser.nextToken() == JsonToken.START_OBJECT);
    assert(parser.nextToken() == JsonToken.PROPERTY_NAME);
    auto name = parser.currentName();
    parser.close();
    return name;
}

@("a factory copy starts with independent canonical property names")
unittest
{
    auto factory = new JsonFactory;
    const name = parsedPropertyName(factory);
    auto copy = factory.copy();
    const copiedName = parsedPropertyName(copy);
    assert(name == "label" && copiedName == name);
    assert(copiedName !is name);
    assert(parsedPropertyName(factory) is name);
    assert(parsedPropertyName(copy) is copiedName);
}
