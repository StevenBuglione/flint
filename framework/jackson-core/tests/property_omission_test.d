/*
 * Ported from Jackson (jackson-core) 3.1.8 tests, https://github.com/FasterXML/jackson-core,
 * tag jackson-core-3.1.8, src/test/java/tools/jackson/core/unittest/json/StreamWriteFeaturesTest.java.
 *
 * Jackson JSON-processor.
 * Copyright (c) 2007- Tatu Saloranta, tatu.saloranta@iki.fi
 * Licensed under the Apache License, Version 2.0.
 *
 * Modified by the Flint authors: the single UTF-8 generator exercises the settings from its factory.
 */
module property_omission_test;

import flint.jackson.core : ObjectWriteContext, StreamWriteFeature;
import flint.jackson.core.json : JsonFactory, JsonWriteFeature;
import flint.jackson.core.util : ByteArrayBuilder;

@safe:

@("configDefaults")
unittest
{
    auto output = new ByteArrayBuilder;
    auto factory = new JsonFactory;
    auto generator = factory.createGenerator(ObjectWriteContext.empty(), output);
    assert(!factory.isEnabled(JsonWriteFeature.WRITE_NUMBERS_AS_STRINGS));
    assert(!generator.isEnabled(StreamWriteFeature.WRITE_BIGDECIMAL_AS_PLAIN));
    assert(generator.canOmitProperties());
    assert(!generator.canWriteObjectId());
    assert(!generator.canWriteTypeId());
    generator.writeNumber(13);
    generator.close();
    assert(output.toUtf8String() == "13");
}

@("omitting properties preserves JSON separators and generator identity")
unittest
{
    auto output = new ByteArrayBuilder;
    auto generator = new JsonFactory().createGenerator(ObjectWriteContext.empty(), output);
    generator.writeStartObject();
    assert(generator.writeOmittedProperty("first") is generator);
    generator.writeObjectPropertyStart("outer");
    generator.writeOmittedProperty("only");
    generator.writeEndObject();
    generator.writeOmittedProperty("middle");
    generator.writeNumberProperty("last", 23);
    generator.writeOmittedProperty("trailing");
    generator.writeEndObject();
    generator.close();
    assert(output.toUtf8String() == "{\"outer\":{},\"last\":23}");
}
