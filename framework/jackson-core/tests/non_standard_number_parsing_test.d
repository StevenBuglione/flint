/*
 * Ported from Jackson (jackson-core) 3.1.8, tag jackson-core-3.1.8:
 * src/test/java/tools/jackson/core/unittest/read/NonStandardNumberParsingTest.java
 *
 * Jackson JSON-processor.
 * Copyright (c) 2007- Tatu Saloranta, tatu.saloranta@iki.fi
 * Licensed under the Apache License, Version 2.0.
 *
 * Modified by the Flint authors: translated JUnit assertions to D unittests; one byte parser serves every mode (the
 * Bytes, Reader and DataInput variants run the same checks). jackson-core has no BigDecimal accessor, no
 * nextName(SerializableString) and no PropertyNameMatcher: largeDecimal is not ported, the getDecimalValue
 * assertions are left out of the other methods, and leadingDotAsFieldValue checks its nextName() form.
 */
module non_standard_number_parsing_test;

import flint.jackson.core : JsonParser, JsonToken;
import flint.jackson.core.json : JsonReadFeature;
import read_test_support : parserWith, verifyException;

@safe:

private enum PLUS = JsonReadFeature.ALLOW_LEADING_PLUS_SIGN_FOR_NUMBERS;
private enum LEADING = JsonReadFeature.ALLOW_LEADING_DECIMAL_POINT_FOR_NUMBERS;
private enum TRAILING = JsonReadFeature.ALLOW_TRAILING_DECIMAL_POINT_FOR_NUMBERS;

private JsonParser jsonF(string doc)
{
    return parserWith(doc, PLUS, LEADING, TRAILING);
}

private void failsWith(string doc, string expected)
{
    auto p = parserWith(doc);
    try
    {
        p.nextToken();
        assert(false, "Should not pass: " ~ doc);
    }
    catch (Exception e)
        verifyException(e, expected);
}

@("hexadecimal")
unittest
{
    failsWith(" 0xc0ffee ", "Unexpected character ('x'");
}

@("hexadecimalBigX")
unittest
{
    failsWith(" 0XC0FFEE ", "Unexpected character ('x'");
}

@("negativeHexadecimal")
unittest
{
    failsWith(" -0xc0ffee ", "Unexpected character ('x'");
}

@("floatMarker")
unittest
{
    failsWith(" -0.123f ", "Unexpected character ('f'");
}

@("doubleMarker")
unittest
{
    failsWith(" -0.123d ", "Unexpected character ('d'");
}

@("test2DecimalPoints")
unittest
{
    failsWith(" -0.123.456 ", "Unexpected character ('.'");
}

@("leadingDotInDecimal")
unittest
{
    failsWith(" .123 ", "Unexpected character ('.'");
}

@("leadingPlusSignInDecimalDefaultFail")
unittest
{
    enum message = "Unexpected character ('+' (code 43)) in numeric value: JSON spec does not allow numbers to have "
        ~ "plus signs: enable `JsonReadFeature.ALLOW_LEADING_PLUS_SIGN_FOR_NUMBERS` to allow";
    failsWith(" +123 ", message);
    failsWith(" +0.123 ", message);
}

@("trailingDotInDecimal")
unittest
{
    failsWith(" 123. ", "Decimal point not followed by a digit");
}

private void testLeadingDotInDecimalAllowed()
{
    auto p = jsonF(" .125 ");
    assert(p.nextToken() == JsonToken.VALUE_NUMBER_FLOAT);
    assert(p.getValueAsDouble() == 0.125);
    assert(p.getString() == ".125");
}

@("testLeadingDotInDecimalAllowedDataInput")
unittest
{
    testLeadingDotInDecimalAllowed();
}

@("testLeadingDotInDecimalAllowedBytes")
unittest
{
    testLeadingDotInDecimalAllowed();
}

@("testLeadingDotInDecimalAllowedReader")
unittest
{
    testLeadingDotInDecimalAllowed();
}

private void testTrailingDotInDecimalAllowed()
{
    auto p = jsonF(" 125. ");
    assert(p.nextToken() == JsonToken.VALUE_NUMBER_FLOAT);
    assert(p.getValueAsDouble() == 125.0);
    assert(p.getString() == "125.");
}

@("testTrailingDotInDecimalAllowedDataInput")
unittest
{
    testTrailingDotInDecimalAllowed();
}

@("testTrailingDotInDecimalAllowedBytes")
unittest
{
    testTrailingDotInDecimalAllowed();
}

@("trailingDotInDecimalAllowedReader")
unittest
{
    testTrailingDotInDecimalAllowed();
}

private void testLeadingPlusSignInDecimalAllowed()
{
    auto p = jsonF(" +125 ");
    assert(p.nextToken() == JsonToken.VALUE_NUMBER_INT);
    assert(p.getValueAsDouble() == 125.0 && p.getString() == "+125");
    p = jsonF(" +0.125 ");
    assert(p.nextToken() == JsonToken.VALUE_NUMBER_FLOAT);
    assert(p.getValueAsDouble() == 0.125 && p.getString() == "+0.125");
    p = jsonF(" +.125 ");
    assert(p.nextToken() == JsonToken.VALUE_NUMBER_FLOAT);
    assert(p.getValueAsDouble() == 0.125 && p.getString() == "+.125");
}

@("leadingPlusSignInDecimalAllowedDataInput")
unittest
{
    testLeadingPlusSignInDecimalAllowed();
}

@("leadingPlusSignInDecimalAllowedBytes")
unittest
{
    testLeadingPlusSignInDecimalAllowed();
}

@("leadingPlusSignInDecimalAllowedReader")
unittest
{
    testLeadingPlusSignInDecimalAllowed();
}

private void testLeadingDotAsFieldValue()
{
    auto p = jsonF(`{"a": .125}`);
    assert(p.nextToken() == JsonToken.START_OBJECT);
    assert(p.nextName() == "a");
    assert(p.nextToken() == JsonToken.VALUE_NUMBER_FLOAT);
    assert(p.getValueAsDouble() == 0.125 && p.getString() == ".125");
    assert(p.nextToken() == JsonToken.END_OBJECT);
}

@("leadingDotAsFieldValueBytes")
unittest
{
    testLeadingDotAsFieldValue();
}

@("leadingDotAsFieldValueReader")
unittest
{
    testLeadingDotAsFieldValue();
}

@("leadingDotAsFieldValueDataInput")
unittest
{
    testLeadingDotAsFieldValue();
}

private void testSignedLeadingDotAsFieldValue()
{
    auto p = jsonF(`{"a": -.125}`);
    assert(p.nextToken() == JsonToken.START_OBJECT);
    assert(p.nextName() == "a");
    assert(p.nextToken() == JsonToken.VALUE_NUMBER_FLOAT);
    assert(p.getValueAsDouble() == -0.125 && p.getString() == "-.125");
    assert(p.nextToken() == JsonToken.END_OBJECT);
    p = jsonF(`{"a": +.125}`);
    assert(p.nextToken() == JsonToken.START_OBJECT);
    assert(p.nextName() == "a");
    assert(p.nextToken() == JsonToken.VALUE_NUMBER_FLOAT);
    assert(p.getValueAsDouble() == 0.125 && p.getString() == "+.125");
    assert(p.nextToken() == JsonToken.END_OBJECT);
}

@("signedLeadingDotAsFieldValueBytes")
unittest
{
    testSignedLeadingDotAsFieldValue();
}

@("signedLeadingDotAsFieldValueReader")
unittest
{
    testSignedLeadingDotAsFieldValue();
}

@("signedLeadingDotAsFieldValueDataInput")
unittest
{
    testSignedLeadingDotAsFieldValue();
}

private void testLeadingDotAsFieldValueFails()
{
    auto p = parserWith(`{"a": .125}`);
    try
    {
        p.nextToken();
        p.nextName();
        p.nextToken();
        assert(false, "Should not pass");
    }
    catch (Exception e)
        verifyException(e, "Unexpected character ('.'");
}

@("leadingDotAsFieldValueFailsWhenDisabledBytes")
unittest
{
    testLeadingDotAsFieldValueFails();
}

@("leadingDotAsFieldValueFailsWhenDisabledReader")
unittest
{
    testLeadingDotAsFieldValueFails();
}

@("leadingDotAsFieldValueFailsWhenDisabledDataInput")
unittest
{
    testLeadingDotAsFieldValueFails();
}

private void testLeadingDotInNegativeDecimalAllowed()
{
    auto p = jsonF(" -.125 ");
    assert(p.nextToken() == JsonToken.VALUE_NUMBER_FLOAT);
    assert(p.getValueAsDouble() == -0.125 && p.getString() == "-.125");
}

@("leadingDotInNegativeDecimalAllowedAsync")
unittest
{
    testLeadingDotInNegativeDecimalAllowed();
}

@("leadingDotInNegativeDecimalAllowedBytes")
unittest
{
    testLeadingDotInNegativeDecimalAllowed();
}

@("leadingDotInNegativeDecimalAllowedReader")
unittest
{
    testLeadingDotInNegativeDecimalAllowed();
}
