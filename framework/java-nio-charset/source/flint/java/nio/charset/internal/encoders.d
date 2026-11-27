/*
 * Copyright (c) 2000, 2021, Oracle and/or its affiliates. All rights reserved.
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
 * Ported from openjdk 21.0.13: the encoders of src/java.base/share/classes/sun/nio/cs/US_ASCII.java,
 * ISO_8859_1.java and UTF_8.java (Copyright (c) 2000, 2021), UnicodeEncoder.java (Copyright (c) 2000, 2010), and
 * UTF_16.java, UTF_16BE.java and UTF_16LE.java (Copyright (c) 2000, 2005).
 * Only the buffer loops are ported; the array loops are their intrinsic-backed fast paths.
 * Modified by the Flint authors.
 */
/** The encoders of the six standard charsets. Not public API. */
module flint.java.nio.charset.internal.encoders;

import flint.java.lang : NullPointerException;
import flint.java.nio.bytebuffer : ByteBuffer;
import flint.java.nio.charbuffer : CharBuffer;
import flint.java.nio.charset : Charset, StandardCharsets;
import flint.java.nio.charset.charsetencoder : CharsetEncoder;
import flint.java.nio.charset.coderresult : CoderResult;
import flint.java.nio.charset.internal.coders : isSurrogate, SurrogateParser;

@safe:

/++
`charset.newEncoder()` for a standard charset. `Charset.init` stands for Java's `null` charset.
Throws: `NullPointerException` for `Charset.init`.
+/
CharsetEncoder standardEncoder(Charset charset)
{
    if (charset == StandardCharsets.US_ASCII)
        return new AsciiEncoder(charset);
    if (charset == StandardCharsets.ISO_8859_1)
        return new Latin1Encoder(charset);
    if (charset == StandardCharsets.UTF_8)
        return new Utf8Encoder(charset);
    if (charset == StandardCharsets.UTF_16)
        return new UnicodeEncoder(charset, true, true);
    if (charset == StandardCharsets.UTF_16BE)
        return new UnicodeEncoder(charset, true, false);
    if (charset == StandardCharsets.UTF_16LE)
        return new UnicodeEncoder(charset, false, false);
    throw new NullPointerException();
}

private:

// sun.nio.cs.US_ASCII.Encoder and ISO_8859_1.Encoder: a character up to `maxChar` is its own byte; a character
// above it is unmappable; an unpaired surrogate is malformed. ISO-8859-1's array loop, taken when both buffers have an
// accessible array, reports a full output before it looks at the next character; the other loops look first.
class SingleByteEncoder : CharsetEncoder
{
    private immutable wchar maxChar;
    private SurrogateParser sgp;

    this(Charset cs, wchar maxChar)
    {
        this.maxChar = maxChar;
        super(cs, 1.0f, 1.0f);
    }

    alias canEncode = CharsetEncoder.canEncode;

    final override bool canEncode(wchar c)
    {
        return c <= maxChar;
    }

    protected final override CoderResult encodeLoop(CharBuffer src, ByteBuffer dst)
    {
        const roomFirst = maxChar == 0xFF && src.hasArray() && dst.hasArray();
        int mark = src.position();
        scope (exit)
            src.position(mark);
        while (src.hasRemaining())
        {
            if (roomFirst && !dst.hasRemaining())
                return CoderResult.OVERFLOW;
            const c = src.get();
            if (c <= maxChar)
            {
                if (!dst.hasRemaining())
                    return CoderResult.OVERFLOW;
                dst.put(cast(byte) c);
                mark++;
                continue;
            }
            if (sgp.parse(c, src) < 0)
                return sgp.error();
            return sgp.unmappableResult();
        }
        return CoderResult.UNDERFLOW;
    }
}

final class AsciiEncoder : SingleByteEncoder
{
    this(Charset cs)
    {
        super(cs, 0x7F);
    }

    override bool isLegalReplacement(scope const(byte)[] repl)
    {
        return (repl.length == 1 && repl[0] >= 0) || super.isLegalReplacement(repl);
    }
}

final class Latin1Encoder : SingleByteEncoder
{
    this(Charset cs)
    {
        super(cs, 0xFF);
    }

    override bool isLegalReplacement(scope const(byte)[] repl)
    {
        return true;
    }
}

// sun.nio.cs.UTF_8.Encoder.
final class Utf8Encoder : CharsetEncoder
{
    private SurrogateParser sgp;

    this(Charset cs)
    {
        super(cs, 1.1f, 3.0f);
    }

    alias canEncode = CharsetEncoder.canEncode;

    override bool canEncode(wchar c)
    {
        return !isSurrogate(c);
    }

    override bool isLegalReplacement(scope const(byte)[] repl)
    {
        return (repl.length == 1 && repl[0] >= 0) || super.isLegalReplacement(repl);
    }

    protected override CoderResult encodeLoop(CharBuffer src, ByteBuffer dst)
    {
        int mark = src.position();
        while (src.hasRemaining())
        {
            const c = src.get();
            if (c < 0x80)
            {
                if (!dst.hasRemaining())
                    return overflow(src, mark);
                dst.put(cast(byte) c);
            }
            else if (c < 0x800)
            {
                if (dst.remaining() < 2)
                    return overflow(src, mark);
                dst.put(cast(byte)(0xC0 | (c >> 6)));
                dst.put(cast(byte)(0x80 | (c & 0x3F)));
            }
            else if (isSurrogate(c))
            {
                const uc = sgp.parse(c, src);
                if (uc < 0)
                {
                    src.position(mark);
                    return sgp.error();
                }
                if (dst.remaining() < 4)
                    return overflow(src, mark);
                dst.put(cast(byte)(0xF0 | (uc >> 18)));
                dst.put(cast(byte)(0x80 | ((uc >> 12) & 0x3F)));
                dst.put(cast(byte)(0x80 | ((uc >> 6) & 0x3F)));
                dst.put(cast(byte)(0x80 | (uc & 0x3F)));
                mark++; // two units
            }
            else
            {
                if (dst.remaining() < 3)
                    return overflow(src, mark);
                dst.put(cast(byte)(0xE0 | (c >> 12)));
                dst.put(cast(byte)(0x80 | ((c >> 6) & 0x3F)));
                dst.put(cast(byte)(0x80 | (c & 0x3F)));
            }
            mark++;
        }
        src.position(mark);
        return CoderResult.UNDERFLOW;
    }

    private static CoderResult overflow(CharBuffer src, int mark)
    {
        src.position(mark);
        return CoderResult.OVERFLOW;
    }
}

// sun.nio.cs.UnicodeEncoder: UTF-16 in one byte order, optionally after a byte-order mark (UTF-16 writes one,
// big-endian). The replacement is U+FFFD in the same order.
final class UnicodeEncoder : CharsetEncoder
{
    private static immutable byte[2] bigReplacement = [cast(byte) 0xFF, cast(byte) 0xFD];
    private static immutable byte[2] littleReplacement = [cast(byte) 0xFD, cast(byte) 0xFF];

    private immutable bool bigEndian;
    private immutable bool usesMark;
    private bool needsMark;
    private SurrogateParser sgp;

    this(Charset cs, bool bigEndian, bool usesMark)
    {
        this.bigEndian = bigEndian;
        this.usesMark = needsMark = usesMark;
        super(cs, 2.0f, usesMark ? 4.0f : 2.0f, bigEndian ? bigReplacement[] : littleReplacement[]);
    }

    alias canEncode = CharsetEncoder.canEncode;

    override bool canEncode(wchar c)
    {
        return !isSurrogate(c);
    }

    protected override CoderResult encodeLoop(CharBuffer src, ByteBuffer dst)
    {
        int mark = src.position();
        if (needsMark && src.hasRemaining())
        {
            if (dst.remaining() < 2)
                return CoderResult.OVERFLOW;
            put(0xFEFF, dst);
            needsMark = false;
        }
        scope (exit)
            src.position(mark);
        while (src.hasRemaining())
        {
            const c = src.get();
            if (!isSurrogate(c))
            {
                if (dst.remaining() < 2)
                    return CoderResult.OVERFLOW;
                mark++;
                put(c, dst);
                continue;
            }
            const d = sgp.parse(c, src);
            if (d < 0)
                return sgp.error();
            if (dst.remaining() < 4)
                return CoderResult.OVERFLOW;
            mark += 2;
            put(cast(wchar)(0xD7C0 + (d >> 10)), dst);
            put(cast(wchar)(0xDC00 + (d & 0x3FF)), dst);
        }
        return CoderResult.UNDERFLOW;
    }

    protected override void implReset()
    {
        needsMark = usesMark;
    }

    private void put(wchar c, ByteBuffer dst)
    {
        const hi = cast(byte)(c >> 8);
        const lo = cast(byte)(c & 0xFF);
        dst.put(bigEndian ? hi : lo);
        dst.put(bigEndian ? lo : hi);
    }
}
