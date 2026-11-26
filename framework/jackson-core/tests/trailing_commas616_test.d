/*
 * Ported from Jackson (jackson-core) 3.1.8, tag jackson-core-3.1.8:
 * src/test/java/tools/jackson/core/unittest/read/TrailingCommas616Test.java
 *
 * Jackson JSON-processor.
 * Copyright (c) 2007- Tatu Saloranta, tatu.saloranta@iki.fi
 * Licensed under the Apache License, Version 2.0.
 *
 * Modified by the Flint authors: translated JUnit assertions to D unittests; one byte parser serves every mode.
 */
module trailing_commas616_test;

import flint.jackson.core.json : JsonReadFeature;
import read_test_support : nextFails, parserWith;

@safe:

// [core#616]: ALLOW_MISSING_VALUES never makes a root-level comma a value.
private void testRootLevel616()
{
    auto p = parserWith(",", JsonReadFeature.ALLOW_MISSING_VALUES);
    nextFails(p, "Unexpected character (','");
    p.close();
}

@("rootLevelComma616")
unittest
{
    testRootLevel616();
}

@("rootLevelComma616Bytes")
unittest
{
    testRootLevel616();
}

@("rootLevelComma616DataInput")
unittest
{
    testRootLevel616();
}
