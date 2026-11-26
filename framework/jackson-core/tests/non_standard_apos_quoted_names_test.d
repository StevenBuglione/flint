/*
 * Ported from Jackson (jackson-core) 3.1.8, tag jackson-core-3.1.8:
 * src/test/java/tools/jackson/core/unittest/read/NonStandardAposQuotedNamesTest.java
 *
 * Jackson JSON-processor.
 * Copyright (c) 2007- Tatu Saloranta, tatu.saloranta@iki.fi
 * Licensed under the Apache License, Version 2.0.
 *
 * Modified by the Flint authors: translated JUnit assertions to D unittests; one byte parser serves every mode.
 */
module non_standard_apos_quoted_names_test;

import flint.jackson.core : JsonParser, JsonToken;
import flint.jackson.core.json : JsonReadFeature;
import read_test_support : parserWith, verifyException;

@safe:

private JsonParser apos(string doc)
{
    return parserWith(doc, JsonReadFeature.ALLOW_SINGLE_QUOTES);
}

@("singleQuotesDefault")
unittest
{
    foreach (doc; ["[ 'text' ]", "{ 'a':1 }"])
    {
        auto p = parserWith(doc);
        p.nextToken();
        try
        {
            p.nextToken();
            assert(false, "Expected exception");
        }
        catch (Exception e)
            verifyException(e, "Unexpected character ('''");
    }
}

// The second document of singleQuotesEnabled: names in nested Objects and Arrays.
private void testSingleQuotesNested()
{
    auto p = apos("{'b':1,'array':[{'b':3}],'ob':{'b':4,'x':0,'y':3,'a':false }}");
    assert(p.nextToken() == JsonToken.START_OBJECT);
    assert(p.nextToken() == JsonToken.PROPERTY_NAME && p.currentName() == "b");
    assert(p.nextToken() == JsonToken.VALUE_NUMBER_INT);
    assert(p.nextToken() == JsonToken.PROPERTY_NAME);
    assert(p.nextToken() == JsonToken.START_ARRAY);
    assert(p.nextToken() == JsonToken.START_OBJECT);
    assert(p.nextToken() == JsonToken.PROPERTY_NAME && p.currentName() == "b");
    assert(p.nextToken() == JsonToken.VALUE_NUMBER_INT && p.getIntValue() == 3);
    assert(p.nextToken() == JsonToken.END_OBJECT);
    assert(p.nextToken() == JsonToken.END_ARRAY);
    assert(p.nextToken() == JsonToken.PROPERTY_NAME);
    assert(p.nextToken() == JsonToken.START_OBJECT);
    assert(p.nextToken() == JsonToken.PROPERTY_NAME && p.currentName() == "b");
    assert(p.nextToken() == JsonToken.VALUE_NUMBER_INT && p.getIntValue() == 4);
    assert(p.nextToken() == JsonToken.PROPERTY_NAME && p.currentName() == "x");
    assert(p.nextToken() == JsonToken.VALUE_NUMBER_INT && p.getIntValue() == 0);
    assert(p.nextToken() == JsonToken.PROPERTY_NAME && p.currentName() == "y");
    assert(p.nextToken() == JsonToken.VALUE_NUMBER_INT && p.getIntValue() == 3);
    assert(p.nextToken() == JsonToken.PROPERTY_NAME && p.currentName() == "a");
    assert(p.nextToken() == JsonToken.VALUE_FALSE);
    assert(p.nextToken() == JsonToken.END_OBJECT);
    assert(p.nextToken() == JsonToken.END_OBJECT);
    p.close();
}

@("singleQuotesEnabled")
unittest
{
    auto p = apos(`{ 'a' : 1, "foobar": 'b', '_abc e\'23\'':'d\'foo\'', '"' : '""', '':'' }`);
    assert(p.nextToken() == JsonToken.START_OBJECT);
    assert(p.nextToken() == JsonToken.PROPERTY_NAME && p.getString() == "a");
    assert(p.nextToken() == JsonToken.VALUE_NUMBER_INT && p.getString() == "1");
    assert(p.nextToken() == JsonToken.PROPERTY_NAME && p.getString() == "foobar");
    assert(p.nextToken() == JsonToken.VALUE_STRING && p.getString() == "b");
    assert(p.nextToken() == JsonToken.PROPERTY_NAME && p.getString() == "_abc e'23'");
    assert(p.nextToken() == JsonToken.VALUE_STRING && p.getString() == "d'foo'");
    assert(p.nextToken() == JsonToken.PROPERTY_NAME && p.getString() == "\"");
    assert(p.nextToken() == JsonToken.VALUE_STRING);
    // An empty name and value are "", not null (D's "".idup is null).
    assert(p.nextToken() == JsonToken.PROPERTY_NAME && p.getString() == "" && p.currentName() !is null);
    assert(p.nextToken() == JsonToken.VALUE_STRING && p.getString() == "" && p.getString() !is null);
    assert(p.nextToken() == JsonToken.END_OBJECT);
    p.close();

    testSingleQuotesNested();
}

@("singleQuotesEscaped")
unittest
{
    auto p = apos(`[ '16\'' ]`);
    assert(p.nextToken() == JsonToken.START_ARRAY);
    assert(p.nextToken() == JsonToken.VALUE_STRING && p.getString() == "16'");
    assert(p.nextToken() == JsonToken.END_ARRAY);
    p.close();
}

private void testSingleQuotedKeys721(string doc, string expKey)
{
    auto p = apos(doc);
    assert(p.nextToken() == JsonToken.START_OBJECT);
    assert(p.nextName() == expKey);
    assert(p.nextToken() == JsonToken.VALUE_STRING && p.getString() == "value");
    assert(p.nextToken() == JsonToken.END_OBJECT);
    p.close();
}

@("singleQuotedKeys721")
unittest
{
    testSingleQuotedKeys721(`{ '""': 'value'}`, `""`);
    testSingleQuotedKeys721(`{ '"key"': 'value'}`, `"key"`);
}

private void testSingleQuotedValues721(string doc, string expValue)
{
    auto p = apos(doc);
    assert(p.nextToken() == JsonToken.START_OBJECT);
    assert(p.nextName() == "bar");
    assert(p.nextToken() == JsonToken.VALUE_STRING && p.getString() == expValue);
    assert(p.nextToken() == JsonToken.END_OBJECT);
    p.close();
}

@("singleQuotedValues721")
unittest
{
    testSingleQuotedValues721(`{ "bar": '""'}`, `""`);
    testSingleQuotedValues721(`{ "bar": '"stuff"'}`, `"stuff"`);
}

// Flint additions: escapes in single-quoted text decode as in double-quoted text, a surrogate pair joins, a lone
// surrogate is U+FFFD (R14), and an unclosed single-quoted value ends with Jackson's end-of-input error.
@("single-quoted text decodes escapes, surrogate pairs and multi-byte characters")
unittest
{
    auto p = apos(`['a\tbé😀\uD800x', 'zé中']`);
    assert(p.nextToken() == JsonToken.START_ARRAY);
    assert(p.nextToken() == JsonToken.VALUE_STRING && p.getString() == "a\tbé\U0001F600�x", p.getString());
    assert(p.nextToken() == JsonToken.VALUE_STRING && p.getString() == "zé中");
    auto open = apos("['never closed");
    assert(open.nextToken() == JsonToken.START_ARRAY);
    try
    {
        open.nextToken();
        assert(false);
    }
    catch (Exception e)
        verifyException(e, "was expecting closing quote for a string value");
}
