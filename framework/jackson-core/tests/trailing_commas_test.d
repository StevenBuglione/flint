/*
 * Ported from Jackson (jackson-core) 3.1.8, tag jackson-core-3.1.8:
 * src/test/java/tools/jackson/core/unittest/read/TrailingCommasTest.java
 *
 * Jackson JSON-processor.
 * Copyright (c) 2007- Tatu Saloranta, tatu.saloranta@iki.fi
 * Licensed under the Apache License, Version 2.0.
 *
 * Modified by the Flint authors: translated the parameterized JUnit tests to D unittests that loop over the same
 * four feature sets (none, ALLOW_MISSING_VALUES, ALLOW_TRAILING_COMMA, both). Flint has one byte parser, so the
 * input modes are one case. objectTrailingCommaWithNextFieldNameStr needs nextName(SerializableString), which
 * jackson-core does not have yet.
 */
module trailing_commas_test;

import flint.jackson.core : JsonParser, JsonToken;
import flint.jackson.core.json : JsonReadFeature;
import read_test_support : assertEnd, parserWith, verifyException;

@safe:

private enum MISSING = JsonReadFeature.ALLOW_MISSING_VALUES;
private enum TRAILING = JsonReadFeature.ALLOW_TRAILING_COMMA;

private immutable JsonReadFeature[][] testCases = [[], [MISSING], [TRAILING], [MISSING, TRAILING]];

private bool has(const JsonReadFeature[] features, JsonReadFeature f) pure nothrow @nogc
{
    foreach (g; features)
        if (g == f)
            return true;
    return false;
}

private void assertUnexpected(JsonParser p, char c)
{
    import std.conv : to;

    try
    {
        p.nextToken();
        assert(false, "No exception thrown");
    }
    catch (Exception e)
        verifyException(e, "Unexpected character ('" ~ c ~ "' (code " ~ (cast(int) c).to!string ~ "))");
}

@("arrayBasic")
unittest
{
    foreach (features; testCases)
    {
        auto p = parserWith(`["a", "b"]`, features.dup);
        assert(p.nextToken() == JsonToken.START_ARRAY);
        assert(p.nextToken() == JsonToken.VALUE_STRING && p.getString() == "a");
        assert(p.nextToken() == JsonToken.VALUE_STRING && p.getString() == "b");
        assert(p.nextToken() == JsonToken.END_ARRAY);
        assertEnd(p);
    }
}

@("arrayInnerComma")
unittest
{
    foreach (features; testCases)
    {
        auto p = parserWith(`["a",, "b"]`, features.dup);
        assert(p.nextToken() == JsonToken.START_ARRAY);
        assert(p.nextToken() == JsonToken.VALUE_STRING && p.getString() == "a");
        if (!features.has(MISSING))
        {
            assertUnexpected(p, ',');
            continue;
        }
        assert(p.nextToken() == JsonToken.VALUE_NULL);
        assert(p.nextToken() == JsonToken.VALUE_STRING && p.getString() == "b");
        assert(p.nextToken() == JsonToken.END_ARRAY);
        assertEnd(p);
    }
}

@("arrayLeadingComma")
unittest
{
    foreach (features; testCases)
    {
        auto p = parserWith(`[,"a", "b"]`, features.dup);
        assert(p.nextToken() == JsonToken.START_ARRAY);
        if (!features.has(MISSING))
        {
            assertUnexpected(p, ',');
            continue;
        }
        assert(p.nextToken() == JsonToken.VALUE_NULL);
        assert(p.nextToken() == JsonToken.VALUE_STRING && p.getString() == "a");
        assert(p.nextToken() == JsonToken.VALUE_STRING && p.getString() == "b");
        assert(p.nextToken() == JsonToken.END_ARRAY);
        assertEnd(p);
    }
}

@("arrayTrailingComma")
unittest
{
    foreach (features; testCases)
    {
        auto p = parserWith(`["a", "b",]`, features.dup);
        assert(p.nextToken() == JsonToken.START_ARRAY);
        assert(p.nextToken() == JsonToken.VALUE_STRING && p.getString() == "a");
        assert(p.nextToken() == JsonToken.VALUE_STRING && p.getString() == "b");
        if (features.has(TRAILING))
        {
            assert(p.nextToken() == JsonToken.END_ARRAY);
            assertEnd(p);
        }
        else if (features.has(MISSING))
        {
            assert(p.nextToken() == JsonToken.VALUE_NULL);
            assert(p.nextToken() == JsonToken.END_ARRAY);
            assertEnd(p);
        }
        else
            assertUnexpected(p, ']');
    }
}

@("arrayTrailingCommas")
unittest
{
    foreach (features; testCases)
    {
        auto p = parserWith(`["a", "b",,]`, features.dup);
        assert(p.nextToken() == JsonToken.START_ARRAY);
        assert(p.nextToken() == JsonToken.VALUE_STRING && p.getString() == "a");
        assert(p.nextToken() == JsonToken.VALUE_STRING && p.getString() == "b");
        if (features.has(MISSING) && features.has(TRAILING))
        {
            assert(p.nextToken() == JsonToken.VALUE_NULL);
            assert(p.nextToken() == JsonToken.END_ARRAY);
            assertEnd(p);
        }
        else if (features.has(MISSING))
        {
            assert(p.nextToken() == JsonToken.VALUE_NULL);
            assert(p.nextToken() == JsonToken.VALUE_NULL);
            assert(p.nextToken() == JsonToken.END_ARRAY);
            assertEnd(p);
        }
        else
            assertUnexpected(p, ',');
    }
}

@("arrayTrailingCommasTriple")
unittest
{
    foreach (features; testCases)
    {
        auto p = parserWith(`["a", "b",,,]`, features.dup);
        assert(p.nextToken() == JsonToken.START_ARRAY);
        assert(p.nextToken() == JsonToken.VALUE_STRING && p.getString() == "a");
        assert(p.nextToken() == JsonToken.VALUE_STRING && p.getString() == "b");
        if (features.has(MISSING) && features.has(TRAILING))
        {
            assert(p.nextToken() == JsonToken.VALUE_NULL);
            assert(p.nextToken() == JsonToken.VALUE_NULL);
            assert(p.nextToken() == JsonToken.END_ARRAY);
            assertEnd(p);
        }
        else if (features.has(MISSING))
        {
            assert(p.nextToken() == JsonToken.VALUE_NULL);
            assert(p.nextToken() == JsonToken.VALUE_NULL);
            assert(p.nextToken() == JsonToken.VALUE_NULL);
            assert(p.nextToken() == JsonToken.END_ARRAY);
            assertEnd(p);
        }
        else
            assertUnexpected(p, ',');
    }
}

@("objectBasic")
unittest
{
    foreach (features; testCases)
    {
        auto p = parserWith(`{"a": true, "b": false}`, features.dup);
        assert(p.nextToken() == JsonToken.START_OBJECT);
        assert(p.nextToken() == JsonToken.PROPERTY_NAME && p.getString() == "a");
        assert(p.nextToken() == JsonToken.VALUE_TRUE);
        assert(p.nextToken() == JsonToken.PROPERTY_NAME && p.getString() == "b");
        assert(p.nextToken() == JsonToken.VALUE_FALSE);
        assert(p.nextToken() == JsonToken.END_OBJECT);
        assertEnd(p);
    }
}

@("objectInnerComma")
unittest
{
    foreach (features; testCases)
    {
        auto p = parserWith(`{"a": true,, "b": false}`, features.dup);
        assert(p.nextToken() == JsonToken.START_OBJECT);
        assert(p.nextToken() == JsonToken.PROPERTY_NAME && p.getString() == "a");
        assert(p.nextToken() == JsonToken.VALUE_TRUE);
        assertUnexpected(p, ',');
    }
}

@("objectLeadingComma")
unittest
{
    foreach (features; testCases)
    {
        auto p = parserWith(`{,"a": true, "b": false}`, features.dup);
        assert(p.nextToken() == JsonToken.START_OBJECT);
        assertUnexpected(p, ',');
    }
}

@("objectTrailingComma")
unittest
{
    foreach (features; testCases)
    {
        auto p = parserWith(`{"a": true, "b": false,}`, features.dup);
        assert(p.nextToken() == JsonToken.START_OBJECT);
        assert(p.nextToken() == JsonToken.PROPERTY_NAME && p.getString() == "a");
        assert(p.nextToken() == JsonToken.VALUE_TRUE);
        assert(p.nextToken() == JsonToken.PROPERTY_NAME && p.getString() == "b");
        assert(p.nextToken() == JsonToken.VALUE_FALSE);
        if (features.has(TRAILING))
        {
            assert(p.nextToken() == JsonToken.END_OBJECT);
            assertEnd(p);
        }
        else
            assertUnexpected(p, '}');
    }
}

@("objectTrailingCommaWithNextFieldName")
unittest
{
    foreach (features; testCases)
    {
        auto p = parserWith(`{"a": true, "b": false,}`, features.dup);
        assert(p.nextToken() == JsonToken.START_OBJECT);
        assert(p.nextName() == "a");
        assert(p.nextToken() == JsonToken.VALUE_TRUE);
        assert(p.nextName() == "b");
        assert(p.nextToken() == JsonToken.VALUE_FALSE);
        if (features.has(TRAILING))
        {
            assert(p.nextName() is null);
            assert(p.currentToken() == JsonToken.END_OBJECT);
            assertEnd(p);
        }
        else
        {
            try
            {
                p.nextName();
                assert(false, "No exception thrown");
            }
            catch (Exception e)
                verifyException(e, "Unexpected character ('}' (code 125))");
        }
    }
}

@("objectTrailingCommas")
unittest
{
    foreach (features; testCases)
    {
        auto p = parserWith(`{"a": true, "b": false,,}`, features.dup);
        assert(p.nextToken() == JsonToken.START_OBJECT);
        assert(p.nextToken() == JsonToken.PROPERTY_NAME && p.getString() == "a");
        assert(p.nextToken() == JsonToken.VALUE_TRUE);
        assert(p.nextToken() == JsonToken.PROPERTY_NAME && p.getString() == "b");
        assert(p.nextToken() == JsonToken.VALUE_FALSE);
        assertUnexpected(p, ',');
    }
}

// Flint addition: a missing Object value is null too (Jackson's _handleUnexpectedValue covers ',' in any scope).
@("a missing Object value is null with ALLOW_MISSING_VALUES and leaves its comma")
unittest
{
    auto p = parserWith(`{"a":,"b":1}`, MISSING);
    assert(p.nextToken() == JsonToken.START_OBJECT);
    assert(p.nextToken() == JsonToken.PROPERTY_NAME && p.currentName() == "a");
    assert(p.nextToken() == JsonToken.VALUE_NULL);
    assert(p.nextToken() == JsonToken.PROPERTY_NAME && p.currentName() == "b");
    assert(p.nextToken() == JsonToken.VALUE_NUMBER_INT && p.getIntValue() == 1);
    assert(p.nextToken() == JsonToken.END_OBJECT);
    auto strict = parserWith(`{"a":,"b":1}`);
    assert(strict.nextToken() == JsonToken.START_OBJECT);
    assert(strict.nextToken() == JsonToken.PROPERTY_NAME);
    assertUnexpected(strict, ',');
}
