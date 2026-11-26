/*
 * Ported from Jackson (jackson-core) 3.1.8, tag jackson-core-3.1.8:
 * src/test/java/tools/jackson/core/unittest/jsonptr/PointerFromContextTest.java
 *
 * Jackson JSON-processor.
 * Copyright (c) 2007- Tatu Saloranta, tatu.saloranta@iki.fi
 * Licensed under the Apache License, Version 2.0.
 *
 * Modified by the Flint authors: translated to D and used a byte-buffer generator.
 */
module pointer_from_context_test;

import flint.jackson.core : JsonGenerator, JsonParser, JsonPointer, JsonToken, ObjectWriteContext;
import flint.jackson.core.json : JsonFactory;
import flint.jackson.core.util : ByteArrayBuilder;

@safe:

private struct ReadStep
{
    JsonToken token;
    string path;
}

private void checkReadSteps(JsonParser parser, bool includeRoot, scope const(ReadStep)[] steps)
{
    foreach (step; steps)
    {
        assert(parser.nextToken() == step.token);
        auto context = parser.streamReadContext();
        auto pointer = includeRoot ? context.pathAsPointer(true) : context.pathAsPointer();
        assert(pointer.toString() == step.path);
        if (step.path.length == 0)
            assert(pointer is JsonPointer.empty());
    }
}

private JsonPointer writePointer(JsonGenerator generator, bool includeRoot)
{
    auto context = generator.streamWriteContext();
    return includeRoot ? context.pathAsPointer(true) : context.pathAsPointer();
}

@("testViaParser")
unittest
{
    auto parser = JsonFactory.builder().build().createParser(
            `{"a":123,"array":[1,2,[3],5,{"obInArray":4}],"ob":{"first":[false,true],"second":{"sub":37}},"b":true}`);
    assert(parser.streamReadContext().pathAsPointer() is JsonPointer.empty());
    checkReadSteps(parser, false, [
        ReadStep(JsonToken.START_OBJECT, ""), ReadStep(JsonToken.PROPERTY_NAME, "/a"),
        ReadStep(JsonToken.VALUE_NUMBER_INT, "/a"), ReadStep(JsonToken.PROPERTY_NAME, "/array"),
        ReadStep(JsonToken.START_ARRAY, "/array"), ReadStep(JsonToken.VALUE_NUMBER_INT,
                "/array/0"), ReadStep(JsonToken.VALUE_NUMBER_INT, "/array/1"),
        ReadStep(JsonToken.START_ARRAY, "/array/2"),
        ReadStep(JsonToken.VALUE_NUMBER_INT, "/array/2/0"), ReadStep(JsonToken.END_ARRAY,
                "/array/2"), ReadStep(JsonToken.VALUE_NUMBER_INT, "/array/3"),
        ReadStep(JsonToken.START_OBJECT, "/array/4"),
        ReadStep(JsonToken.PROPERTY_NAME, "/array/4/obInArray"),
        ReadStep(JsonToken.VALUE_NUMBER_INT, "/array/4/obInArray"),
        ReadStep(JsonToken.END_OBJECT, "/array/4"), ReadStep(JsonToken.END_ARRAY, "/array"),
        ReadStep(JsonToken.PROPERTY_NAME, "/ob"), ReadStep(JsonToken.START_OBJECT, "/ob"),
        ReadStep(JsonToken.PROPERTY_NAME, "/ob/first"), ReadStep(JsonToken.START_ARRAY,
                "/ob/first"), ReadStep(JsonToken.VALUE_FALSE, "/ob/first/0"),
        ReadStep(JsonToken.VALUE_TRUE, "/ob/first/1"), ReadStep(JsonToken.END_ARRAY,
                "/ob/first"), ReadStep(JsonToken.PROPERTY_NAME, "/ob/second"),
        ReadStep(JsonToken.START_OBJECT, "/ob/second"),
        ReadStep(JsonToken.PROPERTY_NAME, "/ob/second/sub"),
        ReadStep(JsonToken.VALUE_NUMBER_INT, "/ob/second/sub"),
        ReadStep(JsonToken.END_OBJECT, "/ob/second"), ReadStep(JsonToken.END_OBJECT, "/ob"),
        ReadStep(JsonToken.PROPERTY_NAME, "/b"), ReadStep(JsonToken.VALUE_TRUE, "/b"),
        ReadStep(JsonToken.END_OBJECT, ""),
    ]);
    assert(parser.nextToken() == JsonToken.NOT_AVAILABLE);
    parser.close();
}

@("testViaGenerator")
unittest
{
    auto output = new ByteArrayBuilder();
    auto g = JsonFactory.builder().build().createGenerator(ObjectWriteContext.empty(), output);
    enum includeRoot = false;
    assert(writePointer(g, includeRoot) is JsonPointer.empty());
    g.writeStartArray();
    assert(writePointer(g, includeRoot) is JsonPointer.empty());
    g.writeBoolean(true);
    assert(writePointer(g, includeRoot).toString() == "/0");
    g.writeStartObject();
    assert(writePointer(g, includeRoot).toString() == "/1");
    g.writeName("x");
    assert(writePointer(g, includeRoot).toString() == "/1/x");
    g.writeString("foo");
    assert(writePointer(g, includeRoot).toString() == "/1/x");
    g.writeName("stats");
    assert(writePointer(g, includeRoot).toString() == "/1/stats");
    g.writeStartObject();
    assert(writePointer(g, includeRoot).toString() == "/1/stats");
    g.writeName("rate");
    assert(writePointer(g, includeRoot).toString() == "/1/stats/rate");
    g.writeNumber(13);
    assert(writePointer(g, includeRoot).toString() == "/1/stats/rate");
    g.writeEndObject();
    assert(writePointer(g, includeRoot).toString() == "/1/stats");
    g.writeEndObject();
    assert(writePointer(g, includeRoot).toString() == "/1");
    g.writeEndArray();
    assert(writePointer(g, includeRoot) is JsonPointer.empty());
    g.close();
}

@("testParserWithRoot")
unittest
{
    auto parser = JsonFactory.builder().build().createParser("{\"a\":1,\"b\":3}\n{\"a\":5,\"c\":[1,2]}\n[1,2]\n");
    assert(parser.streamReadContext().pathAsPointer(true) is JsonPointer.empty());
    checkReadSteps(parser, true, [
        ReadStep(JsonToken.START_OBJECT, "/0"), ReadStep(JsonToken.PROPERTY_NAME, "/0/a"),
        ReadStep(JsonToken.VALUE_NUMBER_INT, "/0/a"), ReadStep(JsonToken.PROPERTY_NAME, "/0/b"),
        ReadStep(JsonToken.VALUE_NUMBER_INT, "/0/b"), ReadStep(JsonToken.END_OBJECT, "/0"),
        ReadStep(JsonToken.START_OBJECT, "/1"), ReadStep(JsonToken.PROPERTY_NAME, "/1/a"),
        ReadStep(JsonToken.VALUE_NUMBER_INT, "/1/a"), ReadStep(JsonToken.PROPERTY_NAME, "/1/c"),
        ReadStep(JsonToken.START_ARRAY, "/1/c"), ReadStep(JsonToken.VALUE_NUMBER_INT, "/1/c/0"),
        ReadStep(JsonToken.VALUE_NUMBER_INT, "/1/c/1"), ReadStep(JsonToken.END_ARRAY, "/1/c"),
        ReadStep(JsonToken.END_OBJECT, "/1"), ReadStep(JsonToken.START_ARRAY, "/2"),
        ReadStep(JsonToken.VALUE_NUMBER_INT, "/2/0"), ReadStep(JsonToken.VALUE_NUMBER_INT,
                "/2/1"), ReadStep(JsonToken.END_ARRAY, "/2"),
    ]);
    assert(parser.nextToken() == JsonToken.NOT_AVAILABLE);
    assert(parser.streamReadContext().pathAsPointer(true).toString() == "/2");
    parser.close();
}

@("testGeneratorWithRoot")
unittest
{
    auto output = new ByteArrayBuilder();
    auto g = JsonFactory.builder().build().createGenerator(ObjectWriteContext.empty(), output);
    enum includeRoot = true;
    assert(writePointer(g, includeRoot) is JsonPointer.empty());
    g.writeStartArray();
    assert(writePointer(g, includeRoot).toString() == "/0");
    g.writeBoolean(true);
    assert(writePointer(g, includeRoot).toString() == "/0/0");
    g.writeStartObject();
    assert(writePointer(g, includeRoot).toString() == "/0/1");
    g.writeName("x");
    assert(writePointer(g, includeRoot).toString() == "/0/1/x");
    g.writeString("foo");
    assert(writePointer(g, includeRoot).toString() == "/0/1/x");
    g.writeEndObject();
    assert(writePointer(g, includeRoot).toString() == "/0/1");
    g.writeEndArray();
    assert(writePointer(g, includeRoot).toString() == "/0");
    g.writeBoolean(true);
    assert(writePointer(g, includeRoot).toString() == "/1");
    g.writeStartArray();
    assert(writePointer(g, includeRoot).toString() == "/2");
    g.writeString("foo");
    assert(writePointer(g, includeRoot).toString() == "/2/0");
    g.writeString("bar");
    assert(writePointer(g, includeRoot).toString() == "/2/1");
    g.writeEndArray();
    assert(writePointer(g, includeRoot).toString() == "/2");
    assert(writePointer(g, includeRoot).toString() == "/2");
    g.close();
}

@("forPath escapes names, keeps empty property segments, and returns independent pointers")
unittest
{
    assert(JsonPointer.forPath(null, true) is JsonPointer.empty());
    auto parser = JsonFactory.builder().build().createParser(`{"a/b~": {"": 1}, "later": 2}`);
    assert(parser.nextToken() == JsonToken.START_OBJECT);
    assert(!parser.streamReadContext().hasPathSegment());
    assert(parser.nextToken() == JsonToken.PROPERTY_NAME);
    assert(parser.streamReadContext().hasPathSegment());
    assert(parser.nextToken() == JsonToken.START_OBJECT);
    assert(parser.nextToken() == JsonToken.PROPERTY_NAME);
    auto context = parser.streamReadContext();
    assert(context.hasCurrentName() && context.currentName().length == 0);
    auto pointer = JsonPointer.forPath(context, false);
    assert(pointer.toString() == "/a~1b~0/");
    assert(pointer.getMatchingProperty() == "a/b~");
    assert(pointer.tail().matchesProperty(""));
    assert(parser.streamReadContext().pathAsPointer(false).equals(pointer));
    assert(parser.nextToken() == JsonToken.VALUE_NUMBER_INT);
    assert(parser.nextToken() == JsonToken.END_OBJECT);
    assert(parser.nextToken() == JsonToken.PROPERTY_NAME);
    assert(pointer.toString() == "/a~1b~0/");
    parser.close();
}

@("empty property names survive both interner insertion and lookup")
unittest
{
    auto factory = JsonFactory.builder().build();
    foreach (iteration; 0 .. 2)
    {
        auto parser = factory.createParser(`{"":1}`);
        assert(parser.nextToken() == JsonToken.START_OBJECT);
        assert(parser.currentName() is null);
        assert(parser.nextToken() == JsonToken.PROPERTY_NAME);
        const name = parser.currentName();
        assert(name !is null && name == "");
        assert(parser.nextToken() == JsonToken.VALUE_NUMBER_INT);
        assert(parser.nextToken() == JsonToken.END_OBJECT);
        parser.close();
    }
}
