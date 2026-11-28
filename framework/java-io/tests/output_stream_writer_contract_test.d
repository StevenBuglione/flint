// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
/** Original specification tests for writing UTF-8 text to a Java byte stream. */
module flint.java.io.output_stream_writer_contract_test;

import flint.java.io : IOException, OutputStream, OutputStreamWriter, Writer;

import std.exception : assertThrown;

import flint.java.lang : NullPointerException;
import flint.java.nio.charset : Charset, IllegalCharsetNameException, StandardCharsets,
    UnsupportedCharsetException;

@safe:

private ubyte[] be16(scope const(char)[] text)
{
    ubyte[] bytes;
    foreach (dchar c; text)
    {
        bytes ~= cast(ubyte)(c >> 8);
        bytes ~= cast(ubyte)(c & 0xFF);
    }
    return bytes;
}

private ubyte[] le16(scope const(char)[] text)
{
    ubyte[] bytes;
    foreach (dchar c; text)
    {
        bytes ~= cast(ubyte)(c & 0xFF);
        bytes ~= cast(ubyte)(c >> 8);
    }
    return bytes;
}

@("OutputStreamWriter rejects a null output stream")
unittest
{
    assertThrown!NullPointerException(new OutputStreamWriter(cast(OutputStream) null));
}

private final class RecordingOutput : OutputStream
{
    ubyte[] bytes;
    int flushes;
    int closes;

    override void write(int value)
    {
        bytes ~= cast(ubyte) value;
    }

    override void write(scope const(ubyte)[] data)
    {
        bytes ~= data;
    }

    override void flush()
    {
        ++flushes;
    }

    override void close()
    {
        ++closes;
    }
}

private final class FailingFlushOutput : OutputStream
{
    bool flushed;
    bool closed;

    override void write(int value)
    {
    }

    override void flush()
    {
        flushed = true;
        throw new IOException("flush failed");
    }

    override void close()
    {
        closed = true;
    }
}

@("OutputStreamWriter writes UTF-8 for an OutputStream and forwards lifecycle calls")
unittest
{
    auto output = new RecordingOutput;
    Writer writer = new OutputStreamWriter(output);

    writer.write("é😀");
    writer.flush();
    assert(output.bytes == cast(const(ubyte)[]) "é😀");
    assert(output.flushes == 1);

    writer.write("!");
    writer.close();
    assert(output.bytes == cast(const(ubyte)[]) "é😀!");
    assert(output.flushes == 2);
    assert(output.closes == 1);
}

@("OutputStreamWriter flushes before closing once and rejects use after close")
unittest
{
    auto output = new RecordingOutput;
    auto writer = new OutputStreamWriter(output);

    writer.write("x");
    writer.close();
    assert(output.flushes == 1);
    assert(output.closes == 1);

    writer.close();
    assert(output.flushes == 1);
    assert(output.closes == 1);

    assertThrown!IOException(writer.write("y"));
    assertThrown!IOException(writer.flush());
    assert(output.flushes == 1);
    assert(output.closes == 1);
}

@("OutputStreamWriter closes the stream even when its final flush fails")
unittest
{
    auto output = new FailingFlushOutput;
    auto writer = new OutputStreamWriter(output);

    assertThrown!IOException(writer.close());
    assert(output.flushed);
    assert(output.closed);

    writer.close();
    assert(output.closed);
}

@("OutputStreamWriter encodes UTF-16 ranges and character arrays as UTF-8")
unittest
{
    auto output = new RecordingOutput;
    Writer writer = new OutputStreamWriter(output);

    writer.write("é😀!", 1, 2); // the emoji by UTF-16 units, not bytes
    assert(output.bytes == cast(const(ubyte)[]) "😀");
    output.bytes = null;

    writer.write("é😀!", 2, 1); // the low surrogate alone
    assert(output.bytes == cast(const(ubyte)[]) "\uFFFD");
    output.bytes = null;

    writer.write([cast(wchar) 'x', cast(wchar) 0xD83D, cast(wchar) 0xDE00]);
    assert(output.bytes == cast(const(ubyte)[]) "x😀");
}

@("OutputStreamWriter accepts an explicit charset and names it through getEncoding")
unittest
{
    auto output = new RecordingOutput;
    auto writer = new OutputStreamWriter(output, StandardCharsets.UTF_8);
    writer.write("é😀");
    assert(output.bytes == cast(const(ubyte)[]) "é😀");
    assert(writer.getEncoding() == "UTF-8");

    auto named = new OutputStreamWriter(new RecordingOutput, "UTF-8");
    assert(named.getEncoding() == "UTF-8");
    auto aliased = new OutputStreamWriter(new RecordingOutput, "UTF8");
    assert(aliased.getEncoding() == "UTF8"); // the name the caller used, as Java's historical name
}

@("OutputStreamWriter rejects an absent charset and unknown or empty charset names")
unittest
{
    assertThrown!NullPointerException(new OutputStreamWriter(new RecordingOutput, Charset.init));
    assertThrown!UnsupportedCharsetException(new OutputStreamWriter(new RecordingOutput, "NO-SUCH-CHARSET"));
    assertThrown!IllegalCharsetNameException(new OutputStreamWriter(new RecordingOutput, ""));
}

@("OutputStreamWriter maps unmappable characters to '?' for ASCII and ISO-8859-1")
unittest
{
    auto asciiOutput = new RecordingOutput;
    auto ascii = new OutputStreamWriter(asciiOutput, StandardCharsets.US_ASCII);
    ascii.write("Aé😀");
    assert(asciiOutput.bytes == [cast(ubyte) 'A', cast(ubyte) '?', cast(ubyte) '?']);
    assert(ascii.getEncoding() == "US-ASCII");

    auto latinOutput = new RecordingOutput;
    auto latin = new OutputStreamWriter(latinOutput, StandardCharsets.ISO_8859_1);
    latin.write("Aé😀");
    assert(latinOutput.bytes == [cast(ubyte) 'A', cast(ubyte) 0xE9, cast(ubyte) '?']);
    assert(latin.getEncoding() == "ISO-8859-1");
}

@("OutputStreamWriter writes UTF-16LE and UTF-16BE without a byte-order mark")
unittest
{
    auto littleOutput = new RecordingOutput;
    auto little = new OutputStreamWriter(littleOutput, StandardCharsets.UTF_16LE);
    little.write("Aé😀");
    assert(littleOutput.bytes == le16("Aé") ~ cast(ubyte[]) [0x3D, 0xD8, 0x00, 0xDE]);
    assert(little.getEncoding() == "UTF-16LE");

    auto bigOutput = new RecordingOutput;
    auto big = new OutputStreamWriter(bigOutput, StandardCharsets.UTF_16BE);
    big.write("Aé😀");
    assert(bigOutput.bytes == be16("Aé") ~ cast(ubyte[]) [0xD8, 0x3D, 0xDE, 0x00]);
    assert(big.getEncoding() == "UTF-16BE");
}

@("OutputStreamWriter writes the UTF-16 byte-order mark once before the first text")
unittest
{
    auto output = new RecordingOutput;
    auto writer = new OutputStreamWriter(output, StandardCharsets.UTF_16);
    writer.write("");
    assert(output.bytes.length == 0); // an empty write emits neither text nor a mark
    writer.write("A");
    writer.write("é");
    assert(output.bytes == cast(ubyte[]) [0xFE, 0xFF] ~ be16("Aé"));
    assert(writer.getEncoding() == "UTF-16");
}

@("OutputStreamWriter writes a lone surrogate as the charset's replacement, as U+FFFD")
unittest
{
    auto output = new RecordingOutput;
    auto writer = new OutputStreamWriter(output, StandardCharsets.US_ASCII);
    writer.write([cast(wchar) 0xD83D]);
    assert(output.bytes == [cast(ubyte) '?']); // U+FFFD is not representable in ASCII
}
