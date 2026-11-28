// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
// Original Flint tests covering the upstream CharsetDecoder/EmptyInput and CharsetDecoder/XcodeOverflow classes,
// which the pinned jtreg source keeps plain GPL. They exercise the convenience decode(ByteBuffer) and
// encode(CharBuffer) methods and the capacity estimate/growth boundary that guards Java's int overflow.
module flint.java.nio.charset.internal.convenience_coders_test;

import flint.java.nio.bufferunderflowexception : BufferUnderflowException;
import flint.java.nio.bytebuffer : ByteBuffer;
import flint.java.nio.charbuffer : CharBuffer;
import flint.java.nio.charset : Charset, StandardCharsets;
import flint.java.nio.charset.coderresult : CoderResult;
import flint.java.nio.charset.internal.coders : estimateCapacity, grownCapacity, softMaxArrayLength;
import flint.java.nio.charset.internal.decoders : standardDecoder;
import flint.java.nio.charset.internal.encoders : standardEncoder;
import flint.java.nio.charset.malformedinputexception : MalformedInputException;
import flint.java.nio.charset.unmappablecharacterexception : UnmappableCharacterException;
import std.exception : collectException;

@safe:

private byte[] readAll(ByteBuffer buffer) pure
{
    byte[] bytes;
    while (buffer.hasRemaining())
        bytes ~= buffer.get();
    return bytes;
}

@("EmptyInput: an empty buffer decodes to UNDERFLOW, which throwException turns into BufferUnderflowException")
unittest
{
    foreach (cs; [StandardCharsets.US_ASCII, StandardCharsets.ISO_8859_1, StandardCharsets.UTF_8])
    {
        auto bb = ByteBuffer.allocate(10);
        bb.flip();
        auto underflow = collectException!BufferUnderflowException(standardDecoder(cs).decode(bb,
                CharBuffer.allocate(10), true).throwException());
        assert(underflow !is null);
    }
}

@("convenience decode(ByteBuffer) returns an empty buffer for empty input")
unittest
{
    foreach (cs; [StandardCharsets.US_ASCII, StandardCharsets.UTF_8])
    {
        auto bb = ByteBuffer.allocate(0);
        auto decoded = standardDecoder(cs).decode(bb);
        assert(decoded.remaining() == 0 && decoded.toString() == "");
    }
}

@("convenience decode(ByteBuffer) and encode(CharBuffer) round-trip ASCII text")
unittest
{
    auto text = "hello, world";
    auto decoded = standardDecoder(StandardCharsets.US_ASCII).decode(ByteBuffer.wrap(cast(byte[]) text.dup));
    assert(decoded.toString() == text);

    auto encoded = standardEncoder(StandardCharsets.US_ASCII).encode(CharBuffer.wrap(text));
    assert(readAll(encoded) == cast(byte[]) text.dup);
}

@("convenience decode(ByteBuffer) throws MalformedInputException for a malformed UTF-8 byte")
unittest
{
    auto bb = ByteBuffer.wrap([cast(byte) 0xFF]);
    auto malformed = collectException!MalformedInputException(standardDecoder(StandardCharsets.UTF_8).decode(bb));
    assert(malformed !is null && malformed.getInputLength() == 1);
    assert(malformed.getMessage() == "Input length = 1");
}

@("convenience encode(CharBuffer) throws UnmappableCharacterException for a non-ASCII character")
unittest
{
    auto unmappable = collectException!UnmappableCharacterException(
            standardEncoder(StandardCharsets.US_ASCII).encode(CharBuffer.wrap("\u00E9")));
    assert(unmappable !is null && unmappable.getInputLength() == 1);
    assert(unmappable.getMessage() == "Input length = 1");
}

@("XcodeOverflow: the capacity estimate saturates instead of overflowing to a negative size")
unittest
{
    foreach (remaining; [int.max, int.max - 1_000_000, int.max / 2 + 1])
        foreach (average; [1.0f, 2.0f, 4.0f])
        {
            const n = estimateCapacity(remaining, average);
            assert(n >= 0 && n <= softMaxArrayLength);
        }
    assert(estimateCapacity(int.max, 1.0f) == softMaxArrayLength);
    assert(estimateCapacity(int.max / 2 + 1, 4.0f) == softMaxArrayLength);
    assert(estimateCapacity(0, 4.0f) == 0);
}

@("XcodeOverflow: the growth keeps a positive size at the int boundary")
unittest
{
    assert(grownCapacity(0) == 1);
    assert(grownCapacity(1) == 3);
    assert(grownCapacity(1023) == 2047);
    assert(grownCapacity(softMaxArrayLength / 2 + 1) == softMaxArrayLength);
    foreach (n; [softMaxArrayLength, int.max])
    {
        const grown = grownCapacity(n);
        assert(grown > 0 && grown >= n);
    }
}
