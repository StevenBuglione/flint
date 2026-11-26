/*
 * Ported from Jackson (jackson-core) 3.1.8, tag jackson-core-3.1.8:
 * src/test/java/tools/jackson/core/unittest/read/NonStandardJsonReadFeaturesTest.java
 *
 * Jackson JSON-processor.
 * Copyright (c) 2007- Tatu Saloranta, tatu.saloranta@iki.fi
 * Licensed under the Apache License, Version 2.0.
 *
 * Modified by the Flint authors: translated JUnit assertions to D unittests; one byte parser serves every mode.
 * The number methods (leadingZeroes, allowNaN, allowInfinity) arrive with the read features' number slice.
 */
module non_standard_json_read_features_test;

import flint.jackson.core : JsonToken;
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
