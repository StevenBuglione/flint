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

@("simplePath")
unittest
{
    auto pointer = JsonPointer.compile("/Image/15/name");
    assert(!pointer.matches());
    assert(pointer.getMatchingIndex() == -1);
    assert(pointer.getMatchingProperty() == "Image");
    assert(pointer.head().toString() == "/Image/15");
    assert(pointer.toString() == "/Image/15/name");

    pointer = pointer.tail();
    assert(pointer !is null && !pointer.matches());
    assert(pointer.getMatchingIndex() == 15);
    assert(pointer.getMatchingProperty() == "15");
    assert(pointer.toString() == "/15/name");
    assert(pointer.head().toString() == "/15");
    assert(pointer.head().head().toString() == "");
    assert(pointer.head().head().head() is null);

    pointer = pointer.tail();
    assert(pointer !is null && !pointer.matches());
    assert(pointer.getMatchingIndex() == -1);
    assert(pointer.getMatchingProperty() == "name");
    assert(pointer.toString() == "/name");
    assert(pointer.head().toString() == "");
    assert(pointer.head() is JsonPointer.empty());

    pointer = pointer.tail();
    assert(pointer.matches());
    assert(pointer.tail() is null);
    assert(pointer.head() is null);
    assert(pointer.getMatchingProperty() is null);
    assert(pointer.getMatchingIndex() == -1);
}

@("simplePathLonger")
unittest
{
    auto pointer = JsonPointer.compile("/a/b/c/d/e/f/0");
    assert(!pointer.matches());
    assert(pointer.getMatchingIndex() == -1);
    assert(pointer.getMatchingProperty() == "a");
    assert(pointer.head().toString() == "/a/b/c/d/e/f");
    assert(pointer.tail().toString() == "/b/c/d/e/f/0");
    assert(pointer.last().toString() == "/0");
    assert(pointer.toString() == "/a/b/c/d/e/f/0");
}

@("last")
unittest
{
    auto pointer = JsonPointer.compile("/Image/name");
    auto leaf = pointer.last();
    assert(leaf.toString() == "/name");
    assert(leaf.getMatchingProperty() == "name");

    pointer = JsonPointer.compile("/Image/15/name");
    leaf = pointer.last();
    assert(leaf.toString() == "/name");
    assert(leaf.getMatchingProperty() == "name");
}

@("equality")
unittest
{
    auto empty = JsonPointer.empty();
    assert(!empty.equals(JsonPointer.compile("/")));
    assert(JsonPointer.compile("/foo/3").equals(JsonPointer.compile("/foo/3")));
    assert(!empty.equals(JsonPointer.compile("/12")));
    assert(!JsonPointer.compile("/12").equals(empty));
    assert(JsonPointer.compile("/a/b/c").tail().equals(JsonPointer.compile("/foo/b/c").tail()));

    auto tail = JsonPointer.compile("/abc/def").tail();
    auto leaf = JsonPointer.compile("/def");
    assert(tail.equals(leaf) && leaf.equals(tail));
    assert(!empty.equals(new Object));

    auto unescaped = JsonPointer.compile("/~2");
    auto escaped = JsonPointer.compile("/~02");
    assert(unescaped.getMatchingProperty() == escaped.getMatchingProperty());
    assert(!unescaped.equals(escaped));
}

@("quotedPath")
unittest
{
    enum expression = "/w~1out/til~0de/~1ab";
    auto pointer = JsonPointer.compile(expression);
    assert(!pointer.matches());
    assert(pointer.getMatchingIndex() == -1);
    assert(pointer.getMatchingProperty() == "w/out");
    assert(pointer.head().toString() == "/w~1out/til~0de");
    assert(pointer.toString() == expression);

    pointer = pointer.tail();
    assert(pointer !is null && !pointer.matches());
    assert(pointer.getMatchingIndex() == -1);
    assert(pointer.getMatchingProperty() == "til~de");
    assert(pointer.head().toString() == "/til~0de");
    assert(pointer.toString() == "/til~0de/~1ab");

    pointer = pointer.tail();
    assert(pointer !is null && !pointer.matches());
    assert(pointer.getMatchingIndex() == -1);
    assert(pointer.getMatchingProperty() == "/ab");
    assert(pointer.toString() == "/~1ab");
    assert(pointer.head().toString() == "");

    pointer = pointer.tail();
    assert(pointer.matches());
    assert(pointer.tail() is null);
}

@("pointer lengths and hashes use Java UTF-16 units")
unittest
{
    auto pointer = JsonPointer.compile("/é/😀");
    auto tail = pointer.tail();
    auto equivalent = JsonPointer.compile("/😀");
    assert(pointer.length() == 5);
    assert(tail.length() == 3);
    assert(tail.hashCode() == 1_818_066);
    assert(pointer.hashCode() == 52_164_856);
    assert(equivalent == tail);
    assert(equivalent.toHash() == tail.toHash());
    assert(JsonPointer.empty().hashCode() == -1);
}

@("head and last preserve the original, decoded segments and stable identities")
unittest
{
    auto pointer = JsonPointer.compile("/w~1out/12/");
    auto head = pointer.head();
    assert(pointer.head() is head);
    assert(head.getMatchingProperty() == "w/out");
    assert(head.getMatchingProperty().ptr is pointer.getMatchingProperty().ptr);
    assert(head.tail().getMatchingIndex() == 12);
    assert(head.tail().tail() is JsonPointer.empty());
    assert(pointer.last() is pointer.tail().tail());
    assert(pointer.last().matchesProperty(""));
    assert(JsonPointer.empty().last() is null);
    assert(JsonPointer.compile("/").head() is JsonPointer.empty());
}

@("wonkyNumber173")
unittest
{
    assert(!JsonPointer.compile("/1e0").matches());
}

@("properties")
unittest
{
    auto name = JsonPointer.compile("/foo");
    assert(name.mayMatchProperty() && !name.mayMatchElement());
    auto indexed = JsonPointer.compile("/12");
    assert(indexed.mayMatchProperty() && indexed.mayMatchElement());
}

@("longNumbers")
unittest
{
    auto pointer = JsonPointer.compile("/User/2147483648");
    assert(pointer.getMatchingProperty() == "User");
    assert(pointer.toString() == "/User/2147483648");
    auto tail = pointer.tail();
    assert(tail !is null && !tail.matches());
    assert(tail.getMatchingIndex() == -1);
    assert(tail.getMatchingProperty() == "2147483648");
    assert(tail.tail().matches() && tail.tail().tail() is null);
}

@("append")
unittest
{
    auto pointer = JsonPointer.compile("/Image/15/name");
    auto suffix = JsonPointer.compile("/extension");
    auto appended = pointer.append(suffix);

    assert(appended.last().getMatchingProperty() == "extension");
    assert(appended.toString() == "/Image/15/name/extension");
}

@("appendWithFinalSlash")
unittest
{
    auto pointer = JsonPointer.compile("/Image/15/name/");
    assert(pointer.toString() == "/Image/15/name/");
    auto appended = pointer.append(JsonPointer.compile("/extension"));

    assert(appended.last().getMatchingProperty() == "extension");
    assert(appended.toString() == "/Image/15/name//extension");
}

@("appendProperty")
unittest
{
    auto pointer = JsonPointer.compile("/Image/15/name");
    auto plain = pointer.appendProperty("extension");
    auto escaped = pointer.appendProperty("/extension~");

    assert(plain.last().getMatchingProperty() == "extension");
    assert(plain.toString() == "/Image/15/name/extension");
    assert(escaped.last().getMatchingProperty() == "/extension~");
    assert(escaped.toString() == "/Image/15/name/~1extension~0");
}

@("appendPropertyEmpty")
unittest
{
    auto pointer = JsonPointer.compile("/Image/72/src");
    assert(pointer.appendProperty(null) is pointer);
    auto appended = pointer.appendProperty("");

    assert(appended !is pointer);
    assert(appended.toString() == "/Image/72/src/");
}

@("appendIndex")
unittest
{
    auto pointer = JsonPointer.compile("/Image/15/name");
    auto appended = pointer.appendIndex(12);

    assert(appended.last().getMatchingIndex() == 12);
}

@("append preserves identity for empty operands and rejects a null suffix on a nonempty pointer")
unittest
{
    import std.exception : assertThrown;

    auto empty = JsonPointer.empty();
    auto pointer = JsonPointer.compile("/a");
    assert(empty.append(pointer) is pointer);
    assert(pointer.append(empty) is pointer);
    assert(empty.append(null) is null);
    assertThrown!Exception(pointer.append(null)); // D-JACKSON-8
}

@("appendIndex keeps a trailing empty segment and rejects a negative index")
unittest
{
    auto pointer = JsonPointer.compile("/a/");
    auto appended = pointer.appendIndex(int.max);
    assert(appended.toString() == "/a//2147483647");
    assert(appended.last().getMatchingIndex() == int.max);

    try
        pointer.appendIndex(-1);
    catch (Exception error) // D-JACKSON-8
    {
        assert(error.msg == "Negative index cannot be appended");
        return;
    }
    assert(false, "negative index unexpectedly appended");
}
