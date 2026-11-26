/*
 * Ported from Jackson (jackson-core) 3.1.8, tag jackson-core-3.1.8:
 * src/test/java/tools/jackson/core/unittest/read/NextXxxAccessTest.java
 *
 * Jackson JSON-processor.
 * Copyright (c) 2007- Tatu Saloranta, tatu.saloranta@iki.fi
 * Licensed under the Apache License, Version 2.0.
 *
 * Modified by the Flint authors: translated the cases for Flint's byte-buffer parser.
 */
module next_xxx_access_test;

import flint.jackson.core : JsonToken;
import flint.jackson.core.exc : InputCoercionException;
import flint.jackson.core.json : JsonFactory;
import std.exception : assertThrown;

@safe:

@("nextIntValue")
unittest
{
    auto parser = JsonFactory.builder().build().createParser(`{"a":"123","b":5,"c":[false,456]}`);
    assert(parser.nextIntValue(0) == 0);
    assert(parser.currentToken() == JsonToken.START_OBJECT);
    assert(parser.nextIntValue(0) == 0);
    assert(parser.currentToken() == JsonToken.PROPERTY_NAME && parser.currentName() == "a");
    assert(parser.nextIntValue(0) == 0);
    assert(parser.currentToken() == JsonToken.VALUE_STRING && parser.getString() == "123");
    assert(parser.nextToken() == JsonToken.PROPERTY_NAME && parser.currentName() == "b");
    assert(parser.nextIntValue(0) == 5);
    assert(parser.nextName() == "c");
    assert(parser.nextIntValue(0) == 0);
    assert(parser.currentToken() == JsonToken.START_ARRAY);
    assert(parser.nextIntValue(0) == 0);
    assert(parser.currentToken() == JsonToken.VALUE_FALSE);
    assert(parser.nextIntValue(0) == 456);
    assert(parser.nextIntValue(0) == 0);
    assert(parser.currentToken() == JsonToken.END_ARRAY);
    assert(parser.nextIntValue(0) == 0);
    assert(parser.currentToken() == JsonToken.END_OBJECT);
    assert(parser.nextIntValue(0) == 0);
    assert(parser.currentToken() == JsonToken.NOT_AVAILABLE);
    parser.close();
}

@("nextLongValue")
unittest
{
    auto parser = JsonFactory.builder().build().createParser(`{"a":"xyz","b":-59,"c":[false,-1]}`);
    assert(parser.nextLongValue(0L) == 0L);
    assert(parser.currentToken() == JsonToken.START_OBJECT);
    assert(parser.nextLongValue(0L) == 0L);
    assert(parser.currentToken() == JsonToken.PROPERTY_NAME && parser.currentName() == "a");
    assert(parser.nextLongValue(0L) == 0L);
    assert(parser.currentToken() == JsonToken.VALUE_STRING && parser.getString() == "xyz");
    assert(parser.nextToken() == JsonToken.PROPERTY_NAME && parser.currentName() == "b");
    assert(parser.nextLongValue(0L) == -59L);
    assert(parser.nextName() == "c");
    assert(parser.nextLongValue(0L) == 0L);
    assert(parser.currentToken() == JsonToken.START_ARRAY);
    assert(parser.nextLongValue(0L) == 0L);
    assert(parser.currentToken() == JsonToken.VALUE_FALSE);
    assert(parser.nextLongValue(0L) == -1L);
    assert(parser.nextLongValue(0L) == 0L);
    assert(parser.currentToken() == JsonToken.END_ARRAY);
    assert(parser.nextLongValue(0L) == 0L);
    assert(parser.currentToken() == JsonToken.END_OBJECT);
    assert(parser.nextLongValue(0L) == 0L);
    assert(parser.currentToken() == JsonToken.NOT_AVAILABLE);
    parser.close();
}

@("isNextTokenName3")
unittest
{
    auto parser = JsonFactory.builder().build().createParser(`{"name":123,"name2":14,"x":"name"}`);
    assert(parser.nextName() is null);
    assert(parser.currentToken() == JsonToken.START_OBJECT);
    assert(parser.nextName() == "name");
    assert(parser.currentToken() == JsonToken.PROPERTY_NAME && parser.currentName() == "name");
    assert(parser.getString() == "name");
    assert(parser.nextName() is null);
    assert(parser.currentToken() == JsonToken.VALUE_NUMBER_INT && parser.getIntValue() == 123);
    assert(parser.nextName() == "name2");
    assert(parser.currentToken() == JsonToken.PROPERTY_NAME && parser.currentName() == "name2");
    assert(parser.nextToken() == JsonToken.VALUE_NUMBER_INT);
    assert(parser.nextName() == "x");
    assert(parser.currentToken() == JsonToken.PROPERTY_NAME && parser.currentName() == "x");
    assert(parser.nextName() is null);
    assert(parser.currentToken() == JsonToken.VALUE_STRING);
    assert(parser.nextName() is null);
    assert(parser.currentToken() == JsonToken.END_OBJECT);
    assert(parser.nextName() is null);
    assert(parser.currentToken() == JsonToken.NOT_AVAILABLE);
    parser.close();
}

@("nextTextValue")
unittest
{
    auto parser = JsonFactory.builder().build().createParser(`{"a":"123","b":5,"c":[false,"foo"]}`);
    assert(parser.nextStringValue() is null);
    assert(parser.currentToken() == JsonToken.START_OBJECT);
    assert(parser.nextStringValue() is null);
    assert(parser.currentToken() == JsonToken.PROPERTY_NAME && parser.currentName() == "a");
    assert(parser.nextStringValue() == "123");
    assert(parser.nextToken() == JsonToken.PROPERTY_NAME && parser.currentName() == "b");
    assert(parser.nextName() is null);
    assert(parser.currentToken() == JsonToken.VALUE_NUMBER_INT);
    assert(parser.nextName() == "c");
    assert(parser.nextStringValue() is null);
    assert(parser.currentToken() == JsonToken.START_ARRAY);
    assert(parser.nextStringValue() is null);
    assert(parser.currentToken() == JsonToken.VALUE_FALSE);
    assert(parser.nextStringValue() == "foo");
    assert(parser.nextStringValue() is null);
    assert(parser.currentToken() == JsonToken.END_ARRAY);
    assert(parser.nextStringValue() is null);
    assert(parser.currentToken() == JsonToken.END_OBJECT);
    assert(parser.nextStringValue() is null);
    assert(parser.currentToken() == JsonToken.NOT_AVAILABLE);
    parser.close();
}

@("integer advance retains defaults for floats and range exceptions for integer tokens")
unittest
{
    auto factory = JsonFactory.builder().build();
    auto ints = factory.createParser("[1.0,2147483648]");
    assert(ints.nextToken() == JsonToken.START_ARRAY);
    assert(ints.nextIntValue(-19) == -19);
    assert(ints.currentToken() == JsonToken.VALUE_NUMBER_FLOAT);
    assertThrown!InputCoercionException(ints.nextIntValue(-19));
    assert(ints.currentToken() == JsonToken.VALUE_NUMBER_INT);
    assert(ints.nextToken() == JsonToken.END_ARRAY);
    ints.close();

    auto longs = factory.createParser("[1.0,9223372036854775808]");
    assert(longs.nextToken() == JsonToken.START_ARRAY);
    assert(longs.nextLongValue(-29L) == -29L);
    assert(longs.currentToken() == JsonToken.VALUE_NUMBER_FLOAT);
    assertThrown!InputCoercionException(longs.nextLongValue(-29L));
    assert(longs.currentToken() == JsonToken.VALUE_NUMBER_INT);
    assert(longs.nextToken() == JsonToken.END_ARRAY);
    longs.close();
}
