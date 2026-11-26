/*
 * Ported from Jackson (jackson-core) 3.1.8, tag jackson-core-3.1.8:
 * src/test/java/tools/jackson/core/unittest/read/NonStandardAllowRSTest.java
 *
 * Jackson JSON-processor.
 * Copyright (c) 2007- Tatu Saloranta, tatu.saloranta@iki.fi
 * Licensed under the Apache License, Version 2.0.
 *
 * Modified by the Flint authors: translated JUnit assertions to D unittests. Flint has one byte parser and no
 * non-blocking parser, so the string, reader, byte and async variants are one case.
 */
module non_standard_allow_rs_test;

import flint.jackson.core : JsonParser, JsonToken;
import flint.jackson.core.json : JsonFactory, JsonReadFeature;
import read_test_support : verifyException;

@safe:

// [core#633]: optionally allow the Record-Separator control character.
private void doRecordSeparationTest(bool recordSeparation)
{
    immutable contents = "{\"key\":true}\u001E";
    auto parser = JsonFactory.builder().configure(JsonReadFeature.ALLOW_RS_CONTROL_CHAR,
            recordSeparation).build().createParser(contents);
    try
    {
        assert(parser.nextToken() == JsonToken.START_OBJECT);
        assert(parser.nextName() == "key");
        assert(parser.nextToken() == JsonToken.VALUE_TRUE);
        assert(parser.nextToken() == JsonToken.END_OBJECT);
        parser.nextToken(); // RS token
        assert(recordSeparation, "Should have thrown an exception");
    }
    catch (Exception e)
    {
        assert(!recordSeparation, e.msg);
        verifyException(e, "Illegal character ((CTRL-CHAR");
        verifyException(e, "consider enabling `JsonReadFeature.ALLOW_RS_CONTROL_CHAR`");
    }
    parser.close();
}

@("recordSeparatorEnabled")
unittest
{
    doRecordSeparationTest(true);
}

@("recordSeparatorDisabled")
unittest
{
    doRecordSeparationTest(false);
}
