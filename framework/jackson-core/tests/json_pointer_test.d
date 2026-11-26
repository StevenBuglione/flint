/*
 * Ported from Jackson (jackson-core) 3.1.8, tag jackson-core-3.1.8:
 * src/test/java/tools/jackson/core/unittest/jsonptr/JsonPointerTest.java
 *
 * Jackson JSON-processor.
 * Copyright (c) 2007- Tatu Saloranta, tatu.saloranta@iki.fi
 * Licensed under the Apache License, Version 2.0.
 *
 * Modified by the Flint authors: translated JUnit assertions to D unittests.
 */
module json_pointer_test;

import flint.jackson.core : JsonPointer;

@safe:

@("simpleTail")
unittest
{
    auto pointer = JsonPointer.compile("/root/leaf");
    assert(pointer.tail().toString() == "/leaf");
    assert(pointer.tail().tail().toString() == "");
}

@("iZeroIndex")
unittest
{
    assert(JsonPointer.compile("/0").getMatchingIndex() == 0);
    assert(JsonPointer.compile("/00").getMatchingIndex() == -1);
}

@("emptyPointer")
unittest
{
    auto empty = JsonPointer.empty();
    assert(JsonPointer.compile("") is empty);
    assert(empty.toString() == "");
    assert(!empty.mayMatchProperty());
    assert(!empty.mayMatchElement());
    assert(empty.getMatchingIndex() == -1);
    assert(empty.getMatchingProperty() is null);
}

@("pointerWithEmptyPropertyName")
unittest
{
    auto pointer = JsonPointer.compile("/");
    assert(pointer !is null && pointer !is JsonPointer.empty());
    assert(pointer.toString() == "/");
    assert(pointer.mayMatchProperty());
    assert(!pointer.mayMatchElement());
    assert(pointer.getMatchingIndex() == -1);
    assert(pointer.getMatchingProperty() == "");
    assert(pointer.matchesProperty(""));
    assert(!pointer.matchesElement(0));
    assert(!pointer.matchesElement(-1));
    assert(!pointer.matchesProperty("1"));
}

@("decoded properties keep their original pointer spelling")
unittest
{
    auto pointer = JsonPointer.compile("/w~1out/til~0de/~1ab/a~2b");
    assert(pointer.getMatchingProperty() == "w/out");
    assert(pointer.toString() == "/w~1out/til~0de/~1ab/a~2b");
    pointer = pointer.matchProperty("w/out");
    assert(pointer.getMatchingProperty() == "til~de");
    assert(pointer.tail().getMatchingProperty() == "/ab");
    assert(pointer.tail().tail().getMatchingProperty() == "a~2b");
    assert(pointer.tail().tail().tail().matches());
    assert(JsonPointer.compile("/2147483647").matchesElement(int.max));
    assert(!JsonPointer.compile("/2147483648").mayMatchElement());
}

@("invalid pointer expressions have Jackson's diagnostic")
unittest
{
    try
        JsonPointer.compile("root");
    catch (Exception error)
    {
        assert(error.msg == "Invalid input: JSON Pointer expression must start with '/': \"root\"");
        return;
    }
    assert(false, "nonempty expression without slash unexpectedly compiled");
}
