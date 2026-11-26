/*
 * Ported from Jackson (jackson-core) 3.1.8, tag jackson-core-3.1.8:
 * src/test/java/tools/jackson/core/unittest/read/NonStandardLeadingPlusSign784Test.java
 *
 * Jackson JSON-processor.
 * Copyright (c) 2007- Tatu Saloranta, tatu.saloranta@iki.fi
 * Licensed under the Apache License, Version 2.0.
 *
 * Modified by the Flint authors: translated JUnit assertions to D unittests; one byte parser serves every mode.
 * jackson-core has no BigInteger accessor, so the overflow case checks the BIG_INTEGER number type only.
 */
module non_standard_leading_plus_sign784_test;

import flint.jackson.core : JsonParser, JsonToken;
import flint.jackson.core.json : JsonReadFeature;
import read_test_support : parserWith;

@safe:

private JsonParser plusParser(string doc)
{
    return parserWith(doc, JsonReadFeature.ALLOW_LEADING_PLUS_SIGN_FOR_NUMBERS,
            JsonReadFeature.ALLOW_LEADING_DECIMAL_POINT_FOR_NUMBERS);
}

private void testNumber(string numberString, JsonToken expectedToken)
{
    auto p = plusParser(" " ~ numberString ~ " ");
    assert(p.nextToken() == expectedToken, numberString);
    assert(p.getString() == numberString, "getText() returned wrong value for number: " ~ numberString);
}

private void testLong(string numberString, long expected)
{
    auto p = plusParser(" " ~ numberString ~ " ");
    assert(p.nextToken() == JsonToken.VALUE_NUMBER_INT);
    assert(p.getString() == numberString);
    assert(p.getLongValue() == expected, "wrong value for " ~ numberString);
}

@("testLeadingPlusSignConsistency")
unittest
{
    testNumber("+125", JsonToken.VALUE_NUMBER_INT);
    testNumber("+0.125", JsonToken.VALUE_NUMBER_FLOAT);
    testNumber("+1.25e2", JsonToken.VALUE_NUMBER_FLOAT);
    testNumber("+125.0", JsonToken.VALUE_NUMBER_FLOAT);
    testNumber("+0", JsonToken.VALUE_NUMBER_INT);
    testNumber("+1", JsonToken.VALUE_NUMBER_INT);
    testNumber("+.125", JsonToken.VALUE_NUMBER_FLOAT);
    testNumber("+.5", JsonToken.VALUE_NUMBER_FLOAT);
    testNumber("+.0", JsonToken.VALUE_NUMBER_FLOAT);
    testNumber("+1e2", JsonToken.VALUE_NUMBER_FLOAT);
    testNumber("+1e+2", JsonToken.VALUE_NUMBER_FLOAT);
    testNumber("+1e-2", JsonToken.VALUE_NUMBER_FLOAT);
}

@("testLeadingPlusSignLongValues")
unittest
{
    testLong("+999999999999999999", 999_999_999_999_999_999L);
    testLong("+1000000000000000000", 1_000_000_000_000_000_000L);
    testLong("+9223372036854775807", long.max);
    testLong("+2147483648", 2_147_483_648L);
    testLong("+1234567890", 1_234_567_890L);
    auto p = plusParser(" +9223372036854775808 ");
    assert(p.nextToken() == JsonToken.VALUE_NUMBER_INT);
    assert(p.getNumberType() == JsonParser.NumberType.BIG_INTEGER);
}
