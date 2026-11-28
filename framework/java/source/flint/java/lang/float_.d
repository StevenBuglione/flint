/*
 * Copyright (c) 1994, 2023, Oracle and/or its affiliates. All rights reserved.
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

// Ported from openjdk 21.0.13: src/java.base/share/classes/java/lang/Float.java
// Modified by the Flint authors: the static members as a zero-aggregate leaf. A boxed `Float` is a D `float`
// (R5), so `valueOf` returns the primitive. Parsing goes through flint.java.internal.math.floatingdecimal;
// formatting through flint.serde.java_number. The throwing and string-returning members are zero-parameter
// templates, so only a program that calls them links the `flint.java.lang` exception hierarchy or the GC
// array copy. The bit operations use raw IEEE-754 unions. `TYPE`, `describeConstable`, `resolveConstant` and
// the instance members are not ported.

/// Java 21 `java.lang.Float`'s static members. Import from `flint.java.lang.float_` (R19: `float` is a D keyword).
module flint.java.lang.float_;

@safe:

/// Java's `Float` statics.
struct Float
{
    /// The smallest positive nonzero value, 2^-149.
    enum float MIN_VALUE = float.min_normal * float.epsilon;
    /// The largest finite value, (2 - 2^-23) * 2^127.
    enum float MAX_VALUE = float.max;
    /// The smallest positive normal value, 2^-126.
    enum float MIN_NORMAL = float.min_normal;
    /// The number of significand bits, 24.
    enum int PRECISION = 24;
    /// The maximum binary exponent, 127.
    enum int MAX_EXPONENT = 127;
    /// The minimum binary exponent, -126.
    enum int MIN_EXPONENT = -126;
    /// The number of bits in the representation, 32.
    enum int SIZE = 32;
    /// The number of bytes in the representation, 4.
    enum int BYTES = 4;
    /// A not-a-number value.
    enum float NAN = float.nan;
    /// Java spells the field `NaN`; an alias keeps the Java name without the linter reading it as a variable.
    alias NaN = NAN;
    /// The positive infinity value.
    enum float POSITIVE_INFINITY = float.infinity;
    /// The negative infinity value.
    enum float NEGATIVE_INFINITY = -float.infinity;

    /// Java's `Float.toString(float)`: the shortest round-trip decimal text.
    static string toString()(float value) pure nothrow
    {
        import flint.serde.java_number : javaFloatString;

        return javaFloatString(value);
    }

    /// Java's `Float.toHexString(float)`: the C99 hexadecimal text, or the decimal text for NaN and infinity.
    static string toHexString()(float value) pure nothrow
    {
        import flint.java.lang.double_ : Double;
        import flint.java.lang.math : Math;

        if (value != value || value == float.infinity || value == -float.infinity)
            return toString(value);

        if (Math.abs(value) < MIN_NORMAL && value != 0.0f)
        {
            const adjusted = Math.scalb(cast(double) value, Double.MIN_EXPONENT - MIN_EXPONENT);
            const text = Double.toHexString(adjusted);
            return text.length >= 6 && text[$ - 6 .. $] == "p-1022" ? text[0 .. $ - 6] ~ "p-126" : text;
        }
        return Double.toHexString(value);
    }

    /++
    Java's `Float.parseFloat(String)`. Accepts the decimal and hexadecimal forms, Java's whitespace, and the
    `f`/`F`/`d`/`D` suffix. Throws `NumberFormatException` with Java's message; a null argument throws
    `NullPointerException`.
    +/
    static float parseFloat()(string s)
    {
        import flint.java.internal.math.floatingdecimal : FloatingDecimalStatus, parseDouble;
        import flint.java.lang : NumberFormatException;
        import flint.java.lang.nullpointerexception : NullPointerException;

        if (s is null)
            throw new NullPointerException("Cannot parse a null string");
        if (s.length == 0)
            throw new NumberFormatException("empty String");

        const result = parseDouble(s);
        if (result.status == FloatingDecimalStatus.ok)
            return cast(float) result.value;
        throw NumberFormatException.forInputString(s);
    }

    /// Java's `Float.valueOf(float)`: the value itself (R5).
    static float valueOf(float value) pure nothrow @nogc
    {
        return value;
    }

    /// Java's `Float.valueOf(String)`: `parseFloat` as a boxed value (R5).
    static float valueOf()(string s)
    {
        return parseFloat(s);
    }

    /// Java's `Float.isNaN(float)`.
    static bool isNaN(float value) pure nothrow @nogc
    {
        return value != value;
    }

    /// Java's `Float.isInfinite(float)`.
    static bool isInfinite(float value) pure nothrow @nogc
    {
        return value == float.infinity || value == -float.infinity;
    }

    /// Java's `Float.isFinite(float)`.
    static bool isFinite(float value) pure nothrow @nogc
    {
        return value == value && value != float.infinity && value != -float.infinity;
    }

    /// Java's `Float.floatToRawIntBits(float)`: the IEEE-754 bits, preserving NaN payloads.
    static int floatToRawIntBits(float value) pure nothrow @nogc
    {
        union Bits
        {
            float value;
            int bits;
        }

        Bits bits;
        bits.value = value;
        return bits.bits;
    }

    /// Java's `Float.floatToIntBits(float)`: the IEEE-754 bits, with all NaNs collapsed to the canonical NaN.
    static int floatToIntBits(float value) pure nothrow @nogc
    {
        if (value != value)
            return 0x7fc0_0000;
        return floatToRawIntBits(value);
    }

    /// Java's `Float.intBitsToFloat(int)`: the float with the given IEEE-754 bits.
    static float intBitsToFloat(int bits) pure nothrow @nogc
    {
        union Bits
        {
            float value;
            int bits;
        }

        Bits result;
        result.bits = bits;
        return result.value;
    }

    /// Java's `Float.hashCode(float)`: the canonical bits.
    static int hashCode(float value) pure nothrow @nogc
    {
        return floatToIntBits(value);
    }

    /// Java's `Float.compare(float, float)`: the IEEE total order, with all NaNs equal and above infinity.
    static int compare(float left, float right) pure nothrow @nogc
    {
        if (left < right)
            return -1;
        if (left > right)
            return 1;

        const leftBits = floatToIntBits(left);
        const rightBits = floatToIntBits(right);
        if (leftBits == rightBits)
            return 0;
        return leftBits < rightBits ? -1 : 1;
    }

    /// Java's `Float.sum(float, float)`: the ordinary IEEE addition.
    static float sum(float left, float right) pure nothrow @nogc
    {
        return left + right;
    }

    /// Java's `Float.max(float, float)`: `Math.max`, with NaN and signed-zero rules.
    static float max(float left, float right) pure nothrow @nogc
    {
        import flint.java.lang.math : Math;

        return Math.max(left, right);
    }

    /// Java's `Float.min(float, float)`: `Math.min`, with NaN and signed-zero rules.
    static float min(float left, float right) pure nothrow @nogc
    {
        import flint.java.lang.math : Math;

        return Math.min(left, right);
    }

    /// Java's `Float.float16ToFloat(short)`: the binary16 value widened to binary32, exactly.
    static float float16ToFloat(short value) pure nothrow @nogc
    {
        const int raw = value;
        const int signBit = raw & 0x8000;
        const int exponentBits = raw & 0x7c00;
        const int significandBits = raw & 0x03ff;
        const float sign = signBit != 0 ? -1.0f : 1.0f;
        const int exponent = (exponentBits >> 10) - 15;

        if (exponent == -15)
            return sign * (0x1p-24f * significandBits);
        if (exponent == 16)
        {
            if (significandBits == 0)
                return sign * float.infinity;
            return intBitsToFloat((signBit << 16) | 0x7f80_0000 | (significandBits << 13));
        }
        const int exponentField = (exponent + 127) << 23;
        return intBitsToFloat((signBit << 16) | exponentField | (significandBits << 13));
    }

    /// Java's `Float.floatToFloat16(float)`: the binary32 value narrowed to binary16, round to nearest even.
    static short floatToFloat16(float value) pure nothrow @nogc
    {
        import flint.java.lang.math : Math;

        const int doppel = floatToRawIntBits(value);
        const short signBit = cast(short)((doppel & 0x8000_0000) >>> 16);

        if (value != value)
            return cast(short)(signBit | 0x7c00 | ((doppel & 0x007f_e000) >> 13) | (
                    (doppel & 0x0000_1ff0) >> 4) | (doppel & 0x0000_000f));

        const float magnitude = Math.abs(value);
        if (magnitude >= (0x1.ffcp15f + 0x0.002p15f))
            return cast(short)(signBit | 0x7c00);
        if (magnitude <= 0x1.0p-24f * 0.5f)
            return signBit;

        int exponent = Math.getExponent(value);
        int exponentDelta = 0;
        int msb = 0x0000_0000;
        if (exponent < -14)
        {
            exponentDelta = -14 - exponent;
            exponent = -15;
            msb = 0x0080_0000;
        }
        const int significandBits = doppel & 0x007f_ffff | msb;
        short rounded = cast(short)(significandBits >> (13 + exponentDelta));
        const int least = significandBits & (1 << (13 + exponentDelta));
        const int round = significandBits & (1 << (12 + exponentDelta));
        const int sticky = significandBits & ((1 << (12 + exponentDelta)) - 1);
        if (round != 0 && (least | sticky) != 0)
            ++rounded;
        return cast(short)(signBit | ((exponent + 15) << 10) + rounded);
    }
}
