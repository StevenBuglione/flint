// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
// Original Flint tests of the array loops' leading single-byte run (decodeSingleByteRun, encodeSingleByteRun): the
// run honours arrayOffset, position and limit, stops at the unit the buffer loop must see, and leaves results equal
// to the buffer loop's on sources without an accessible array.
module single_byte_run_test;

import flint.java.nio.bytebuffer : ByteBuffer;
import flint.java.nio.charbuffer : CharBuffer;
import flint.java.nio.charset : Charset, StandardCharsets;
import flint.java.nio.charset.coderresult : CoderResult;
import flint.java.nio.charset.internal.decoders : standardDecoder;
import flint.java.nio.charset.internal.encoders : standardEncoder;

@safe:

// `content` behind `lead` filler bytes, sliced so that its array offset is `lead.length`.
private ByteBuffer offsetBytes(const(ubyte)[] lead, const(ubyte)[] content)
{
    auto all = cast(byte[])(lead ~ content).dup;
    auto bb = ByteBuffer.wrap(all);
    bb.position(cast(int) lead.length);
    auto s = bb.slice();
    assert(s.arrayOffset() == lead.length);
    return s;
}

private CharBuffer offsetChars(int lead, const(wchar)[] content)
{
    auto all = new wchar[lead] ~ content.dup;
    all[0 .. lead] = 'x';
    auto cb = CharBuffer.wrap(all);
    cb.position(lead);
    auto s = cb.slice();
    assert(s.arrayOffset() == lead);
    return s;
}

// An output buffer of `capacity` whose array offset is 3 and position 1.
private CharBuffer charOut(int capacity)
{
    auto cb = CharBuffer.allocate(capacity + 4);
    cb.position(3);
    auto s = cb.slice();
    s.position(1);
    return s;
}

private ByteBuffer byteOut(int capacity)
{
    auto bb = ByteBuffer.allocate(capacity + 4);
    bb.position(3);
    auto s = bb.slice();
    s.position(1);
    return s;
}

private wchar[] written(CharBuffer cb)
{
    return cb.array()[cb.arrayOffset() + 1 .. cb.arrayOffset() + cb.position()].dup;
}

private byte[] written(ByteBuffer bb)
{
    return bb.array()[bb.arrayOffset() + 1 .. bb.arrayOffset() + bb.position()].dup;
}

@("SingleByteRun.utf8DecodeContinuesAfterRun")
unittest
{
    auto src = offsetBytes([0xC3, 0xA9], ['h', 'i', 0xC3, 0xA9, '!']);
    auto dst = charOut(8);
    const cr = standardDecoder(StandardCharsets.UTF_8).decode(src, dst, true);
    assert(cr.isUnderflow());
    assert(src.position() == 5);
    assert(written(dst) == "hi\u00E9!"w);
}

@("SingleByteRun.asciiDecodeStopsAtNonAscii")
unittest
{
    auto src = offsetBytes(['z'], ['a', 'b', 0x80, 'c']);
    auto dst = charOut(8);
    const cr = standardDecoder(StandardCharsets.US_ASCII).decode(src, dst, true);
    assert(cr.isMalformed() && cr.length() == 1);
    assert(src.position() == 2);
    assert(written(dst) == "ab"w);
}

@("SingleByteRun.asciiDecodeFullOutputBeforeBadByte")
unittest
{
    // Java's array loop reports OVERFLOW before it looks at the next byte.
    auto src = offsetBytes(['z'], ['a', 'b', 0x80]);
    auto dst = charOut(2);
    const cr = standardDecoder(StandardCharsets.US_ASCII).decode(src, dst, true);
    assert(cr.isOverflow());
    assert(src.position() == 2);
}

@("SingleByteRun.latin1DecodeLimitedByOutput")
unittest
{
    auto src = offsetBytes([1, 2, 3], [0xE9, 'a', 0xFF, 'b']);
    auto dst = charOut(2);
    const cr = standardDecoder(StandardCharsets.ISO_8859_1).decode(src, dst, true);
    assert(cr.isOverflow());
    assert(src.position() == 2);
    assert(written(dst) == "\u00E9a"w);
}

@("SingleByteRun.singleByteEncodersStopAtUnmappable")
unittest
{
    auto src = offsetChars(2, "ab\u00E9"w);
    auto dst = byteOut(8);
    auto cr = standardEncoder(StandardCharsets.US_ASCII).encode(src, dst, true);
    assert(cr.isUnmappable() && cr.length() == 1);
    assert(src.position() == 2);
    assert(written(dst) == cast(const(byte)[]) "ab");

    src = offsetChars(1, "a\u00E9\u0100"w);
    dst = byteOut(8);
    cr = standardEncoder(StandardCharsets.ISO_8859_1).encode(src, dst, true);
    assert(cr.isUnmappable() && cr.length() == 1);
    assert(src.position() == 2);
    assert(written(dst) == [cast(byte) 'a', cast(byte) 0xE9]);
}

@("SingleByteRun.utf8EncodeOverflowAfterRun")
unittest
{
    auto src = offsetChars(3, "abc\u00E9"w);
    auto dst = byteOut(4);
    const cr = standardEncoder(StandardCharsets.UTF_8).encode(src, dst, true);
    assert(cr.isOverflow());
    assert(src.position() == 3);
    assert(written(dst) == cast(const(byte)[]) "abc");
}

@("SingleByteRun.readOnlySourceAgrees")
unittest
{
    // With ample output the array path and the buffer path (read-only source) give the same result, positions and
    // output on mixed inputs.
    static immutable Charset[3] charsets = [
        StandardCharsets.US_ASCII, StandardCharsets.ISO_8859_1, StandardCharsets.UTF_8
    ];
    static immutable ubyte[8] pool = ['a', 'Z', 0x7F, 0x80, 0xC3, 0xA9, 0xE2, 0xFF];
    static immutable wchar[7] charPool = ['a', 'Z', 0x7F, 0x80, 0xE9, 0x100, 0xD800];
    uint seed = 12_345;
    uint next()
    {
        seed = seed * 1_103_515_245 + 12_345;
        return seed >> 16;
    }

    foreach (round; 0 .. 300)
    {
        const cs = charsets[round % 3];
        ubyte[] input;
        wchar[] chars;
        foreach (i; 0 .. next() % 24)
        {
            input ~= next() % 4 == 0 ? pool[next() % pool.length] : cast(ubyte)('a' + next() % 26);
            chars ~= next() % 4 == 0 ? charPool[next() % charPool.length] : cast(wchar)('a' + next() % 26);
        }

        auto viaArray = offsetBytes([9, 9], input);
        auto viaBuffer = ByteBuffer.wrap(cast(byte[]) input.dup).asReadOnlyBuffer();
        auto outArray = charOut(64);
        auto outBuffer = charOut(64);
        const a = standardDecoder(cs).decode(viaArray, outArray, true);
        const b = standardDecoder(cs).decode(viaBuffer, outBuffer, true);
        assert(a.toString() == b.toString() && viaArray.position() == viaBuffer.position());
        assert(written(outArray) == written(outBuffer));

        auto charsArray = offsetChars(2, chars);
        auto charsBuffer = CharBuffer.wrap(chars.dup).asReadOnlyBuffer();
        auto bytesArray = byteOut(96);
        auto bytesBuffer = byteOut(96);
        const c = standardEncoder(cs).encode(charsArray, bytesArray, true);
        const d = standardEncoder(cs).encode(charsBuffer, bytesBuffer, true);
        assert(c.toString() == d.toString() && charsArray.position() == charsBuffer.position());
        assert(written(bytesArray) == written(bytesBuffer));
    }
}
