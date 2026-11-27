/*
 * Copyright (c) 2000, 2023, Oracle and/or its affiliates. All rights reserved.
 * DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS FILE HEADER.
 *
 * This code is free software; you can redistribute it and/or modify it
 * under the terms of the GNU General Public License version 2 only, as
 * published by the Free Software Foundation.  Oracle designates this
 * particular file as subject to the "Classpath" exception as provided
 * by Oracle in the LICENSE file that accompanied this code.
 *
 * This code is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
 * FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
 * version 2 for more details (a copy is included in the LICENSE file that
 * accompanied this code).
 *
 * You should have received a copy of the GNU General Public License version
 * 2 along with this work; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin St, Fifth Floor, Boston, MA 02110-1301 USA.
 *
 * Please contact Oracle, 500 Oracle Parkway, Redwood Shores, CA 94065 USA
 * or visit www.oracle.com if you need additional information or have any
 * questions.
 */

/*
 * Ported from openjdk 21.0.13: the decoders of src/java.base/share/classes/sun/nio/cs/US_ASCII.java,
 * ISO_8859_1.java and UTF_8.java (Copyright (c) 2000, 2021), UnicodeDecoder.java (Copyright (c) 2000, 2019), and
 * UTF_16.java, UTF_16BE.java and UTF_16LE.java (Copyright (c) 2000, 2005); and the default isLegalReplacement of
 * src/java.base/share/classes/java/nio/charset/Charset-X-Coder.java.template (Copyright (c) 2000, 2023).
 * The buffer loops are ported; of the array loops, only their leading single-byte run (decodeSingleByteRun).
 * Modified by the Flint authors.
 */
/** The decoders of the six standard charsets. Not public API. */
module flint.java.nio.charset.internal.decoders;

import flint.java.lang : NullPointerException;
import flint.java.nio.bytebuffer : ByteBuffer;
import flint.java.nio.charbuffer : CharBuffer;
import flint.java.nio.charset : Charset, StandardCharsets;
import flint.java.nio.charset.charsetdecoder : CharsetDecoder;
import flint.java.nio.charset.coderresult : CoderResult;
import flint.java.nio.charset.internal.coders : decodeSingleByteRun, isHighSurrogate,
    isLowSurrogate, isSurrogate, javaFloatToInt;

@safe:

/++
`charset.newDecoder()` for a standard charset. `Charset.init` stands for Java's `null` charset.
Throws: `NullPointerException` for `Charset.init`.
+/
CharsetDecoder standardDecoder(Charset charset)
{
    if (charset == StandardCharsets.US_ASCII)
        return new AsciiDecoder(charset);
    if (charset == StandardCharsets.ISO_8859_1)
        return new Latin1Decoder(charset);
    if (charset == StandardCharsets.UTF_8)
        return new Utf8Decoder(charset);
    if (charset == StandardCharsets.UTF_16)
        return new UnicodeDecoder(charset, byteOrderNone);
    if (charset == StandardCharsets.UTF_16BE)
        return new UnicodeDecoder(charset, byteOrderBig);
    if (charset == StandardCharsets.UTF_16LE)
        return new UnicodeDecoder(charset, byteOrderLittle);
    throw new NullPointerException();
}

/++
The default `CharsetEncoder.isLegalReplacement`: whether `charset`'s decoder, with both actions REPORT, decodes
`repl` without an error.
Throws: `NullPointerException` for `Charset.init`.
+/
package(flint.java.nio.charset) bool isLegalReplacementFor(Charset charset, scope const(byte)[] repl)
{
    auto decoder = standardDecoder(charset);
    auto src = ByteBuffer.wrap(repl.dup);
    auto dst = CharBuffer.allocate(javaFloatToInt(src.remaining() * decoder.maxCharsPerByte()));
    return !decoder.decode(src, dst, true).isError();
}

private:

enum byteOrderNone = 0;
enum byteOrderBig = 1;
enum byteOrderLittle = 2;

// sun.nio.cs.US_ASCII.Decoder: a negative byte is malformed. Java's array loop, taken when both buffers have an
// accessible array, reports a full output before it looks at the next byte; its buffer loop looks first.
final class AsciiDecoder : CharsetDecoder
{
    this(Charset cs)
    {
        super(cs, 1.0f, 1.0f);
    }

    protected override CoderResult decodeLoop(ByteBuffer src, CharBuffer dst)
    {
        const roomFirst = src.hasArray() && dst.hasArray();
        decodeSingleByteRun(src, dst, false);
        int mark = src.position();
        scope (exit)
            src.position(mark);
        while (src.hasRemaining())
        {
            if (roomFirst && !dst.hasRemaining())
                return CoderResult.OVERFLOW;
            const b = src.get();
            if (b < 0)
                return CoderResult.malformedForLength(1);
            if (!dst.hasRemaining())
                return CoderResult.OVERFLOW;
            dst.put(cast(wchar) b);
            ++mark;
        }
        return CoderResult.UNDERFLOW;
    }
}

// sun.nio.cs.ISO_8859_1.Decoder: every byte is the character of the same value.
final class Latin1Decoder : CharsetDecoder
{
    this(Charset cs)
    {
        super(cs, 1.0f, 1.0f);
    }

    protected override CoderResult decodeLoop(ByteBuffer src, CharBuffer dst)
    {
        decodeSingleByteRun(src, dst, true);
        int mark = src.position();
        scope (exit)
            src.position(mark);
        while (src.hasRemaining())
        {
            const b = src.get();
            if (!dst.hasRemaining())
                return CoderResult.OVERFLOW;
            dst.put(cast(wchar)(b & 0xFF));
            ++mark;
        }
        return CoderResult.UNDERFLOW;
    }
}

// sun.nio.cs.UTF_8.Decoder. A byte is read sign-extended, as Java's `int b = src.get()`.
final class Utf8Decoder : CharsetDecoder
{
    this(Charset cs)
    {
        super(cs, 1.0f, 1.0f);
    }

    protected override CoderResult decodeLoop(ByteBuffer src, CharBuffer dst)
    {
        decodeSingleByteRun(src, dst, false);
        int mark = src.position();
        const limit = src.limit();
        while (mark < limit)
        {
            const int b1 = src.get();
            CoderResult cr;
            if (b1 >= 0)
            {
                if (dst.remaining() < 1)
                    return xflow(src, mark, 1);
                dst.put(cast(wchar) b1);
                mark++;
            }
            else if ((b1 >> 5) == -2 && (b1 & 0x1E) != 0)
            {
                if (!decode2(b1, src, dst, mark, limit, cr))
                    return cr;
            }
            else if ((b1 >> 4) == -2)
            {
                if (!decode3(b1, src, dst, mark, limit, cr))
                    return cr;
            }
            else if ((b1 >> 3) == -2)
            {
                if (!decode4(b1, src, dst, mark, limit, cr))
                    return cr;
            }
            else
                return malformed(src, mark, 1);
        }
        return xflow(src, mark, 0);
    }

    // The branches of Java's loop for a lead byte of two, three and four bytes, after `src.get()` read it. Each
    // returns false with the loop's result in `cr`, or decodes the sequence and advances `mark` past it.
    private static bool decode2(int b1, ByteBuffer src, CharBuffer dst, ref int mark, int limit, out CoderResult cr)
    {
        if (limit - mark < 2 || dst.remaining() < 1)
            return fail(cr, xflow(src, mark, 2));
        const int b2 = src.get();
        if (isNotContinuation(b2))
            return fail(cr, malformedForLength(src, mark, 1));
        dst.put(cast(wchar)(((b1 & 0x1F) << 6) | (b2 & 0x3F)));
        mark += 2;
        return true;
    }

    private static bool decode3(int b1, ByteBuffer src, CharBuffer dst, ref int mark, int limit, out CoderResult cr)
    {
        const srcRemaining = limit - mark;
        if (srcRemaining < 3 || dst.remaining() < 1)
        {
            if (srcRemaining > 1 && isMalformed3_2(b1, src.get()))
                return fail(cr, malformedForLength(src, mark, 1));
            return fail(cr, xflow(src, mark, 3));
        }
        const int b2 = src.get();
        const int b3 = src.get();
        if (isMalformed3(b1, b2, b3))
            return fail(cr, malformed(src, mark, 3));
        const c = cast(wchar)(((b1 & 0x0F) << 12) | ((b2 & 0x3F) << 6) | (b3 & 0x3F));
        if (isSurrogate(c))
            return fail(cr, malformedForLength(src, mark, 3));
        dst.put(c);
        mark += 3;
        return true;
    }

    private static bool decode4(int b1, ByteBuffer src, CharBuffer dst, ref int mark, int limit, out CoderResult cr)
    {
        const srcRemaining = limit - mark;
        if (srcRemaining < 4 || dst.remaining() < 2)
        {
            const lead = b1 & 0xFF;
            if (lead > 0xF4 || (srcRemaining > 1 && isMalformed4_2(lead, src.get() & 0xFF)))
                return fail(cr, malformedForLength(src, mark, 1));
            if (srcRemaining > 2 && isNotContinuation(src.get()))
                return fail(cr, malformedForLength(src, mark, 2));
            return fail(cr, xflow(src, mark, 4));
        }
        const int b2 = src.get();
        const int b3 = src.get();
        const int b4 = src.get();
        const uc = ((b1 & 0x07) << 18) | ((b2 & 0x3F) << 12) | ((b3 & 0x3F) << 6) | (b4 & 0x3F);
        if (isMalformed4(b2, b3, b4) || uc < 0x10000 || uc > 0x10FFFF)
            return fail(cr, malformed(src, mark, 4));
        dst.put(cast(wchar)(0xD7C0 + (uc >> 10)));
        dst.put(cast(wchar)(0xDC00 + (uc & 0x3FF)));
        mark += 4;
        return true;
    }

    private static bool fail(out CoderResult cr, CoderResult result) pure nothrow @nogc
    {
        cr = result;
        return false;
    }

    private static bool isNotContinuation(int b) pure nothrow @nogc
    {
        return (b & 0xC0) != 0x80;
    }

    // E0 followed by 80..9F is overlong.
    private static bool isMalformed3(int b1, int b2, int b3) pure nothrow @nogc
    {
        return isMalformed3_2(b1, b2) || isNotContinuation(b3);
    }

    private static bool isMalformed3_2(int b1, int b2) pure nothrow @nogc
    {
        return (b1 == cast(byte) 0xE0 && (b2 & 0xE0) == 0x80) || isNotContinuation(b2);
    }

    private static bool isMalformed4(int b2, int b3, int b4) pure nothrow @nogc
    {
        return isNotContinuation(b2) || isNotContinuation(b3) || isNotContinuation(b4);
    }

    // F0 needs 90..BF next (no overlong form); F4 needs 80..8F (nothing above U+10FFFF). Both bytes unsigned.
    private static bool isMalformed4_2(int b1, int b2) pure nothrow @nogc
    {
        return (b1 == 0xF0 && (b2 < 0x90 || b2 > 0xBF)) || (b1 == 0xF4 && (b2 & 0xF0) != 0x80) || isNotContinuation(b2);
    }

    // The malformed length of the `nb`-byte sequence at the position.
    private static CoderResult malformedN(ByteBuffer src, int nb)
    {
        if (nb == 3)
        {
            const int b1 = src.get();
            const int b2 = src.get();
            return CoderResult.malformedForLength(isMalformed3_2(b1, b2) ? 1 : 2);
        }
        if (nb == 4)
        {
            const b1 = src.get() & 0xFF;
            const b2 = src.get() & 0xFF;
            if (b1 > 0xF4 || isMalformed4_2(b1, b2))
                return CoderResult.malformedForLength(1);
            if (isNotContinuation(src.get()))
                return CoderResult.malformedForLength(2);
            return CoderResult.malformedForLength(3);
        }
        return CoderResult.malformedForLength(1);
    }

    private static CoderResult malformed(ByteBuffer src, int mark, int nb)
    {
        src.position(mark);
        const cr = malformedN(src, nb);
        src.position(mark);
        return cr;
    }

    private static CoderResult malformedForLength(ByteBuffer src, int mark, int malformedNB)
    {
        src.position(mark);
        return CoderResult.malformedForLength(malformedNB);
    }

    // UNDERFLOW when the sequence of `nb` bytes is incomplete (or `nb` is 0), else OVERFLOW.
    private static CoderResult xflow(ByteBuffer src, int mark, int nb)
    {
        src.position(mark);
        return nb == 0 || src.remaining() < nb ? CoderResult.UNDERFLOW : CoderResult.OVERFLOW;
    }
}

// sun.nio.cs.UnicodeDecoder: UTF-16 in a fixed byte order, or (UTF-16) the order of a leading byte-order mark,
// big-endian by default.
final class UnicodeDecoder : CharsetDecoder
{
    private immutable int expectedByteOrder;
    private int currentByteOrder;

    this(Charset cs, int byteOrder)
    {
        super(cs, 0.5f, 1.0f);
        expectedByteOrder = currentByteOrder = byteOrder;
    }

    protected override CoderResult decodeLoop(ByteBuffer src, CharBuffer dst)
    {
        int mark = src.position();
        scope (exit)
            src.position(mark);
        while (src.remaining() > 1)
        {
            const b1 = src.get() & 0xFF;
            const b2 = src.get() & 0xFF;
            if (currentByteOrder == byteOrderNone)
            {
                const mark16 = (b1 << 8) | b2;
                if (mark16 == 0xFEFF || mark16 == 0xFFFE)
                {
                    currentByteOrder = mark16 == 0xFEFF ? byteOrderBig : byteOrderLittle;
                    mark += 2;
                    continue;
                }
                currentByteOrder = byteOrderBig;
            }
            const c = unit(b1, b2);
            if (isSurrogate(c))
            {
                if (!isHighSurrogate(c))
                    return CoderResult.malformedForLength(2);
                if (src.remaining() < 2)
                    return CoderResult.UNDERFLOW;
                const b3 = src.get() & 0xFF;
                const c2 = unit(b3, src.get() & 0xFF);
                if (!isLowSurrogate(c2))
                    return CoderResult.malformedForLength(4);
                if (dst.remaining() < 2)
                    return CoderResult.OVERFLOW;
                mark += 4;
                dst.put(c);
                dst.put(c2);
                continue;
            }
            if (!dst.hasRemaining())
                return CoderResult.OVERFLOW;
            mark += 2;
            dst.put(c);
        }
        return CoderResult.UNDERFLOW;
    }

    protected override void implReset()
    {
        currentByteOrder = expectedByteOrder;
    }

    private wchar unit(int b1, int b2) const pure nothrow @nogc
    {
        return cast(wchar)(currentByteOrder == byteOrderBig ? (b1 << 8) | b2 : (b2 << 8) | b1);
    }
}
