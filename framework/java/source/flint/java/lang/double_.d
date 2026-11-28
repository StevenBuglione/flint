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

// Ported from openjdk 21.0.13: src/java.base/share/classes/java/lang/Double.java
// Modified by the Flint authors: the static members as a zero-aggregate leaf. A boxed `Double` is a D `double`
// (R5), so `valueOf` returns the primitive. Parsing goes through flint.java.internal.math.floatingdecimal;
// formatting through flint.serde.java_number. The throwing and string-returning members are zero-parameter
// templates, so only a program that calls them links the `flint.java.lang` exception hierarchy or the GC
// array copy. The bit operations use raw IEEE-754 unions. `TYPE`, `describeConstable`, `resolveConstant` and
// the instance members are not ported.

/// Java 21 `java.lang.Double`'s static members. Import from `flint.java.lang.double_` (R19: `double` is a D keyword).
module flint.java.lang.double_;

@safe:

/// Java's `Double` statics.
struct Double
{
    /// The smallest positive nonzero value, 2^-1074.
    enum double MIN_VALUE = double.min_normal * double.epsilon;
    /// The largest finite value, (2 - 2^-52) * 2^1023.
    enum double MAX_VALUE = double.max;
    /// The smallest positive normal value, 2^-1022.
    enum double MIN_NORMAL = double.min_normal;
    /// The number of significand bits, 53.
    enum int PRECISION = 53;
    /// The maximum binary exponent, 1023.
    enum int MAX_EXPONENT = 1023;
    /// The minimum binary exponent, -1022.
    enum int MIN_EXPONENT = -1022;
    /// The number of bits in the representation, 64.
    enum int SIZE = 64;
    /// The number of bytes in the representation, 8.
    enum int BYTES = 8;
    /// A not-a-number value.
    enum double NAN = double.nan;
    /// Java spells the field `NaN`; an alias keeps the Java name without the linter reading it as a variable.
    alias NaN = NAN;
    /// The positive infinity value.
    enum double POSITIVE_INFINITY = double.infinity;
    /// The negative infinity value.
    enum double NEGATIVE_INFINITY = -double.infinity;

    /// Java's `Double.toString(double)`: the shortest round-trip decimal text.
    static string toString()(double value) pure nothrow
    {
        import flint.serde.java_number : javaDoubleString;

        return javaDoubleString(value);
    }

    /// Java's `Double.toHexString(double)`: the C99 hexadecimal text, or the decimal text for NaN and infinity.
    static string toHexString()(double value) pure nothrow
    {
        import flint.java.lang.long_ : Long;
        import flint.java.lang.math : Math;

        if (value != value || value == double.infinity || value == -double.infinity)
            return toString(value);

        char[24] buffer = void;
        size_t length;

        if (Math.copySign(1.0, value) == -1.0)
            buffer[length++] = '-';
        buffer[length++] = '0';
        buffer[length++] = 'x';

        const magnitude = Math.abs(value);
        if (magnitude == 0.0)
        {
            buffer[length++] = '0';
            buffer[length++] = '.';
            buffer[length++] = '0';
            buffer[length++] = 'p';
            buffer[length++] = '0';
        }
        else
        {
            const subnormal = magnitude < MIN_NORMAL;
            const bits = doubleToLongBits(magnitude) & 0x000f_ffff_ffff_ffffL | 0x1000_0000_0000_0000L;
            const text = Long.toHexString(bits)[3 .. 16];
            size_t end = text.length;
            while (end > 0 && text[end - 1] == '0')
                --end;
            buffer[length++] = subnormal ? '0' : '1';
            buffer[length++] = '.';
            if (end == 0)
                buffer[length++] = '0';
            else
                foreach (c; text[0 .. end])
                    buffer[length++] = c;
            buffer[length++] = 'p';
            const exponent = subnormal ? MIN_EXPONENT : Math.getExponent(magnitude);
            foreach (c; Long.toString(exponent))
                buffer[length++] = c;
        }
        return buffer[0 .. length].idup;
    }

    /++
    Java's `Double.parseDouble(String)`. Accepts the decimal and hexadecimal forms, Java's whitespace, and the
    `f`/`F`/`d`/`D` suffix. Throws `NumberFormatException` with Java's message; a null argument throws
    `NullPointerException`.
    +/
    static double parseDouble()(string s)
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
            return result.value;
        throw NumberFormatException.forInputString(s);
    }

    /// Java's `Double.valueOf(double)`: the value itself (R5).
    static double valueOf(double value) pure nothrow @nogc
    {
        return value;
    }

    /// Java's `Double.valueOf(String)`: `parseDouble` as a boxed value (R5).
    static double valueOf()(string s)
    {
        return parseDouble(s);
    }

    /// Java's `Double.isNaN(double)`.
    static bool isNaN(double value) pure nothrow @nogc
    {
        return value != value;
    }

    /// Java's `Double.isInfinite(double)`.
    static bool isInfinite(double value) pure nothrow @nogc
    {
        return value == double.infinity || value == -double.infinity;
    }

    /// Java's `Double.isFinite(double)`.
    static bool isFinite(double value) pure nothrow @nogc
    {
        return value == value && value != double.infinity && value != -double.infinity;
    }

    /// Java's `Double.doubleToRawLongBits(double)`: the IEEE-754 bits, preserving NaN payloads.
    static long doubleToRawLongBits(double value) pure nothrow @nogc
    {
        union Bits
        {
            double value;
            long bits;
        }

        Bits bits;
        bits.value = value;
        return bits.bits;
    }

    /// Java's `Double.doubleToLongBits(double)`: the IEEE-754 bits, with all NaNs collapsed to the canonical NaN.
    static long doubleToLongBits(double value) pure nothrow @nogc
    {
        if (value != value)
            return 0x7ff8_0000_0000_0000L;
        return doubleToRawLongBits(value);
    }

    /// Java's `Double.longBitsToDouble(long)`: the double with the given IEEE-754 bits.
    static double longBitsToDouble(long bits) pure nothrow @nogc
    {
        union Bits
        {
            double value;
            long bits;
        }

        Bits result;
        result.bits = bits;
        return result.value;
    }

    /// Java's `Double.hashCode(double)`: the canonical bits' xor-folded hash.
    static int hashCode(double value) pure nothrow @nogc
    {
        const bits = doubleToLongBits(value);
        return cast(int)(bits ^ (bits >>> 32));
    }

    /// Java's `Double.compare(double, double)`: the IEEE total order, with all NaNs equal and above infinity.
    static int compare(double left, double right) pure nothrow @nogc
    {
        if (left < right)
            return -1;
        if (left > right)
            return 1;

        const leftBits = doubleToLongBits(left);
        const rightBits = doubleToLongBits(right);
        if (leftBits == rightBits)
            return 0;
        return leftBits < rightBits ? -1 : 1;
    }

    /// Java's `Double.sum(double, double)`: the ordinary IEEE addition.
    static double sum(double left, double right) pure nothrow @nogc
    {
        return left + right;
    }

    /// Java's `Double.max(double, double)`: `Math.max`, with NaN and signed-zero rules.
    static double max(double left, double right) pure nothrow @nogc
    {
        import flint.java.lang.math : Math;

        return Math.max(left, right);
    }

    /// Java's `Double.min(double, double)`: `Math.min`, with NaN and signed-zero rules.
    static double min(double left, double right) pure nothrow @nogc
    {
        import flint.java.lang.math : Math;

        return Math.min(left, right);
    }
}
