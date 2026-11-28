// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
/** Original specification tests for the Java character-array writer. */
module flint.java.io.char_array_writer_contract_test;

import flint.java.io : CharArrayWriter, StringWriter, Writer;
import flint.java.lang : IllegalArgumentException, IndexOutOfBoundsException, NullPointerException;

import std.exception : assertThrown;

@safe:

@("CharArrayWriter starts empty with Java's default capacity")
unittest
{
    auto writer = new CharArrayWriter;
    assert(writer.size() == 0);
    assert(writer.toCharArray().length == 0);
    assert(writer.toString() == "");
}

@("CharArrayWriter rejects a negative initial size and accepts zero")
unittest
{
    assertThrown!IllegalArgumentException(new CharArrayWriter(-1));
    auto writer = new CharArrayWriter(0);
    writer.write("a");
    assert(writer.toString() == "a" && writer.size() == 1);
}

@("CharArrayWriter grows past a small initial capacity")
unittest
{
    auto writer = new CharArrayWriter(1);
    writer.write("abcdef");
    assert(writer.toString() == "abcdef");
    assert(writer.size() == 6);
    assert(writer.toCharArray() == "abcdef"w);
}

@("CharArrayWriter writes UTF-16 code units and preserves a supplementary pair")
unittest
{
    auto writer = new CharArrayWriter;
    writer.write("A😀");
    assert(writer.size() == 3);
    assert(writer.toString() == "A😀");
    assert(writer.toCharArray() == "A😀"w);
}

@("CharArrayWriter writes a String and char-array range by Java's UTF-16 offsets")
unittest
{
    auto writer = new CharArrayWriter;
    writer.write("hello", 1, 3);
    assert(writer.toString() == "ell");
    writer.reset();
    writer.write("abcde"w, 2, 2);
    assert(writer.toString() == "cd");
}

@("CharArrayWriter rejects an out-of-range char-array write")
unittest
{
    auto writer = new CharArrayWriter;
    assertThrown!IndexOutOfBoundsException(writer.write("abc"w, 2, 2));
}

@("CharArrayWriter append returns the writer and writes one code unit")
unittest
{
    auto writer = new CharArrayWriter;
    assert(writer.append(cast(wchar) 'é') is writer);
    assert(writer.append(cast(wchar) 'Ω') is writer);
    assert(writer.toString() == "éΩ");
}

@("CharArrayWriter writeTo copies the text without clearing the writer")
unittest
{
    auto writer = new CharArrayWriter;
    writer.write("A😀");
    auto sink = new StringWriter;
    writer.writeTo(sink);
    assert(sink.toString() == "A😀");
    assert(writer.toString() == "A😀");
    assertThrown!NullPointerException(writer.writeTo(cast(Writer) null));
}

@("CharArrayWriter reset keeps the buffer and toCharArray returns a copy")
unittest
{
    auto writer = new CharArrayWriter;
    writer.write("abc");
    auto copy = writer.toCharArray();
    copy[0] = cast(wchar) 'z';
    assert(writer.toString() == "abc");

    writer.reset();
    assert(writer.size() == 0 && writer.toString() == "");
    writer.write("new");
    assert(writer.toString() == "new");
}

@("CharArrayWriter flush and close do nothing and leave the writer usable")
unittest
{
    auto writer = new CharArrayWriter;
    writer.write("a");
    writer.flush();
    writer.close();
    writer.write("b");
    assert(writer.toString() == "ab");
}
