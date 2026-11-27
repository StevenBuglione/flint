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

// Ported from openjdk 21.0.13: src/java.base/share/classes/java/lang/Math.java
// and src/java.base/share/classes/java/lang/StrictMath.java (floor, ceil, rint).
// Modified by the Flint authors: pure @safe nothrow @nogc leaf using raw IEEE-754 bit unions
// and explicit saturating float/double-to-integer bounds for Math.round. The exact integer
// family throws the Java exceptions, and guards division by zero and MIN_VALUE / -1 explicitly,
// because both trap (or are undefined) in D where Java defines them. The throwing members are
// zero-parameter templates that import the exceptions locally, so only code that calls them links
// the flint.java.lang aggregate; the IEEE-754 core stays a zero-aggregate leaf.

module flint.java.lang.math;

@safe:

private union DoubleBits
{
    double value;
    long bits;
}

private union FloatBits
{
    float value;
    int bits;
}

private long doubleToRawLongBits(double d) pure nothrow @nogc
{
    DoubleBits u = void;
    u.value = d;
    return u.bits;
}

private double longBitsToDouble(long bits) pure nothrow @nogc
{
    DoubleBits u = void;
    u.bits = bits;
    return u.value;
}

private int floatToRawIntBits(float f) pure nothrow @nogc
{
    FloatBits u = void;
    u.value = f;
    return u.bits;
}

private float intBitsToFloat(int bits) pure nothrow @nogc
{
    FloatBits u = void;
    u.bits = bits;
    return u.value;
}

private enum int DOUBLE_SIGNIFICAND_WIDTH = 53;
private enum int DOUBLE_MIN_EXPONENT = -1022;
private enum int DOUBLE_MAX_EXPONENT = 1023;
private enum int DOUBLE_EXP_BIAS = 1023;
private enum long DOUBLE_SIGN_BIT_MASK = cast(long) 0x8000_0000_0000_0000UL;
private enum long DOUBLE_EXP_BIT_MASK = 0x7FF0_0000_0000_0000L;
private enum long DOUBLE_SIGNIF_BIT_MASK = 0x000F_FFFF_FFFF_FFFFL;
private enum long DOUBLE_MAG_BIT_MASK = 0x7FFF_FFFF_FFFF_FFFFL;
private enum double DOUBLE_MIN_VALUE = 0x1p-1074;
private enum double TWO_TO_THE_52 = 0x1p52;
private enum double TWO_TO_THE_DOUBLE_SCALE_UP = 0x1p512;
private enum double TWO_TO_THE_DOUBLE_SCALE_DOWN = 0x1p-512;

private enum int FLOAT_SIGNIFICAND_WIDTH = 24;
private enum int FLOAT_MIN_EXPONENT = -126;
private enum int FLOAT_MAX_EXPONENT = 127;
private enum int FLOAT_EXP_BIAS = 127;
private enum int FLOAT_SIGN_BIT_MASK = cast(int) 0x8000_0000U;
private enum int FLOAT_EXP_BIT_MASK = 0x7F80_0000;
private enum int FLOAT_SIGNIF_BIT_MASK = 0x007F_FFFF;
private enum int FLOAT_MAG_BIT_MASK = 0x7FFF_FFFF;
private enum float FLOAT_MIN_VALUE = 0x1p-149f;

private enum double DEGREES_TO_RADIANS = 0.017453292519943295;
private enum double RADIANS_TO_DEGREES = 57.29577951308232;

private double powerOfTwoD(int n) pure nothrow @nogc
{
    assert(n >= DOUBLE_MIN_EXPONENT && n <= DOUBLE_MAX_EXPONENT);
    return longBitsToDouble(
            ((cast(long) n + cast(long) DOUBLE_EXP_BIAS) << (DOUBLE_SIGNIFICAND_WIDTH - 1)) & DOUBLE_EXP_BIT_MASK);
}

private float powerOfTwoF(int n) pure nothrow @nogc
{
    assert(n >= FLOAT_MIN_EXPONENT && n <= FLOAT_MAX_EXPONENT);
    return intBitsToFloat(((n + FLOAT_EXP_BIAS) << (FLOAT_SIGNIFICAND_WIDTH - 1)) & FLOAT_EXP_BIT_MASK);
}

private double floorOrCeil(double a, double negativeBoundary, double positiveBoundary, double sign) pure nothrow @nogc
{
    const exponent = Math.getExponent(a);
    if (exponent < 0)
        return a == 0.0 ? a : (a < 0.0 ? negativeBoundary : positiveBoundary);
    if (exponent >= 52)
        return a;

    const doppel = doubleToRawLongBits(a);
    const mask = DOUBLE_SIGNIF_BIT_MASK >> exponent;
    if ((mask & doppel) == 0L)
        return a;

    double result = longBitsToDouble(doppel & (~mask));
    if (sign * a > 0.0)
        result += sign;
    return result;
}

private noreturn throwArithmetic()(string message) pure
{
    import flint.java.lang : ArithmeticException;

    throw new ArithmeticException(message);
}

// DMD -O -inline folds the unreachable division of an inlined literal zero divisor into a "divide by zero"
// compile error, so `Math.floorDiv(1, 0)` would not compile. DMD keeps these helpers out of line. Other
// compilers inline them.
version (DigitalMars)
    private enum bool inlineDivision = false;
else
    private enum bool inlineDivision = true;

// Java's `x / y`: ArithmeticException on a zero divisor, and MIN_VALUE / -1 wraps to MIN_VALUE.
private int javaQuotient()(int x, int y) pure
{
    pragma(inline, inlineDivision);
    if (y == 0)
        throwArithmetic("/ by zero");
    return y == -1 ? -x : x / y;
}

private long javaQuotient()(long x, long y) pure
{
    pragma(inline, inlineDivision);
    if (y == 0)
        throwArithmetic("/ by zero");
    return y == -1 ? -x : x / y;
}

// Java's `x % y`: ArithmeticException on a zero divisor, and MIN_VALUE % -1 is 0.
private int javaRemainder()(int x, int y) pure
{
    pragma(inline, inlineDivision);
    if (y == 0)
        throwArithmetic("/ by zero");
    return y == -1 ? 0 : x % y;
}

private long javaRemainder()(long x, long y) pure
{
    pragma(inline, inlineDivision);
    if (y == 0)
        throwArithmetic("/ by zero");
    return y == -1 ? 0 : x % y;
}

// Java's `min + " > " + max` for the integral clamp overloads.
private noreturn throwClampRange()(long min, long max) pure
{
    import flint.java.lang : IllegalArgumentException;

    char[43] text = void;
    size_t at = text.length;
    const long[2] values = [max, min];
    foreach (i, value; values)
    {
        ulong magnitude = value < 0 ? -cast(ulong) value : cast(ulong) value;
        do
        {
            text[--at] = cast(char)('0' + magnitude % 10);
            magnitude /= 10;
        }
        while (magnitude != 0);
        if (value < 0)
            text[--at] = '-';
        if (i == 0)
        {
            at -= 3;
            text[at .. at + 3] = " > ";
        }
    }
    throw new IllegalArgumentException(text[at .. $].idup);
}

// Java's `IllegalArgumentException(message)` for the floating-point clamp overloads.
private noreturn throwIllegalArgument()(string message) pure
{
    import flint.java.lang : IllegalArgumentException;

    throw new IllegalArgumentException(message);
}

// Java's `min + " > " + max` for clamp(double, double, double).
private noreturn throwFloatingClampRange()(double min, double max) pure
{
    import flint.serde.java_number : javaDoubleString;

    throwIllegalArgument(javaDoubleString(min) ~ " > " ~ javaDoubleString(max));
}

// Java's `min + " > " + max` for clamp(float, float, float).
private noreturn throwFloatingClampRange()(float min, float max) pure
{
    import flint.serde.java_number : javaFloatString;

    throwIllegalArgument(javaFloatString(min) ~ " > " ~ javaFloatString(max));
}

/++
Java's `java.lang.Math` pure numeric constants, IEEE-754 operations and exact integer arithmetic.

The `*Exact`, `floorDiv`/`floorMod`, `ceilDiv`/`ceilMod` and `clamp` members throw Java's
`ArithmeticException` or `IllegalArgumentException`, so they are `pure` but neither `nothrow` nor `@nogc`. They are
zero-parameter templates, so only a program that calls one links the `flint.java.lang` exception hierarchy. A zero
divisor throws `ArithmeticException("/ by zero")` as Java's `/` does, and `MIN_VALUE / -1` wraps as in Java instead
of trapping.

The members that read IEEE-754 bits (`ceil`, `floor`, `rint`, `round`, `abs(float)`, `abs(double)`, `ulp`,
`signum`, `copySign`, `getExponent`, `nextAfter`, `nextUp`, `nextDown` and `scalb`) cannot run in CTFE, because D
rejects reinterpreting a union field at compile time. A compile-time call fails to compile; it never folds at
`real` precision and returns a result that differs from Java.
+/
struct Math
{
    @disable this();

    /// The `double` value closer than any other to *e*.
    enum double E = 2.718281828459045;

    /// The `double` value closer than any other to *pi*.
    enum double PI = 3.141592653589793;

    /// The `double` value closer than any other to *tau* (`2.0 * PI`).
    enum double TAU = 2.0 * PI;

    /// Convert an angle in degrees to radians.
    static double toRadians(double angdeg) pure nothrow @nogc
    {
        return angdeg * DEGREES_TO_RADIANS;
    }

    /// Convert an angle in radians to degrees.
    static double toDegrees(double angrad) pure nothrow @nogc
    {
        return angrad * RADIANS_TO_DEGREES;
    }

    /// Smallest integer-valued `double` >= `a`, preserving signed zero, infinity, and NaN.
    static double ceil(double a) pure nothrow @nogc
    {
        return floorOrCeil(a, -0.0, 1.0, 1.0);
    }

    /// Largest integer-valued `double` <= `a`, preserving signed zero, infinity, and NaN.
    static double floor(double a) pure nothrow @nogc
    {
        return floorOrCeil(a, -1.0, 0.0, -1.0);
    }

    /// Closest integer-valued `double` to `a`, with ties rounding to even.
    static double rint(double a) pure nothrow @nogc
    {
        const sign = copySign(1.0, a);
        double mag = abs(a);
        if (mag < TWO_TO_THE_52)
            mag = (TWO_TO_THE_52 + mag) - TWO_TO_THE_52;
        return sign * mag;
    }

    /// Closest `int` to `a`, with ties rounding toward positive infinity and Java saturation.
    static int round(float a) pure nothrow @nogc
    {
        const intBits = floatToRawIntBits(a);
        const biasedExp = (intBits & FLOAT_EXP_BIT_MASK) >> (FLOAT_SIGNIFICAND_WIDTH - 1);
        const shift = (FLOAT_SIGNIFICAND_WIDTH - 2 + FLOAT_EXP_BIAS) - biasedExp;
        if ((shift & -32) == 0)
        {
            int r = (intBits & FLOAT_SIGNIF_BIT_MASK) | (FLOAT_SIGNIF_BIT_MASK + 1);
            if (intBits < 0)
                r = -r;
            return ((r >> shift) + 1) >> 1;
        }
        if (a != a)
            return 0;
        if (a >= 0x1p31f)
            return int.max;
        if (a <= -0x1p31f)
            return int.min;
        return cast(int) a;
    }

    /// Closest `long` to `a`, with ties rounding toward positive infinity and Java saturation.
    static long round(double a) pure nothrow @nogc
    {
        const longBits = doubleToRawLongBits(a);
        const biasedExp = (longBits & DOUBLE_EXP_BIT_MASK) >> (DOUBLE_SIGNIFICAND_WIDTH - 1);
        const shift = (DOUBLE_SIGNIFICAND_WIDTH - 2 + DOUBLE_EXP_BIAS) - biasedExp;
        if ((shift & -64L) == 0)
        {
            long r = (longBits & DOUBLE_SIGNIF_BIT_MASK) | (DOUBLE_SIGNIF_BIT_MASK + 1);
            if (longBits < 0)
                r = -r;
            return ((r >> cast(int) shift) + 1) >> 1;
        }
        if (a != a)
            return 0;
        if (a >= 0x1p63)
            return long.max;
        if (a <= -0x1p63)
            return long.min;
        return cast(long) a;
    }

    /// `x + y`; throws `ArithmeticException` if the `int` result overflows.
    static int addExact()(int x, int y) pure
    {
        const int r = x + y;
        if (((x ^ r) & (y ^ r)) < 0)
            throwArithmetic("integer overflow");
        return r;
    }

    /// `x + y`; throws `ArithmeticException` if the `long` result overflows.
    static long addExact()(long x, long y) pure
    {
        const long r = x + y;
        if (((x ^ r) & (y ^ r)) < 0)
            throwArithmetic("long overflow");
        return r;
    }

    /// `x - y`; throws `ArithmeticException` if the `int` result overflows.
    static int subtractExact()(int x, int y) pure
    {
        const int r = x - y;
        if (((x ^ y) & (x ^ r)) < 0)
            throwArithmetic("integer overflow");
        return r;
    }

    /// `x - y`; throws `ArithmeticException` if the `long` result overflows.
    static long subtractExact()(long x, long y) pure
    {
        const long r = x - y;
        if (((x ^ y) & (x ^ r)) < 0)
            throwArithmetic("long overflow");
        return r;
    }

    /// `x * y`; throws `ArithmeticException` if the `int` result overflows.
    static int multiplyExact()(int x, int y) pure
    {
        const long r = cast(long) x * cast(long) y;
        if (cast(int) r != r)
            throwArithmetic("integer overflow");
        return cast(int) r;
    }

    /// `x * y`; throws `ArithmeticException` if the `long` result overflows.
    static long multiplyExact()(long x, int y) pure
    {
        return multiplyExact(x, cast(long) y);
    }

    /// `x * y`; throws `ArithmeticException` if the `long` result overflows.
    static long multiplyExact()(long x, long y) pure
    {
        const long r = x * y;
        const long ax = abs(x);
        const long ay = abs(y);
        if (((ax | ay) >>> 31) != 0)
        {
            if ((y != 0 && javaQuotient(r, y) != x) || (x == long.min && y == -1))
                throwArithmetic("long overflow");
        }
        return r;
    }

    /// `x / y` truncated; throws `ArithmeticException` on a zero divisor or for `int.min / -1`.
    static int divideExact()(int x, int y) pure
    {
        const int q = javaQuotient(x, y);
        if ((x & y & q) >= 0)
            return q;
        throwArithmetic("integer overflow");
    }

    /// `x / y` truncated; throws `ArithmeticException` on a zero divisor or for `long.min / -1`.
    static long divideExact()(long x, long y) pure
    {
        const long q = javaQuotient(x, y);
        if ((x & y & q) >= 0)
            return q;
        throwArithmetic("long overflow");
    }

    /// Floor of `x / y`; throws `ArithmeticException` on a zero divisor or for `int.min / -1`.
    static int floorDivExact()(int x, int y) pure
    {
        const int q = javaQuotient(x, y);
        if ((x & y & q) >= 0)
        {
            if ((x ^ y) < 0 && q * y != x)
                return q - 1;
            return q;
        }
        throwArithmetic("integer overflow");
    }

    /// Floor of `x / y`; throws `ArithmeticException` on a zero divisor or for `long.min / -1`.
    static long floorDivExact()(long x, long y) pure
    {
        const long q = javaQuotient(x, y);
        if ((x & y & q) >= 0)
        {
            if ((x ^ y) < 0 && q * y != x)
                return q - 1;
            return q;
        }
        throwArithmetic("long overflow");
    }

    /// Ceiling of `x / y`; throws `ArithmeticException` on a zero divisor or for `int.min / -1`.
    static int ceilDivExact()(int x, int y) pure
    {
        const int q = javaQuotient(x, y);
        if ((x & y & q) >= 0)
        {
            if ((x ^ y) >= 0 && q * y != x)
                return q + 1;
            return q;
        }
        throwArithmetic("integer overflow");
    }

    /// Ceiling of `x / y`; throws `ArithmeticException` on a zero divisor or for `long.min / -1`.
    static long ceilDivExact()(long x, long y) pure
    {
        const long q = javaQuotient(x, y);
        if ((x & y & q) >= 0)
        {
            if ((x ^ y) >= 0 && q * y != x)
                return q + 1;
            return q;
        }
        throwArithmetic("long overflow");
    }

    /// `a + 1`; throws `ArithmeticException` for `int.max`.
    static int incrementExact()(int a) pure
    {
        if (a == int.max)
            throwArithmetic("integer overflow");
        return a + 1;
    }

    /// `a + 1`; throws `ArithmeticException` for `long.max`.
    static long incrementExact()(long a) pure
    {
        if (a == long.max)
            throwArithmetic("long overflow");
        return a + 1L;
    }

    /// `a - 1`; throws `ArithmeticException` for `int.min`.
    static int decrementExact()(int a) pure
    {
        if (a == int.min)
            throwArithmetic("integer overflow");
        return a - 1;
    }

    /// `a - 1`; throws `ArithmeticException` for `long.min`.
    static long decrementExact()(long a) pure
    {
        if (a == long.min)
            throwArithmetic("long overflow");
        return a - 1L;
    }

    /// `-a`; throws `ArithmeticException` for `int.min`.
    static int negateExact()(int a) pure
    {
        if (a == int.min)
            throwArithmetic("integer overflow");
        return -a;
    }

    /// `-a`; throws `ArithmeticException` for `long.min`.
    static long negateExact()(long a) pure
    {
        if (a == long.min)
            throwArithmetic("long overflow");
        return -a;
    }

    /// `value` as an `int`; throws `ArithmeticException` if it does not fit.
    static int toIntExact()(long value) pure
    {
        if (cast(int) value != value)
            throwArithmetic("integer overflow");
        return cast(int) value;
    }

    /// Exact 64-bit product of two 32-bit signed integers.
    static long multiplyFull(int x, int y) pure nothrow @nogc
    {
        return cast(long) x * cast(long) y;
    }

    /// Most significant 64 bits of the signed 128-bit product of `x` and `y`.
    static long multiplyHigh(long x, long y) pure nothrow @nogc
    {
        const long x1 = x >> 32;
        const long x2 = x & 0xFFFF_FFFFL;
        const long y1 = y >> 32;
        const long y2 = y & 0xFFFF_FFFFL;

        const long z2 = x2 * y2;
        const long t = x1 * y2 + (z2 >>> 32);
        long z1 = t & 0xFFFF_FFFFL;
        const long z0 = t >> 32;
        z1 += x2 * y1;

        return x1 * y1 + z0 + (z1 >> 32);
    }

    /// Most significant 64 bits of the unsigned 128-bit product of `x` and `y`.
    static long unsignedMultiplyHigh(long x, long y) pure nothrow @nogc
    {
        long result = multiplyHigh(x, y);
        result += y & (x >> 63);
        result += x & (y >> 63);
        return result;
    }

    /// Largest `int` not greater than `x / y`; `int.min / -1` is `int.min`. Throws `ArithmeticException` if `y` is 0.
    static int floorDiv()(int x, int y) pure
    {
        const int q = javaQuotient(x, y);
        if ((x ^ y) < 0 && q * y != x)
            return q - 1;
        return q;
    }

    /// Largest `long` not greater than `x / y`. Throws `ArithmeticException` if `y` is 0.
    static long floorDiv()(long x, int y) pure
    {
        return floorDiv(x, cast(long) y);
    }

    /// Largest `long` not greater than `x / y`; `long.min / -1` is `long.min`. Throws `ArithmeticException` if `y` is 0.
    static long floorDiv()(long x, long y) pure
    {
        const long q = javaQuotient(x, y);
        if ((x ^ y) < 0 && q * y != x)
            return q - 1;
        return q;
    }

    /// `x - floorDiv(x, y) * y`, with the sign of `y`. Throws `ArithmeticException` if `y` is 0.
    static int floorMod()(int x, int y) pure
    {
        const int r = javaRemainder(x, y);
        if ((x ^ y) < 0 && r != 0)
            return r + y;
        return r;
    }

    /// `x - floorDiv(x, y) * y`, with the sign of `y`. Throws `ArithmeticException` if `y` is 0.
    static int floorMod()(long x, int y) pure
    {
        return cast(int) floorMod(x, cast(long) y);
    }

    /// `x - floorDiv(x, y) * y`, with the sign of `y`. Throws `ArithmeticException` if `y` is 0.
    static long floorMod()(long x, long y) pure
    {
        const long r = javaRemainder(x, y);
        if ((x ^ y) < 0 && r != 0)
            return r + y;
        return r;
    }

    /// Smallest `int` not less than `x / y`; `int.min / -1` is `int.min`. Throws `ArithmeticException` if `y` is 0.
    static int ceilDiv()(int x, int y) pure
    {
        const int q = javaQuotient(x, y);
        if ((x ^ y) >= 0 && q * y != x)
            return q + 1;
        return q;
    }

    /// Smallest `long` not less than `x / y`. Throws `ArithmeticException` if `y` is 0.
    static long ceilDiv()(long x, int y) pure
    {
        return ceilDiv(x, cast(long) y);
    }

    /// Smallest `long` not less than `x / y`; `long.min / -1` is `long.min`. Throws `ArithmeticException` if `y` is 0.
    static long ceilDiv()(long x, long y) pure
    {
        const long q = javaQuotient(x, y);
        if ((x ^ y) >= 0 && q * y != x)
            return q + 1;
        return q;
    }

    /// `x - ceilDiv(x, y) * y`, with the opposite sign of `y`. Throws `ArithmeticException` if `y` is 0.
    static int ceilMod()(int x, int y) pure
    {
        const int r = javaRemainder(x, y);
        if ((x ^ y) >= 0 && r != 0)
            return r - y;
        return r;
    }

    /// `x - ceilDiv(x, y) * y`, with the opposite sign of `y`. Throws `ArithmeticException` if `y` is 0.
    static int ceilMod()(long x, int y) pure
    {
        return cast(int) ceilMod(x, cast(long) y);
    }

    /// `x - ceilDiv(x, y) * y`, with the opposite sign of `y`. Throws `ArithmeticException` if `y` is 0.
    static long ceilMod()(long x, long y) pure
    {
        const long r = javaRemainder(x, y);
        if ((x ^ y) >= 0 && r != 0)
            return r - y;
        return r;
    }

    /// Absolute value of an `int` (`int.min` returns `int.min`).
    static int abs(int a) pure nothrow @nogc
    {
        return a < 0 ? -a : a;
    }

    /// Absolute value of a `long` (`long.min` returns `long.min`).
    static long abs(long a) pure nothrow @nogc
    {
        return a < 0 ? -a : a;
    }

    /// Absolute value of an `int`; throws `ArithmeticException` for `int.min`.
    static int absExact()(int a) pure
    {
        if (a == int.min)
            throwArithmetic("Overflow to represent absolute value of Integer.MIN_VALUE");
        return abs(a);
    }

    /// Absolute value of a `long`; throws `ArithmeticException` for `long.min`.
    static long absExact()(long a) pure
    {
        if (a == long.min)
            throwArithmetic("Overflow to represent absolute value of Long.MIN_VALUE");
        return abs(a);
    }

    /// Absolute value of a `float` (clears the sign bit).
    static float abs(float a) pure nothrow @nogc
    {
        return intBitsToFloat(floatToRawIntBits(a) & FLOAT_MAG_BIT_MASK);
    }

    /// Absolute value of a `double` (clears the sign bit).
    static double abs(double a) pure nothrow @nogc
    {
        return longBitsToDouble(doubleToRawLongBits(a) & DOUBLE_MAG_BIT_MASK);
    }

    /// Greater of two `int` values.
    static int max(int a, int b) pure nothrow @nogc
    {
        return a >= b ? a : b;
    }

    /// Greater of two `long` values.
    static long max(long a, long b) pure nothrow @nogc
    {
        return a >= b ? a : b;
    }

    /// Greater of two `float` values (`+0.0f > -0.0f`, propagates NaN).
    static float max(float a, float b) pure nothrow @nogc
    {
        if (a != a)
            return a;
        if (a == 0.0f && b == 0.0f && floatToRawIntBits(a) == FLOAT_SIGN_BIT_MASK)
            return b;
        return a >= b ? a : b;
    }

    /// Greater of two `double` values (`+0.0 > -0.0`, propagates NaN).
    static double max(double a, double b) pure nothrow @nogc
    {
        if (a != a)
            return a;
        if (a == 0.0 && b == 0.0 && doubleToRawLongBits(a) == DOUBLE_SIGN_BIT_MASK)
            return b;
        return a >= b ? a : b;
    }

    /// Smaller of two `int` values.
    static int min(int a, int b) pure nothrow @nogc
    {
        return a <= b ? a : b;
    }

    /// Smaller of two `long` values.
    static long min(long a, long b) pure nothrow @nogc
    {
        return a <= b ? a : b;
    }

    /// Smaller of two `float` values (`-0.0f < +0.0f`, propagates NaN).
    static float min(float a, float b) pure nothrow @nogc
    {
        if (a != a)
            return a;
        if (a == 0.0f && b == 0.0f && floatToRawIntBits(b) == FLOAT_SIGN_BIT_MASK)
            return b;
        return a <= b ? a : b;
    }

    /// Smaller of two `double` values (`-0.0 < +0.0`, propagates NaN).
    static double min(double a, double b) pure nothrow @nogc
    {
        if (a != a)
            return a;
        if (a == 0.0 && b == 0.0 && doubleToRawLongBits(b) == DOUBLE_SIGN_BIT_MASK)
            return b;
        return a <= b ? a : b;
    }

    /// `value` clamped to `[min, max]`; throws `IllegalArgumentException` if `min > max`.
    static int clamp()(long value, int min, int max) pure
    {
        if (min > max)
            throwClampRange(min, max);
        return cast(int) Math.min(cast(long) max, Math.max(value, cast(long) min));
    }

    /// `value` clamped to `[min, max]`; throws `IllegalArgumentException` if `min > max`.
    static long clamp()(long value, long min, long max) pure
    {
        if (min > max)
            throwClampRange(min, max);
        return Math.min(max, Math.max(value, min));
    }

    /// `value` clamped to `[min, max]`; throws `IllegalArgumentException` if `min` or `max` is NaN or `min > max`.
    static double clamp()(double value, double min, double max) pure
    {
        // Java's single-branch common path: !(min < max) also catches NaN and the equal-bounds cases.
        if (!(min < max))
        {
            if (min != min)
                throwIllegalArgument("min is NaN");
            if (max != max)
                throwIllegalArgument("max is NaN");
            // Double.compare(min, max) > 0: min > max, or min is +0.0 and max is -0.0.
            if (min > max || (doubleToRawLongBits(min) == 0 && doubleToRawLongBits(max) == DOUBLE_SIGN_BIT_MASK))
                throwFloatingClampRange(min, max);
        }
        return Math.min(max, Math.max(value, min));
    }

    /// `value` clamped to `[min, max]`; throws `IllegalArgumentException` if `min` or `max` is NaN or `min > max`.
    static float clamp()(float value, float min, float max) pure
    {
        if (!(min < max))
        {
            if (min != min)
                throwIllegalArgument("min is NaN");
            if (max != max)
                throwIllegalArgument("max is NaN");
            // Float.compare(min, max) > 0: min > max, or min is +0.0f and max is -0.0f.
            if (min > max || (floatToRawIntBits(min) == 0 && floatToRawIntBits(max) == FLOAT_SIGN_BIT_MASK))
                throwFloatingClampRange(min, max);
        }
        return Math.min(max, Math.max(value, min));
    }

    /// Size of an ulp (unit in the last place) of `d`.
    static double ulp(double d) pure nothrow @nogc
    {
        int exp = getExponent(d);
        if (exp == DOUBLE_MAX_EXPONENT + 1)
            return abs(d);
        if (exp == DOUBLE_MIN_EXPONENT - 1)
            return DOUBLE_MIN_VALUE;

        exp -= DOUBLE_SIGNIFICAND_WIDTH - 1;
        if (exp >= DOUBLE_MIN_EXPONENT)
            return powerOfTwoD(exp);
        return longBitsToDouble(1L << (exp - (DOUBLE_MIN_EXPONENT - (DOUBLE_SIGNIFICAND_WIDTH - 1))));
    }

    /// Size of an ulp (unit in the last place) of `f`.
    static float ulp(float f) pure nothrow @nogc
    {
        int exp = getExponent(f);
        if (exp == FLOAT_MAX_EXPONENT + 1)
            return abs(f);
        if (exp == FLOAT_MIN_EXPONENT - 1)
            return FLOAT_MIN_VALUE;

        exp -= FLOAT_SIGNIFICAND_WIDTH - 1;
        if (exp >= FLOAT_MIN_EXPONENT)
            return powerOfTwoF(exp);
        return intBitsToFloat(1 << (exp - (FLOAT_MIN_EXPONENT - (FLOAT_SIGNIFICAND_WIDTH - 1))));
    }

    /// Signum function of `d` (`±0.0` and `NaN` preserved).
    static double signum(double d) pure nothrow @nogc
    {
        return (d == 0.0 || d != d) ? d : copySign(1.0, d);
    }

    /// Signum function of `f` (`±0.0f` and `NaN` preserved).
    static float signum(float f) pure nothrow @nogc
    {
        return (f == 0.0f || f != f) ? f : copySign(1.0f, f);
    }

    /// First argument with the sign bit of the second argument.
    static double copySign(double magnitude, double sign) pure nothrow @nogc
    {
        return longBitsToDouble((doubleToRawLongBits(sign) & DOUBLE_SIGN_BIT_MASK) | (
                doubleToRawLongBits(magnitude) & DOUBLE_MAG_BIT_MASK));
    }

    /// First argument with the sign bit of the second argument.
    static float copySign(float magnitude, float sign) pure nothrow @nogc
    {
        return intBitsToFloat((floatToRawIntBits(sign) & FLOAT_SIGN_BIT_MASK) | (
                floatToRawIntBits(magnitude) & FLOAT_MAG_BIT_MASK));
    }

    /// Unbiased exponent of `f` (`-127` for zero/subnormal, `128` for infinity/NaN).
    static int getExponent(float f) pure nothrow @nogc
    {
        return ((floatToRawIntBits(f) & FLOAT_EXP_BIT_MASK) >> (FLOAT_SIGNIFICAND_WIDTH - 1)) - FLOAT_EXP_BIAS;
    }

    /// Unbiased exponent of `d` (`-1023` for zero/subnormal, `1024` for infinity/NaN).
    static int getExponent(double d) pure nothrow @nogc
    {
        return cast(int)(
                ((doubleToRawLongBits(d) & DOUBLE_EXP_BIT_MASK) >> (DOUBLE_SIGNIFICAND_WIDTH - 1)) - DOUBLE_EXP_BIAS);
    }

    /// Adjacent `double` to `start` in the direction of `direction`.
    static double nextAfter(double start, double direction) pure nothrow @nogc
    {
        if (start > direction)
        {
            if (start != 0.0)
            {
                const transducer = doubleToRawLongBits(start);
                return longBitsToDouble(transducer + (transducer > 0L ? -1L : 1L));
            }
            return -DOUBLE_MIN_VALUE;
        }
        if (start < direction)
        {
            const transducer = doubleToRawLongBits(start + 0.0);
            return longBitsToDouble(transducer + (transducer >= 0L ? 1L : -1L));
        }
        if (start == direction)
            return direction;
        return start + direction;
    }

    /// Adjacent `float` to `start` in the direction of `direction`.
    static float nextAfter(float start, double direction) pure nothrow @nogc
    {
        if (start > direction)
        {
            if (start != 0.0f)
            {
                const transducer = floatToRawIntBits(start);
                return intBitsToFloat(transducer + (transducer > 0 ? -1 : 1));
            }
            return -FLOAT_MIN_VALUE;
        }
        if (start < direction)
        {
            const transducer = floatToRawIntBits(start + 0.0f);
            return intBitsToFloat(transducer + (transducer >= 0 ? 1 : -1));
        }
        if (start == direction)
            return cast(float) direction;
        return start + cast(float) direction;
    }

    /// Adjacent `double` toward positive infinity.
    static double nextUp(double d) pure nothrow @nogc
    {
        if (d < double.infinity)
        {
            const transducer = doubleToRawLongBits(d + 0.0);
            return longBitsToDouble(transducer + (transducer >= 0L ? 1L : -1L));
        }
        return d;
    }

    /// Adjacent `float` toward positive infinity.
    static float nextUp(float f) pure nothrow @nogc
    {
        if (f < float.infinity)
        {
            const transducer = floatToRawIntBits(f + 0.0f);
            return intBitsToFloat(transducer + (transducer >= 0 ? 1 : -1));
        }
        return f;
    }

    /// Adjacent `double` toward negative infinity.
    static double nextDown(double d) pure nothrow @nogc
    {
        if (d != d || d == -double.infinity)
            return d;
        if (d == 0.0)
            return -DOUBLE_MIN_VALUE;
        return longBitsToDouble(doubleToRawLongBits(d) + (d > 0.0 ? -1L : 1L));
    }

    /// Adjacent `float` toward negative infinity.
    static float nextDown(float f) pure nothrow @nogc
    {
        if (f != f || f == -float.infinity)
            return f;
        if (f == 0.0f)
            return -FLOAT_MIN_VALUE;
        return intBitsToFloat(floatToRawIntBits(f) + (f > 0.0f ? -1 : 1));
    }

    /// Compute `d * 2^scaleFactor` rounded as if by a single correctly rounded multiply.
    static double scalb(double d, int scaleFactor) pure nothrow @nogc
    {
        enum int MAX_SCALE = DOUBLE_MAX_EXPONENT + -DOUBLE_MIN_EXPONENT + DOUBLE_SIGNIFICAND_WIDTH + 1;
        int scaleIncrement;
        double expDelta;

        if (scaleFactor < 0)
        {
            scaleFactor = max(scaleFactor, -MAX_SCALE);
            scaleIncrement = -512;
            expDelta = TWO_TO_THE_DOUBLE_SCALE_DOWN;
        }
        else
        {
            scaleFactor = min(scaleFactor, MAX_SCALE);
            scaleIncrement = 512;
            expDelta = TWO_TO_THE_DOUBLE_SCALE_UP;
        }

        const int t = (scaleFactor >> 8) >>> 23;
        const int expAdjust = ((scaleFactor + t) & 511) - t;

        d *= powerOfTwoD(expAdjust);
        scaleFactor -= expAdjust;

        while (scaleFactor != 0)
        {
            d *= expDelta;
            scaleFactor -= scaleIncrement;
        }
        return d;
    }

    /// Compute `f * 2^scaleFactor` rounded as if by a single correctly rounded multiply.
    static float scalb(float f, int scaleFactor) pure nothrow @nogc
    {
        enum int MAX_SCALE = FLOAT_MAX_EXPONENT + -FLOAT_MIN_EXPONENT + FLOAT_SIGNIFICAND_WIDTH + 1;
        scaleFactor = max(min(scaleFactor, MAX_SCALE), -MAX_SCALE);
        return cast(float)(cast(double) f * powerOfTwoD(scaleFactor));
    }
}
