/*
 * Ported from Jackson (jackson-core) 3.1.8, tag jackson-core-3.1.8:
 * src/test/java/tools/jackson/core/unittest/read/NonStandardUnquotedNamesTest.java
 *
 * Jackson JSON-processor.
 * Copyright (c) 2007- Tatu Saloranta, tatu.saloranta@iki.fi
 * Licensed under the Apache License, Version 2.0.
 *
 * Modified by the Flint authors: translated JUnit assertions to D unittests; one byte parser serves every mode.
 * unquotedIssue510's reader-mode input (padding, '{', 'a', U+0100) is the same bytes in UTF-8.
 */
module non_standard_unquoted_names_test;

import flint.jackson.core : JsonParser, JsonToken;
import flint.jackson.core.json : JsonReadFeature;
import read_test_support : parserWith, verifyException;

@safe:

private JsonParser unquoted(string doc)
{
    return parserWith(doc, JsonReadFeature.ALLOW_UNQUOTED_PROPERTY_NAMES);
}

private void testSimpleUnquoted()
{
    auto p = unquoted(`{ a : 1, _foo:true, $:"money!", " ":null }`);
    assert(p.nextToken() == JsonToken.START_OBJECT);
    assert(p.nextToken() == JsonToken.PROPERTY_NAME && p.currentName() == "a");
    assert(p.nextToken() == JsonToken.VALUE_NUMBER_INT);
    assert(p.nextToken() == JsonToken.PROPERTY_NAME && p.currentName() == "_foo");
    assert(p.nextToken() == JsonToken.VALUE_TRUE);
    assert(p.nextToken() == JsonToken.PROPERTY_NAME && p.currentName() == "$");
    assert(p.nextToken() == JsonToken.VALUE_STRING && p.getString() == "money!");
    assert(p.nextToken() == JsonToken.PROPERTY_NAME && p.currentName() == " ");
    assert(p.nextToken() == JsonToken.VALUE_NULL);
    assert(p.nextToken() == JsonToken.END_OBJECT);
    p.close();

    p = unquoted("{ 123:true,4:false }");
    assert(p.nextToken() == JsonToken.START_OBJECT);
    assert(p.nextToken() == JsonToken.PROPERTY_NAME && p.currentName() == "123");
    assert(p.nextToken() == JsonToken.VALUE_TRUE);
    assert(p.nextToken() == JsonToken.PROPERTY_NAME && p.currentName() == "4");
    assert(p.nextToken() == JsonToken.VALUE_FALSE);
    assert(p.nextToken() == JsonToken.END_OBJECT);
    p.close();
}

@("simpleUnquotedBytes")
unittest
{
    testSimpleUnquoted();
}

@("simpleUnquotedChars")
unittest
{
    testSimpleUnquoted();
}

@("largeUnquoted")
unittest
{
    import std.conv : to;

    enum reps = 1050;
    string json = "[\n";
    foreach (i; 0 .. reps)
    {
        if (i > 0)
        {
            json ~= ',';
            if ((i & 7) == 0)
                json ~= '\n';
        }
        json ~= "{abc" ~ (i & 127).to!string ~ ':' ~ ((i & 1) != 0 ? "true" : "false") ~ "}\n";
    }
    json ~= "]";
    auto p = unquoted(json);
    assert(p.nextToken() == JsonToken.START_ARRAY);
    foreach (i; 0 .. reps)
    {
        assert(p.nextToken() == JsonToken.START_OBJECT);
        assert(p.nextToken() == JsonToken.PROPERTY_NAME);
        assert(p.currentName() == "abc" ~ (i & 127).to!string);
        assert(p.nextToken() == ((i & 1) != 0 ? JsonToken.VALUE_TRUE : JsonToken.VALUE_FALSE));
        assert(p.nextToken() == JsonToken.END_OBJECT);
    }
    assert(p.nextToken() == JsonToken.END_ARRAY);
    p.close();
}

@("unquotedIssue510")
unittest
{
    string doc;
    foreach (i; 0 .. 3998)
        doc ~= ' ';
    doc ~= "{aĀ";
    auto p = unquoted(doc);
    assert(p.nextToken() == JsonToken.START_OBJECT);
    try
    {
        p.nextToken();
        assert(false, "Should not pass");
    }
    catch (Exception e)
        verifyException(e, "Unexpected end-of-input within/between Object entries");
    p.close();
}

@("nonStandardNameChars")
unittest
{
    enum json = `{ @type : "mytype", #color : 123, *error* : true, ` ~ ` hyphen-ated : "yes", me+my : null` ~ "}";
    auto p = unquoted(json);
    assert(p.nextToken() == JsonToken.START_OBJECT);
    assert(p.nextToken() == JsonToken.PROPERTY_NAME && p.getString() == "@type");
    assert(p.nextToken() == JsonToken.VALUE_STRING && p.getString() == "mytype");
    assert(p.nextToken() == JsonToken.PROPERTY_NAME && p.getString() == "#color");
    assert(p.nextToken() == JsonToken.VALUE_NUMBER_INT && p.getIntValue() == 123);
    assert(p.nextToken() == JsonToken.PROPERTY_NAME && p.getString() == "*error*");
    assert(p.nextToken() == JsonToken.VALUE_TRUE);
    assert(p.nextToken() == JsonToken.PROPERTY_NAME && p.getString() == "hyphen-ated");
    assert(p.nextToken() == JsonToken.VALUE_STRING && p.getString() == "yes");
    assert(p.nextToken() == JsonToken.PROPERTY_NAME && p.getString() == "me+my");
    assert(p.nextToken() == JsonToken.VALUE_NULL);
    assert(p.nextToken() == JsonToken.END_OBJECT);
    p.close();
}

// Flint additions: Jackson's two errors at the start of a name, and a quoted name still reads as before.
@("an unquoted name needs its feature and a name character to start")
unittest
{
    auto strict = parserWith("{ a : 1 }");
    assert(strict.nextToken() == JsonToken.START_OBJECT);
    try
    {
        strict.nextToken();
        assert(false);
    }
    catch (Exception e)
        verifyException(e, "was expecting double-quote to start property name");
    auto bad = unquoted("{ ? : 1 }");
    assert(bad.nextToken() == JsonToken.START_OBJECT);
    try
    {
        bad.nextToken();
        assert(false);
    }
    catch (Exception e)
        verifyException(e, "was expecting either valid name character (for unquoted name) or double-quote");
    auto quoted = unquoted(`{ "q" : 1 }`);
    assert(quoted.nextToken() == JsonToken.START_OBJECT);
    assert(quoted.nextToken() == JsonToken.PROPERTY_NAME && quoted.currentName() == "q");
}
