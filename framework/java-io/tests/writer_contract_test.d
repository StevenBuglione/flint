// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
/** Original specification tests for the existing Java character sink. */
module flint.java.io.writer_contract_test;

import flint.java.io : Writer;

import std.exception : assertThrown;

import flint.java.lang : IndexOutOfBoundsException;

@safe:

private final class TextSink : Writer
{
    string text;

    override void write(scope const(char)[] value)
    {
        text ~= value;
    }

    override void flush()
    {
    }

    override void close()
    {
    }
}

@("Writer append forwards text and returns the same writer")
unittest
{
    auto sink = new TextSink;
    Writer writer = sink;

    assert(writer.append("é😀") is writer);
    assert(writer.append("") is writer);
    writer.write("!");
    assert(sink.text == "é😀!");
}

@("Writer.append(char) writes one UTF-16 code unit through write(int)")
unittest
{
    auto sink = new TextSink;
    Writer writer = sink;

    assert(writer.append(cast(wchar) 'a') is writer);
    assert(sink.text == "a");

    writer.append(cast(wchar) 0xD83D); // a lone high surrogate
    assert(sink.text == "a\uFFFD");

    writer.append(cast(wchar) 0xDE00); // a lone low surrogate
    assert(sink.text == "a\uFFFD\uFFFD");
}

@("Writer.write(String,int,int) counts UTF-16 units over UTF-8 text")
unittest
{
    // "a😀b": a is unit 0, the emoji is the surrogate pair at units 1 and 2, b is unit 3.
    static immutable string text = "a😀b";
    auto sink = new TextSink;
    Writer writer = sink;

    writer.write(text, 0, 1);
    assert(sink.text == "a");
    sink.text = null;

    writer.write(text, 3, 1);
    assert(sink.text == "b");
    sink.text = null;

    writer.write(text, 1, 2); // the whole supplementary character
    assert(sink.text == "😀");
    sink.text = null;

    writer.write(text, 0, 4);
    assert(sink.text == text);
    sink.text = null;

    writer.write(text, 1, 3); // the emoji and b
    assert(sink.text == "😀b");
    sink.text = null;

    writer.write(text, 0, 0);
    assert(sink.text == "");
}

@("Writer.write(String,int,int) writes U+FFFD for a split surrogate pair")
unittest
{
    static immutable string text = "a😀b";
    auto sink = new TextSink;
    Writer writer = sink;

    writer.write(text, 1, 1); // the high surrogate alone
    assert(sink.text == "\uFFFD");
    sink.text = null;

    writer.write(text, 2, 1); // the low surrogate alone
    assert(sink.text == "\uFFFD");
    sink.text = null;

    writer.write(text, 2, 2); // the low surrogate and b
    assert(sink.text == "\uFFFDb");
    sink.text = null;

    writer.write(text, 0, 2); // a and the high surrogate
    assert(sink.text == "a\uFFFD");
}

@("Writer.write(String,int,int) rejects a range outside the text")
unittest
{
    static immutable string text = "a😀b";
    auto sink = new TextSink;
    Writer writer = sink;

    assertThrown!IndexOutOfBoundsException(writer.write(text, 4, 1)); // four UTF-16 units, not bytes
    assertThrown!IndexOutOfBoundsException(writer.write(text, -1, 1));
    assertThrown!IndexOutOfBoundsException(writer.write(text, 0, -1));
    assertThrown!IndexOutOfBoundsException(writer.write(text, 0, 5));
}

@("Writer.write(char[]) transcodes UTF-16, pairing surrogates and replacing lone halves")
unittest
{
    auto sink = new TextSink;
    Writer writer = sink;

    writer.write([cast(wchar) 'a', cast(wchar) 'é', cast(wchar) 'b']);
    assert(sink.text == "aéb");
    sink.text = null;

    writer.write([cast(wchar) 0xD83D, cast(wchar) 0xDE00]); // 😀 as a surrogate pair
    assert(sink.text == "😀");
    sink.text = null;

    writer.write([cast(wchar) 0xD83D]); // lone high surrogate
    assert(sink.text == "\uFFFD");
    sink.text = null;

    writer.write([cast(wchar) 0xDE00]); // lone low surrogate
    assert(sink.text == "\uFFFD");
    sink.text = null;

    writer.write([cast(wchar) 0xD83D, cast(wchar) 'a']); // an unpaired high surrogate before a BMP character
    assert(sink.text == "\uFFFD" ~ "a");
    sink.text = null;

    writer.write(cast(const(wchar)[]) null); // R26: a null array is empty
    assert(sink.text == "");
}

@("Writer.write(char[],int,int) selects wchar units and checks the bounds")
unittest
{
    static immutable wchar[] units = [
        cast(wchar) 'a', cast(wchar) 0xD83D, cast(wchar) 0xDE00, cast(wchar) 'b'
    ];
    auto sink = new TextSink;
    Writer writer = sink;

    writer.write(units, 1, 2); // the whole surrogate pair
    assert(sink.text == "😀");
    sink.text = null;

    writer.write(units, 0, 2); // a and the high surrogate alone
    assert(sink.text == "a\uFFFD");
    sink.text = null;

    writer.write(units, 2, 2); // the low surrogate alone and b
    assert(sink.text == "\uFFFDb");
    sink.text = null;

    writer.write(units, 1, 0);
    assert(sink.text == "");
    sink.text = null;

    assertThrown!IndexOutOfBoundsException(writer.write(units, 0, 5));
    assertThrown!IndexOutOfBoundsException(writer.write(units, -1, 1));
    assertThrown!IndexOutOfBoundsException(writer.write(units, 0, -1));
}

@("Writer.write(dchar) writes one code point and U+FFFD for a surrogate")
unittest
{
    auto sink = new TextSink;
    Writer writer = sink;

    writer.write(cast(dchar) 'é');
    assert(sink.text == "é");
    sink.text = null;

    writer.write(cast(dchar) 0x1F600);
    assert(sink.text == "😀");
    sink.text = null;

    writer.write(cast(dchar) 0xD83D);
    assert(sink.text == "\uFFFD");
}
