/*
 * Ported from Jackson (jackson-core) 3.1.8, tag jackson-core-3.1.8:
 * src/test/java/tools/jackson/core/unittest/read/AposUnescapedControlChars1750Test.java
 *
 * Jackson JSON-processor.
 * Copyright (c) 2007- Tatu Saloranta, tatu.saloranta@iki.fi
 * Licensed under the Apache License, Version 2.0.
 *
 * Modified by the Flint authors: translated JUnit assertions to D unittests; one byte parser serves every mode, so
 * linefeedsUpdateRow expects row 2 throughout (Jackson's DataInput mode alone counts CR LF as two rows).
 * controlCharsStreamedToWriter needs JsonParser.readString(Writer), which jackson-core does not have yet.
 */
module apos_unescaped_control_chars1750_test;

import flint.jackson.core : JsonParser, JsonToken;
import flint.jackson.core.json : JsonReadFeature;
import read_test_support : parserWith, verifyException;

@safe:

private enum APOS = JsonReadFeature.ALLOW_SINGLE_QUOTES;
private enum CTRL = JsonReadFeature.ALLOW_UNESCAPED_CONTROL_CHARS;

private string longValue()
{
    string text;
    foreach (i; 0 .. 6000)
    {
        switch (i % 7)
        {
        case 0:
            text ~= '\t';
            break;
        case 3:
            text ~= "é";
            break;
        default:
            text ~= cast(char)('a' + (i % 26));
        }
    }
    return text;
}

private string[] values()
{
    return ["a\tb", "\t", "a\u0001b", "x\ny\rz", "é\t中", "\t\U0001F600\t", longValue()];
}

@("controlCharsInAposValueAllowed")
unittest
{
    foreach (value; values())
    {
        auto p = parserWith("['" ~ value ~ "']", APOS, CTRL);
        assert(p.nextToken() == JsonToken.START_ARRAY);
        assert(p.nextToken() == JsonToken.VALUE_STRING && p.getString() == value);
        assert(p.nextToken() == JsonToken.END_ARRAY);
        p = parserWith("{'a':'" ~ value ~ "'}", APOS, CTRL);
        assert(p.nextToken() == JsonToken.START_OBJECT);
        assert(p.nextToken() == JsonToken.PROPERTY_NAME);
        assert(p.nextToken() == JsonToken.VALUE_STRING && p.getString() == value);
        assert(p.nextToken() == JsonToken.END_OBJECT);
        p = parserWith("['" ~ value ~ "',true]", APOS, CTRL);
        assert(p.nextToken() == JsonToken.START_ARRAY);
        assert(p.nextToken() == JsonToken.VALUE_STRING);
        assert(p.nextToken() == JsonToken.VALUE_TRUE);
        assert(p.nextToken() == JsonToken.END_ARRAY);
    }
}

@("controlCharsInAposNameAllowed")
unittest
{
    foreach (name; ["a\tb", "\t", "x\ny"])
    {
        auto p = parserWith("{'" ~ name ~ "':1}", APOS, CTRL);
        assert(p.nextToken() == JsonToken.START_OBJECT);
        assert(p.nextToken() == JsonToken.PROPERTY_NAME && p.currentName() == name);
        assert(p.nextToken() == JsonToken.VALUE_NUMBER_INT);
        assert(p.nextToken() == JsonToken.END_OBJECT);
    }
}

@("controlCharsInAposDisallowed")
unittest
{
    foreach (doc; ["['a\tb']", "{'a':'a\tb'}", "['" ~ longValue() ~ "']"])
    {
        auto p = parserWith(doc, APOS);
        try
        {
            p.nextToken();
            p.nextToken();
            p.nextToken();
            p.getString();
            assert(false, "Should not pass");
        }
        catch (Exception e)
        {
            verifyException(e, "Illegal unquoted character");
            verifyException(e, "string value");
        }
    }
    auto p = parserWith("{'a\tb':1}", APOS);
    try
    {
        p.nextToken();
        p.nextToken();
        assert(false, "Should not pass");
    }
    catch (Exception e)
    {
        verifyException(e, "Illegal unquoted character");
        verifyException(e, "name");
    }
}

@("linefeedsUpdateRow")
unittest
{
    foreach (lf; ["\n", "\r", "\r\n"])
        foreach (q; ['\'', '"'])
        {
            immutable doc = "[" ~ q ~ "x" ~ lf ~ "y" ~ q ~ ", 1]";
            foreach (getText; [true, false])
            {
                auto p = parserWith(doc, APOS, CTRL);
                assert(p.nextToken() == JsonToken.START_ARRAY);
                assert(p.nextToken() == JsonToken.VALUE_STRING);
                if (getText)
                    assert(p.getString() == "x" ~ lf ~ "y");
                assert(p.nextToken() == JsonToken.VALUE_NUMBER_INT);
                assert(p.currentTokenLocation().getLineNr() == 2, doc);
            }
        }
}
