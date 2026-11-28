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
 * Ported from openjdk 21.0.13: src/java.base/share/classes/java/nio/charset/Charset-X-Coder.java.template
 * (the state machine and validation shared by both expansions), and the Parser class of
 * src/java.base/share/classes/sun/nio/cs/Surrogate.java (Copyright (c) 2000, 2010).
 * Modified by the Flint authors.
 */
/** Helpers shared by `CharsetDecoder` and `CharsetEncoder`. Not public API. */
module flint.java.nio.charset.internal.coders;

import flint.java.lang : IllegalArgumentException, IllegalStateException;
import flint.java.nio.bytebuffer : ByteBuffer;
import flint.java.nio.charbuffer : CharBuffer;
import flint.java.nio.charset.coderresult : CoderResult;

@safe:

package(flint.java.nio.charset):

enum ubyte stReset = 0;
enum ubyte stCoding = 1;
enum ubyte stEnd = 2;
enum ubyte stFlushed = 3;

/// `ArraysSupport.SOFT_MAX_ARRAY_LENGTH`.
enum int softMaxArrayLength = int.max - 8;

/// Java's `Current state = X, new state = Y`.
pragma(inline, false) noreturn throwIllegalState(ubyte from, ubyte to) pure
{
    static immutable string[4] names = ["RESET", "CODING", "CODING_END", "FLUSHED"];
    throw new IllegalStateException("Current state = " ~ names[from] ~ ", new state = " ~ names[to]);
}

pragma(inline, false) noreturn throwIllegalArgument(string message) pure
{
    throw new IllegalArgumentException(message);
}

/// The constructor checks, in Java's order. `!(x > 0)` also rejects NaN.
void checkRates(float average, float max, string averageName, string maxName) pure
{
    if (!(average > 0.0f))
        throwIllegalArgument("Non-positive " ~ averageName);
    if (!(max > 0.0f))
        throwIllegalArgument("Non-positive " ~ maxName);
    if (average > max)
        throwIllegalArgument(averageName ~ " exceeds " ~ maxName);
}

/// The common part of `replaceWith`: a `null` replacement counts as empty (R26).
void checkReplacementLength(size_t length, float max) pure
{
    if (length == 0)
        throwIllegalArgument("Empty replacement");
    if (length > max)
        throwIllegalArgument("Replacement too long");
}

/// Java's `String.length()` of UTF-8 `text`: one unit per BMP character, two per supplementary one (R14).
int utf16Length(scope const(char)[] text) pure nothrow @nogc
{
    size_t units;
    foreach (b; cast(const(ubyte)[]) text)
    {
        if ((b & 0xC0) != 0x80)
            ++units;
        if (b >= 0xF0)
            ++units;
    }
    return units > int.max ? int.max : cast(int) units;
}

/// Java's `(int) value` narrowing: NaN is 0 and out-of-range values saturate.
int javaFloatToInt(float value) pure nothrow @nogc
{
    if (value != value)
        return 0;
    if (value >= 2_147_483_648.0f)
        return int.max;
    if (value <= -2_147_483_648.0f)
        return int.min;
    return cast(int) value;
}

/// The capacity estimate of the convenience `decode(in)` / `encode(in)`.
int estimateCapacity(int remaining, float average) pure nothrow @nogc
{
    const n = javaFloatToInt(remaining * average);
    return n < softMaxArrayLength ? n : softMaxArrayLength;
}

/// `ArraysSupport.newLength(n, min(n + 1, 1024), n + 1)`, the convenience loop's growth on overflow.
int grownCapacity(int n) pure nothrow @nogc
{
    const preferred = 2L * n + 1;
    if (preferred > 0 && preferred <= softMaxArrayLength)
        return cast(int) preferred;
    // Compute in `long`: `n + 1` overflows int at the top of the range, where Java's `newLength` would throw OOME.
    const minGrowth = n < 1023 ? cast(long) n + 1 : 1024L;
    const minimum = cast(long) n + minGrowth;
    if (minimum <= softMaxArrayLength)
        return softMaxArrayLength;
    return minimum > int.max ? int.max : cast(int) minimum;
}

/++
The leading run of the array loops (`JLA.decodeASCII`, `inflateBytesToChars`): when both buffers have an accessible
array, decodes the bytes of `src` that are ASCII (every byte when `latin1`) while `dst` has room, and advances both
positions past them. The caller's buffer loop then handles what stopped the run, exactly as if it had read the run
itself.
+/
void decodeSingleByteRun(ByteBuffer src, CharBuffer dst, bool latin1) pure
{
    if (!src.hasArray() || !dst.hasArray())
        return;
    const n = src.remaining() < dst.remaining() ? src.remaining() : dst.remaining();
    const sp = src.arrayOffset() + src.position();
    const dp = dst.arrayOffset() + dst.position();
    const(byte)[] s = src.array()[sp .. sp + n];
    wchar[] d = dst.array()[dp .. dp + n];
    size_t i;
    if (latin1)
        for (; i < s.length; ++i)
            d[i] = cast(wchar)(s[i] & 0xFF);
    else
        for (; i < s.length && s[i] >= 0; ++i)
            d[i] = cast(wchar) s[i];
    src.position(src.position() + cast(int) i);
    dst.position(dst.position() + cast(int) i);
}

/++
The leading run of the array loops (`JLA.encodeASCII`, `StringCoding.implEncodeISOArray`): when both buffers have an
accessible array, encodes the characters of `src` up to `maxChar` (0x7F or 0xFF) while `dst` has room, and advances
both positions past them. The caller's buffer loop then handles what stopped the run.
+/
void encodeSingleByteRun(CharBuffer src, ByteBuffer dst, wchar maxChar) pure
{
    if (!src.hasArray() || !dst.hasArray())
        return;
    const n = src.remaining() < dst.remaining() ? src.remaining() : dst.remaining();
    const sp = src.arrayOffset() + src.position();
    const dp = dst.arrayOffset() + dst.position();
    const(wchar)[] s = src.array()[sp .. sp + n];
    byte[] d = dst.array()[dp .. dp + n];
    size_t i;
    for (; i < s.length && s[i] <= maxChar; ++i)
        d[i] = cast(byte) s[i];
    src.position(src.position() + cast(int) i);
    dst.position(dst.position() + cast(int) i);
}

/// Java's `Character.isSurrogate`.
bool isSurrogate(wchar c) pure nothrow @nogc
{
    return c >= 0xD800 && c <= 0xDFFF;
}

/// Java's `Character.isHighSurrogate`.
bool isHighSurrogate(wchar c) pure nothrow @nogc
{
    return c >= 0xD800 && c <= 0xDBFF;
}

/// Java's `Character.isLowSurrogate`.
bool isLowSurrogate(wchar c) pure nothrow @nogc
{
    return c >= 0xDC00 && c <= 0xDFFF;
}

/// `sun.nio.cs.Surrogate.Parser`: reads one character, or one surrogate pair, from a `CharBuffer`.
struct SurrogateParser
{
    private CoderResult error_ = CoderResult.UNDERFLOW;
    private bool isPair;

    /++
    The code point of `c`, reading its low surrogate from `src` when `c` is a high one; or -1, with the reason in
    `error()`: UNDERFLOW when the low surrogate is not there yet, MALFORMED[1] for an unpaired surrogate.
    +/
    int parse(wchar c, CharBuffer src) pure
    {
        if (isHighSurrogate(c))
        {
            if (!src.hasRemaining())
                return fail(CoderResult.UNDERFLOW);
            const d = src.get();
            if (!isLowSurrogate(d))
                return fail(CoderResult.malformedForLength(1));
            isPair = true;
            return 0x10000 + ((c - 0xD800) << 10) + (d - 0xDC00);
        }
        if (isLowSurrogate(c))
            return fail(CoderResult.malformedForLength(1));
        isPair = false;
        return c;
    }

    /// The error of the last `parse` that returned -1.
    CoderResult error() const pure nothrow @nogc
    {
        return error_;
    }

    /// UNMAPPABLE for the last character parsed, one or two units long.
    CoderResult unmappableResult() const pure
    {
        return CoderResult.unmappableForLength(isPair ? 2 : 1);
    }

    private int fail(CoderResult result) pure nothrow @nogc
    {
        error_ = result;
        return -1;
    }
}
