/*
 * Ported from Jackson (jackson-core) 3.1.8, tag jackson-core-3.1.8:
 * src/test/java/tools/jackson/core/unittest/read/NonStandardJsonReadFeaturesTest.java
 *
 * Jackson JSON-processor.
 * Copyright (c) 2007- Tatu Saloranta, tatu.saloranta@iki.fi
 * Licensed under the Apache License, Version 2.0.
 *
 * Modified by the Flint authors: translated JUnit assertions to D unittests; one byte parser serves every mode.
 * jackson-core has no BigDecimal accessor, so allowNaN's getDecimalValue check and the Integer class check of
 * leadingZeroes are not ported; the rest of each method is.
 */
module non_standard_json_read_features_test;

import flint.jackson.core : JsonParser, JsonToken;
import flint.jackson.core.json : JsonFactory, JsonReadFeature;
import read_test_support : parserWith, verifyException;

@safe:

@("defaults")
unittest
{
    auto f = new JsonFactory();
    assert(!f.isEnabled(JsonReadFeature.ALLOW_LEADING_ZEROS_FOR_NUMBERS));
    assert(!f.isEnabled(JsonReadFeature.ALLOW_NON_NUMERIC_NUMBERS));
}

@("nonStandardAnyCharQuoting")
unittest
{
    enum json = `"\'"`;
    auto p = parserWith(json);
    try
    {
        p.nextToken();
        p.getString();
        assert(false, "Should have thrown an exception for doc <" ~ json ~ ">");
    }
    catch (Exception e)
        verifyException(e, "unrecognized character escape");
    p.close();
    p = parserWith(json, JsonReadFeature.ALLOW_BACKSLASH_ESCAPING_ANY_CHARACTER);
    assert(p.nextToken() == JsonToken.VALUE_STRING);
    assert(p.getString() == "'");
    p.close();
}

private void testLeadingZeroes(bool appendSpace)
{
    import std.conv : to;

    string json = "00003" ~ (appendSpace ? " " : "");
    auto p = parserWith(json);
    try
    {
        p.nextToken();
        p.getString();
        assert(false, "Should have thrown an exception for doc <" ~ json ~ ">");
    }
    catch (Exception e)
        verifyException(e, "invalid numeric value");
    p = parserWith("[ -000 ]");
    assert(p.nextToken() == JsonToken.START_ARRAY);
    try
    {
        p.nextToken();
        assert(false, "Should have thrown an exception");
    }
    catch (Exception e)
        verifyException(e, "invalid numeric value");
    p = parserWith(json, JsonReadFeature.ALLOW_LEADING_ZEROS_FOR_NUMBERS);
    assert(p.nextToken() == JsonToken.VALUE_NUMBER_INT);
    assert(p.getIntValue() == 3 && p.getString() == "3");
    json = "0" ~ int.max.to!string ~ (appendSpace ? " " : "");
    p = parserWith(json, JsonReadFeature.ALLOW_LEADING_ZEROS_FOR_NUMBERS);
    assert(p.nextToken() == JsonToken.VALUE_NUMBER_INT);
    assert(p.getString() == int.max.to!string && p.getIntValue() == int.max);
    assert(p.getNumberType() == JsonParser.NumberType.INT);
    p = parserWith("[000]", JsonReadFeature.ALLOW_LEADING_ZEROS_FOR_NUMBERS);
    assert(p.nextToken() == JsonToken.START_ARRAY);
    assert(p.nextToken() == JsonToken.VALUE_NUMBER_INT && p.getIntValue() == 0 && p.getString() == "0");
    assert(p.nextToken() == JsonToken.END_ARRAY);
}

@("leadingZeroesUTF8")
unittest
{
    testLeadingZeroes(false);
    testLeadingZeroes(true);
}

@("leadingZeroesReader")
unittest
{
    testLeadingZeroes(false);
    testLeadingZeroes(true);
}

@("allowNaN")
unittest
{
    import std.math : isNaN;

    enum json = "[ NaN]";
    auto p = parserWith(json);
    assert(p.nextToken() == JsonToken.START_ARRAY);
    try
    {
        p.nextToken();
        assert(false, "Expected exception");
    }
    catch (Exception e)
        verifyException(e, "non-standard");
    p = parserWith(json, JsonReadFeature.ALLOW_NON_NUMERIC_NUMBERS);
    assert(p.nextToken() == JsonToken.START_ARRAY);
    assert(p.nextToken() == JsonToken.VALUE_NUMBER_FLOAT);
    assert(isNaN(p.getDoubleValue()) && p.isNaN());
    assert(p.getString() == "NaN");
    assert(p.nextToken() == JsonToken.END_ARRAY);
}

@("allowInfinity")
unittest
{
    enum json = "[ -INF, +INF, +Infinity, Infinity, -Infinity ]";
    auto p = parserWith(json);
    assert(p.nextToken() == JsonToken.START_ARRAY);
    try
    {
        p.nextToken();
        assert(false, "Expected exception");
    }
    catch (Exception e)
        verifyException(e, "Non-standard token '-INF'");
    p = parserWith(json, JsonReadFeature.ALLOW_NON_NUMERIC_NUMBERS);
    assert(p.nextToken() == JsonToken.START_ARRAY);
    foreach (expected; ["-INF", "+INF", "+Infinity", "Infinity", "-Infinity"])
    {
        assert(p.nextToken() == JsonToken.VALUE_NUMBER_FLOAT);
        immutable d = p.getDoubleValue();
        assert(p.getString() == expected && p.isNaN());
        assert(d == (expected[0] == '-' ? -double.infinity : double.infinity));
    }
    assert(p.nextToken() == JsonToken.END_ARRAY);
    p.close();
}
