/*
 * Ported from Jackson (jackson-core) 3.1.8 tests, https://github.com/FasterXML/jackson-core,
 * tag jackson-core-3.1.8, src/test/java/tools/jackson/core/unittest/write/WriteTypeIdTest.java.
 *
 * Jackson JSON-processor.
 * Copyright (c) 2007- Tatu Saloranta, tatu.saloranta@iki.fi
 * Licensed under the Apache License, Version 2.0.
 *
 * Modified by the Flint authors: translated to D with a UTF-8 output sink and
 * additional tests for native object ids and recovery after a rejected write.
 */
module native_ids_test;

import flint.engine.aot.any : Any;
import flint.jackson.core : JsonGenerator, JsonToken, ObjectWriteContext;
import flint.jackson.core.exc : StreamWriteException;
import flint.jackson.core.json : JsonFactory;
import flint.jackson.core.util : ByteArrayBuilder;

@safe:

private void expectIdFailure(JsonGenerator generator, void delegate() @safe operation, string message)
{
    try
    {
        operation();
    }
    catch (StreamWriteException error)
    {
        assert(error.msg == message);
        assert(error.processor() is generator);
        return;
    }
    assert(false, "expected StreamWriteException");
}

@("WriteTypeIdTest.noNativeTypeIdForJson")
unittest
{
    auto output = new ByteArrayBuilder;
    auto generator = JsonFactory.builder().build().createGenerator(ObjectWriteContext.empty(), output);
    assert(!generator.canWriteTypeId());
    expectIdFailure(generator, () { generator.writeTypeId(Any.of("whatever")); },
            "No native support for writing Type Ids");
    generator.close();
    assert(output.toUtf8String() == "");
}

@("native object IDs are rejected without changing the generator's context")
unittest
{
    auto output = new ByteArrayBuilder;
    auto generator = JsonFactory.builder().build().createGenerator(ObjectWriteContext.empty(), output);
    assert(!generator.canWriteObjectId());
    generator.writeStartObject();
    generator.writeName("value");
    auto id = Any.of(17);
    expectIdFailure(generator, () { generator.writeObjectId(id); }, "No native support for writing Object Ids");
    expectIdFailure(generator, () { generator.writeObjectRef(id); }, "No native support for writing Object Ids");
    generator.writeNumber(42);
    generator.writeEndObject();
    generator.close();
    assert(output.toUtf8String() == "{\"value\":42}");
}

@("JSON parser exposes no native ids on regular id properties")
unittest
{
    auto parser = JsonFactory.builder().build().createParser("{\"id\":\"thing\",\"type\":\"example\"}");
    assert(!parser.canReadObjectId());
    assert(!parser.canReadTypeId());
    assert(parser.nextToken() == JsonToken.START_OBJECT);
    assert(parser.getObjectId().isNull() && parser.getTypeId().isNull());
    assert(parser.nextToken() == JsonToken.PROPERTY_NAME);
    assert(parser.currentName() == "id");
    assert(parser.nextToken() == JsonToken.VALUE_STRING);
    assert(parser.getObjectId().isNull() && parser.getTypeId().isNull());
    assert(parser.getString() == "thing");
    assert(parser.nextToken() == JsonToken.PROPERTY_NAME);
    assert(parser.currentName() == "type");
    assert(parser.nextToken() == JsonToken.VALUE_STRING);
    assert(parser.getObjectId().isNull() && parser.getTypeId().isNull());
    assert(parser.getString() == "example");
    parser.close();
}
