/*
 * Copyright (c) 2012, 2023, Oracle and/or its affiliates. All rights reserved.
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
 *
 * Modified by the Flint authors: ported to D from OpenJDK 21.0.13
 * src/java.base/share/classes/java/util/Base64.java.
 */
/// Java SE 21 Base64 encoders and decoders (RFC 4648 and RFC 2045).
///
/// Import from `flint.java.util.base64`; the `flint.java.util` package module
/// cannot re-export a `flint:java-util` leaf.
module flint.java.util.base64;

@safe:

/// Factory for RFC 4648 basic/URL-safe and RFC 2045 MIME Base64 encoders and decoders.
struct Base64
{
    @disable this();

    /// Return a basic RFC 4648 Base64 encoder.
    static Encoder getEncoder() pure nothrow
    {
        return new Encoder(false, null, -1, true);
    }

    /// Return a URL- and filename-safe RFC 4648 Base64 encoder.
    static Encoder getUrlEncoder() pure nothrow
    {
        return new Encoder(true, null, -1, true);
    }

    /// Return an RFC 2045 MIME Base64 encoder with 76-character CRLF lines.
    static Encoder getMimeEncoder() pure nothrow
    {
        return new Encoder(false, crlf, mimeLineMax, true);
    }

    /// Return a MIME encoder with `lineLength` rounded down to a multiple of 4
    /// and the given line separator; a length of 0 or less gives the basic
    /// encoder. A separator containing a Base64 alphabet byte or `'='` throws
    /// `IllegalArgumentException`. The separator is copied (R26: `null` counts as empty).
    static Encoder getMimeEncoder(int lineLength, scope const(byte)[] lineSeparator) pure
    {
        foreach (b; lineSeparator)
        {
            if (fromBase64[cast(ubyte) b] != -1)
                failIllegal("Illegal base64 line separator character 0x", b);
        }
        lineLength &= ~0b11;
        if (lineLength <= 0)
            return getEncoder();
        return new Encoder(false, lineSeparator.idup, lineLength, true);
    }

    /// Return a basic RFC 4648 Base64 decoder.
    static Decoder getDecoder() pure nothrow
    {
        return new Decoder(false, false);
    }

    /// Return a URL- and filename-safe RFC 4648 Base64 decoder.
    static Decoder getUrlDecoder() pure nothrow
    {
        return new Decoder(true, false);
    }

    /// Return an RFC 2045 MIME Base64 decoder, which ignores bytes outside the alphabet.
    static Decoder getMimeDecoder() pure nothrow
    {
        return new Decoder(false, true);
    }

    /// Immutable, thread-safe Base64 encoder.
    static final class Encoder
    {
        private immutable(byte)[] newline;
        private immutable int linemax;
        private immutable bool isURL;
        private immutable bool doPadding;

        private this(bool isURL, immutable(byte)[] newline, int linemax, bool doPadding) pure nothrow @nogc
        {
            this.isURL = isURL;
            this.newline = newline;
            this.linemax = linemax;
            this.doPadding = doPadding;
        }

        /// Encode all bytes of `src` into a newly allocated array (R26: `null` counts as empty).
        byte[] encode(scope const(byte)[] src) const pure nothrow
        {
            auto dst = new byte[encodedLength(src.length, true)];
            encodeInto(src, cast(ubyte[]) dst);
            return dst;
        }

        /// Encode all bytes of `src` into `dst` and return the number of bytes written;
        /// throws `IllegalArgumentException` when `dst` is too small (R26).
        int encode(scope const(byte)[] src, scope byte[] dst) const pure
        {
            const len = encodedLength(src.length, false);
            if (len == size_t.max || dst.length < len)
                failArgument("Output byte array is too small for encoding all input bytes");
            return cast(int) encodeInto(src, cast(ubyte[]) dst);
        }

        /// Encode all bytes of `src` into an ASCII string (R26).
        /// A separator byte above 0x7F becomes the Latin-1 character Java's String holds.
        string encodeToString(scope const(byte)[] src) const pure nothrow
        {
            auto dst = new char[encodedLength(src.length, true)];
            encodeInto(src, cast(ubyte[]) dst);
            foreach (b; newline)
            {
                if (b < 0)
                    return widenLatin1(dst);
            }
            return dst;
        }

        /// Return an encoder like this one that adds no `'='` padding.
        Encoder withoutPadding() pure nothrow
        {
            if (!doPadding)
                return this;
            return new Encoder(isURL, newline, linemax, false);
        }

        /// Java's encoded length, or `size_t.max` (or `OutOfMemoryError` when
        /// `throwOOME`) when it exceeds a Java array's `int` length.
        private size_t encodedLength(size_t srclen, bool throwOOME) const pure nothrow @nogc
        {
            // Below 2^31 input bytes the arithmetic stays far inside ulong; only the result is bounded.
            ulong len = ulong.max;
            if (srclen <= int.max)
            {
                len = doPadding ? 4 * ((srclen + 2) / 3) : 4 * (srclen / 3) + (srclen % 3 == 0 ? 0 : srclen % 3 + 1);
                if (linemax > 0 && len > 0)
                    len += (len - 1) / linemax * newline.length;
            }
            if (len > int.max)
            {
                if (throwOOME)
                    tooLarge();
                return size_t.max;
            }
            return cast(size_t) len;
        }

        pragma(inline, false)
        {
            private size_t encodeInto(scope const(byte)[] src, scope ubyte[] dst) const pure nothrow @nogc
            {
                const string base64 = isURL ? toBase64URL : toBase64;
                const size_t end = src.length;
                size_t sp;
                size_t slen = end / 3 * 3;
                const size_t sl = slen;
                if (linemax > 0 && slen > linemax / 4 * 3)
                    slen = linemax / 4 * 3;
                size_t dp;
                while (sp < sl)
                {
                    const size_t sl0 = sp + slen < sl ? sp + slen : sl;
                    for (size_t sp0 = sp; sp0 < sl0; sp0 += 3)
                    {
                        const uint high = cast(ubyte) src[sp0] << 16 | cast(ubyte) src[sp0 + 1] << 8;
                        const uint bits = high | cast(ubyte) src[sp0 + 2];
                        dst[dp++] = base64[(bits >>> 18) & 0x3f];
                        dst[dp++] = base64[(bits >>> 12) & 0x3f];
                        dst[dp++] = base64[(bits >>> 6) & 0x3f];
                        dst[dp++] = base64[bits & 0x3f];
                    }
                    const size_t dlen = (sl0 - sp) / 3 * 4;
                    sp = sl0;
                    if (dlen == linemax && sp < end)
                    {
                        foreach (b; newline)
                            dst[dp++] = b;
                    }
                }
                if (sp < end)
                {
                    const uint b0 = cast(ubyte) src[sp++];
                    dst[dp++] = base64[b0 >> 2];
                    if (sp == end)
                    {
                        dst[dp++] = base64[(b0 << 4) & 0x3f];
                        if (doPadding)
                        {
                            dst[dp++] = '=';
                            dst[dp++] = '=';
                        }
                    }
                    else
                    {
                        const uint b1 = cast(ubyte) src[sp++];
                        dst[dp++] = base64[(b0 << 4) & 0x3f | (b1 >> 4)];
                        dst[dp++] = base64[(b1 << 2) & 0x3f];
                        if (doPadding)
                            dst[dp++] = '=';
                    }
                }
                return dp;
            }
        }
    }

    /// Immutable, thread-safe Base64 decoder.
    static final class Decoder
    {
        private immutable bool isURL;
        private immutable bool isMIME;

        private this(bool isURL, bool isMIME) pure nothrow @nogc
        {
            this.isURL = isURL;
            this.isMIME = isMIME;
        }

        /// Decode all bytes of `src` into a newly allocated array; throws
        /// `IllegalArgumentException` when `src` is not valid Base64 (R26).
        byte[] decode(scope const(byte)[] src) const pure
        {
            auto dst = new byte[decodedLength(src)];
            const written = decodeInto(src, cast(ubyte[]) dst);
            return written == dst.length ? dst : dst[0 .. written];
        }

        /// Decode `src` after encoding it as ISO-8859-1, as Java does: each code
        /// point above U+00FF, and each malformed UTF-8 sequence, becomes `'?'` (R26).
        byte[] decode(scope const(char)[] src) const pure
        {
            size_t at;
            while (at < src.length && src[at] < 0x80)
                ++at;
            if (at == src.length)
                return decode(cast(const(byte)[]) src);
            return decode(latin1(src, at));
        }

        /// Decode all bytes of `src` into `dst` and return the number of bytes written;
        /// throws `IllegalArgumentException` when `src` is invalid or `dst` too small (R26).
        int decode(scope const(byte)[] src, scope byte[] dst) const pure
        {
            const len = decodedLength(src);
            if (dst.length < len)
                failArgument("Output byte array is too small for decoding all input bytes");
            return cast(int) decodeInto(src, cast(ubyte[]) dst);
        }

        private size_t decodedLength(scope const(byte)[] src) const pure
        {
            const size_t sl = src.length;
            if (sl == 0)
                return 0;
            if (sl < 2)
            {
                if (isMIME)
                    return 0;
                failArgument("Input byte[] should at least have 2 bytes for base64 bytes");
            }
            const byte[] base64 = isURL ? fromBase64URL : fromBase64;
            size_t len = sl;
            size_t paddings;
            if (isMIME)
            {
                size_t n;
                for (size_t sp; sp < sl; ++sp)
                {
                    const ubyte b = src[sp];
                    if (b == '=')
                    {
                        len -= sl - sp;
                        break;
                    }
                    if (base64[b] == -1)
                        ++n;
                }
                len -= n;
            }
            else if (src[sl - 1] == '=')
            {
                ++paddings;
                if (src[sl - 2] == '=')
                    ++paddings;
            }
            if (paddings == 0 && (len & 0x3) != 0)
                paddings = 4 - (len & 0x3);
            const size_t full = 3 * ((len + 3) / 4);
            return full > paddings ? full - paddings : 0;
        }

        pragma(inline, false) private size_t decodeInto(scope const(byte)[] src, scope ubyte[] dst) const pure
        {
            const byte[] base64 = isURL ? fromBase64URL : fromBase64;
            const size_t sl = src.length;
            size_t sp;
            size_t dp;
            int bits;
            int shiftto = 18;
            while (sp < sl)
            {
                if (shiftto == 18 && sp + 4 < sl)
                    decodeQuads(base64, src, sp, dst, dp);
                if (sp >= sl)
                    break;
                const byte raw = src[sp++];
                const int b = base64[cast(ubyte) raw];
                if (b == -2)
                {
                    checkPadding(src, sp, shiftto);
                    break;
                }
                if (b < 0)
                {
                    if (isMIME)
                        continue;
                    failIllegal("Illegal base64 character ", raw);
                }
                bits |= b << shiftto;
                shiftto -= 6;
                if (shiftto < 0)
                {
                    putBytes(dst, dp, bits, 3);
                    shiftto = 18;
                    bits = 0;
                }
            }
            if (shiftto == 12)
                failArgument("Last unit does not have enough valid bits");
            if (shiftto != 18)
                putBytes(dst, dp, bits, shiftto == 6 ? 1 : 2);
            for (; sp < sl; ++sp)
            {
                if (!isMIME || base64[cast(ubyte) src[sp]] >= 0)
                    failEnding(sp + isMIME);
            }
            return dp;
        }
    }
}

private:

enum string toBase64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
enum string toBase64URL = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
enum int mimeLineMax = 76;
immutable byte[] crlf = ['\r', '\n'];

byte[256] decodeTable(string alphabet) pure nothrow @nogc
{
    byte[256] table = -1;
    foreach (i, c; alphabet)
        table[c] = cast(byte) i;
    table['='] = -2;
    return table;
}

immutable byte[256] fromBase64 = decodeTable(toBase64);
immutable byte[256] fromBase64URL = decodeTable(toBase64URL);

pure nothrow @nogc
{
    /// Decode whole 4-byte units from `sp` until one holds a byte outside the alphabet.
    void decodeQuads(scope const byte[] table, scope const(byte)[] src, ref size_t sp, scope ubyte[] dst, ref size_t dp)
    {
        const size_t end = sp + ((src.length - sp) & ~cast(size_t) 0b11);
        while (sp < end)
        {
            const int b1 = table[cast(ubyte) src[sp]];
            const int b2 = table[cast(ubyte) src[sp + 1]];
            const int b3 = table[cast(ubyte) src[sp + 2]];
            const int b4 = table[cast(ubyte) src[sp + 3]];
            if ((b1 | b2 | b3 | b4) < 0)
                return;
            putBytes(dst, dp, b1 << 18 | b2 << 12 | b3 << 6 | b4, 3);
            sp += 4;
        }
    }

    /// Write the top `count` of the three bytes in `bits`.
    void putBytes(scope ubyte[] dst, ref size_t dp, int bits, int count)
    {
        dst[dp++] = cast(ubyte)(bits >> 16);
        if (count > 1)
            dst[dp++] = cast(ubyte)(bits >> 8);
        if (count > 2)
            dst[dp++] = cast(ubyte) bits;
    }
}

/// Accept a `'='` read just before `sp` only where Java does.
void checkPadding(scope const(byte)[] src, ref size_t sp, int shiftto) pure
{
    // =     shiftto==18 unnecessary padding
    // x=    shiftto==12 a dangling single x
    // xx=   shiftto==6&&sp==sl missing last =
    // xx=y  shiftto==6 last is not =
    if (shiftto == 18 || (shiftto == 6 && (sp == src.length || src[sp++] != '=')))
        failArgument("Input byte array has wrong 4-byte ending unit");
}

/// Java's `String.getBytes(ISO_8859_1)` of UTF-8 `src`, whose first `ascii` bytes are ASCII.
const(byte)[] latin1(scope const(char)[] src, size_t ascii) pure nothrow
{
    import flint.engine.aot.text : decodeUtf8;

    auto bytes = new byte[src.length];
    bytes[0 .. ascii] = cast(const(byte)[]) src[0 .. ascii];
    size_t n = ascii;
    size_t at = ascii;
    while (at < src.length)
    {
        const dchar c = decodeUtf8(src, at);
        bytes[n++] = cast(byte)(c <= 0xff ? c : '?');
    }
    return bytes[0 .. n];
}

/// Re-encode Latin-1 `text` as UTF-8.
pragma(inline, false) string widenLatin1(scope const(char)[] text) pure nothrow
{
    size_t high;
    foreach (c; text)
        high += c >= 0x80;
    auto wide = new char[text.length + high];
    size_t n;
    foreach (c; text)
    {
        if (c < 0x80)
        {
            wide[n++] = c;
        }
        else
        {
            wide[n++] = cast(char)(0xc0 | c >> 6);
            wide[n++] = cast(char)(0x80 | (c & 0x3f));
        }
    }
    return wide;
}

pragma(inline, false) noreturn failArgument(string message) pure
{
    import flint.java.lang : IllegalArgumentException;

    throw new IllegalArgumentException(message);
}

/// Throw with Java's `Integer.toString(b, 16)` of the signed byte appended.
pragma(inline, false) noreturn failIllegal(string prefix, byte b) pure
{
    import flint.java.lang : IllegalArgumentException;

    enum string digits = "0123456789abcdef";
    const uint magnitude = b < 0 ? -cast(int) b : b;
    char[3] text;
    size_t at = text.length;
    text[--at] = digits[magnitude & 0xf];
    if (magnitude > 0xf)
        text[--at] = digits[magnitude >> 4];
    if (b < 0)
        text[--at] = '-';
    throw new IllegalArgumentException(prefix ~ text[at .. $].idup);
}

pragma(inline, false) noreturn failEnding(size_t position) pure
{
    import flint.java.lang : IllegalArgumentException;

    char[20] text;
    size_t at = text.length;
    do
    {
        text[--at] = cast(char)('0' + position % 10);
        position /= 10;
    }
    while (position != 0);
    throw new IllegalArgumentException("Input byte array has incorrect ending byte at " ~ text[at .. $].idup);
}

pragma(inline, false) noreturn tooLarge() pure nothrow @nogc
{
    import core.exception : onOutOfMemoryError;

    onOutOfMemoryError();
}
