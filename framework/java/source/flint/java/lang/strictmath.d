/*
 * Copyright (c) 1999, 2023, Oracle and/or its affiliates. All rights reserved.
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

// Ported from openjdk 21.0.13: src/java.base/share/classes/java/lang/StrictMath.java
// Modified by the Flint authors: thin zero-aggregate leaf delegating the 20 FDLIBM methods
// directly to flint.java.internal.fdlibm via zero-parameter templates and aliasing the 78
// exact/IEEE methods to flint.java.lang.math.Math (whose floor, ceil and rint are ported
// directly from StrictMath.java and whose throwing exact/clamp methods import flint.java.lang
// lazily). StrictMath.random() is deferred until Random wiring lands.

module flint.java.lang.strictmath;

import flint.java.lang.math : Math;

@safe:

/+
Java 21 `java.lang.StrictMath` deterministic surface as a thin zero-aggregate leaf.

The 20 transcendental and remainder methods delegate directly to `flint.java.internal.fdlibm`
(a bit-exact port of OpenJDK 21.0.13 `FdLibm.java`). The remaining 78 deterministic methods
alias `flint.java.lang.math.Math`, preserving `pure nothrow @nogc` on the IEEE-754 core and
lazy exception imports on the throwing exact/clamp family without duplicating code or templates.
+/
struct StrictMath
{
    @disable this();

    /// The `double` value closer than any other to *e*.
    enum double E = 2.718281828459045;

    /// The `double` value closer than any other to *pi*.
    enum double PI = 3.141592653589793;

    /// The `double` value closer than any other to *tau* (`2.0 * PI`).
    enum double TAU = 2.0 * PI;

    /// Convert an angle in degrees to radians.
    alias toRadians = Math.toRadians;

    /// Convert an angle in radians to degrees.
    alias toDegrees = Math.toDegrees;

    /// Smallest integer-valued `double` >= `a`, preserving signed zero, infinity, and NaN.
    alias ceil = Math.ceil;

    /// Largest integer-valued `double` <= `a`, preserving signed zero, infinity, and NaN.
    alias floor = Math.floor;

    /// Closest integer-valued `double` to `a`, with ties rounding to even.
    alias rint = Math.rint;

    /// Closest `int`/`long` to `a`, with ties rounding toward positive infinity and Java saturation.
    alias round = Math.round;

    /// `x + y`; throws `ArithmeticException` on overflow.
    alias addExact = Math.addExact;

    /// `x - y`; throws `ArithmeticException` on overflow.
    alias subtractExact = Math.subtractExact;

    /// `x * y`; throws `ArithmeticException` on overflow.
    alias multiplyExact = Math.multiplyExact;

    /// `x / y` truncated; throws `ArithmeticException` on zero divisor or `MIN_VALUE / -1`.
    alias divideExact = Math.divideExact;

    /// Floor of `x / y`; throws `ArithmeticException` on zero divisor or `MIN_VALUE / -1`.
    alias floorDivExact = Math.floorDivExact;

    /// Ceiling of `x / y`; throws `ArithmeticException` on zero divisor or `MIN_VALUE / -1`.
    alias ceilDivExact = Math.ceilDivExact;

    /// `a + 1`; throws `ArithmeticException` on overflow.
    alias incrementExact = Math.incrementExact;

    /// `a - 1`; throws `ArithmeticException` on overflow.
    alias decrementExact = Math.decrementExact;

    /// `-a`; throws `ArithmeticException` on `MIN_VALUE`.
    alias negateExact = Math.negateExact;

    /// `value` as an `int`; throws `ArithmeticException` if it does not fit.
    alias toIntExact = Math.toIntExact;

    /// Exact 64-bit product of two 32-bit signed integers.
    alias multiplyFull = Math.multiplyFull;

    /// Most significant 64 bits of the signed 128-bit product of `x` and `y`.
    alias multiplyHigh = Math.multiplyHigh;

    /// Most significant 64 bits of the unsigned 128-bit product of `x` and `y`.
    alias unsignedMultiplyHigh = Math.unsignedMultiplyHigh;

    /// Largest integer not greater than `x / y`; throws `ArithmeticException` if `y` is 0.
    alias floorDiv = Math.floorDiv;

    /// `x - floorDiv(x, y) * y`, with the sign of `y`; throws `ArithmeticException` if `y` is 0.
    alias floorMod = Math.floorMod;

    /// Smallest integer not less than `x / y`; throws `ArithmeticException` if `y` is 0.
    alias ceilDiv = Math.ceilDiv;

    /// `x - ceilDiv(x, y) * y`, with the opposite sign of `y`; throws `ArithmeticException` if `y` is 0.
    alias ceilMod = Math.ceilMod;

    /// Absolute value of an `int`, `long`, `float`, or `double`.
    alias abs = Math.abs;

    /// Absolute value of an `int` or `long`; throws `ArithmeticException` for `MIN_VALUE`.
    alias absExact = Math.absExact;

    /// Greater of two `int`, `long`, `float`, or `double` values.
    alias max = Math.max;

    /// Smaller of two `int`, `long`, `float`, or `double` values.
    alias min = Math.min;

    /// `value` clamped to `[min, max]`; throws `IllegalArgumentException` if bounds are invalid.
    alias clamp = Math.clamp;

    /// `a * b + c` with a single IEEE-754 rounding.
    alias fma = Math.fma;

    /// Size of an ulp (unit in the last place) of `d` or `f`.
    alias ulp = Math.ulp;

    /// Signum function of `d` or `f` (`±0.0` and `NaN` preserved).
    alias signum = Math.signum;

    /// First argument with the sign bit of the second argument (NaN sign is always treated as positive).
    static double copySign(double magnitude, double sign) pure nothrow @nogc
    {
        return Math.copySign(magnitude, sign != sign ? 1.0 : sign);
    }

    /// First argument with the sign bit of the second argument (NaN sign is always treated as positive).
    static float copySign(float magnitude, float sign) pure nothrow @nogc
    {
        return Math.copySign(magnitude, sign != sign ? 1.0f : sign);
    }

    /// Unbiased exponent of `f` or `d`.
    alias getExponent = Math.getExponent;

    /// Adjacent floating-point value to `start` in the direction of `direction`.
    alias nextAfter = Math.nextAfter;

    /// Adjacent floating-point value toward positive infinity.
    alias nextUp = Math.nextUp;

    /// Adjacent floating-point value toward negative infinity.
    alias nextDown = Math.nextDown;

    /// Compute `x * 2^scaleFactor` rounded as if by a single correctly rounded multiply.
    alias scalb = Math.scalb;

    /// Trigonometric sine of angle `a` in radians (FDLIBM).
    static double sin()(double a) pure nothrow @nogc
    {
        import flint.java.internal.fdlibm : fdSin;

        return fdSin(a);
    }

    /// Trigonometric cosine of angle `a` in radians (FDLIBM).
    static double cos()(double a) pure nothrow @nogc
    {
        import flint.java.internal.fdlibm : fdCos;

        return fdCos(a);
    }

    /// Trigonometric tangent of angle `a` in radians (FDLIBM).
    static double tan()(double a) pure nothrow @nogc
    {
        import flint.java.internal.fdlibm : fdTan;

        return fdTan(a);
    }

    /// Arc sine of `a` in `[-pi/2, pi/2]` (FDLIBM).
    static double asin()(double a) pure nothrow @nogc
    {
        import flint.java.internal.fdlibm : fdAsin;

        return fdAsin(a);
    }

    /// Arc cosine of `a` in `[0, pi]` (FDLIBM).
    static double acos()(double a) pure nothrow @nogc
    {
        import flint.java.internal.fdlibm : fdAcos;

        return fdAcos(a);
    }

    /// Arc tangent of `a` in `[-pi/2, pi/2]` (FDLIBM).
    static double atan()(double a) pure nothrow @nogc
    {
        import flint.java.internal.fdlibm : fdAtan;

        return fdAtan(a);
    }

    /// Euler's number `e` raised to the power of `a` (FDLIBM).
    static double exp()(double a) pure nothrow @nogc
    {
        import flint.java.internal.fdlibm : fdExp;

        return fdExp(a);
    }

    /// Natural logarithm (base `e`) of `a` (FDLIBM).
    static double log()(double a) pure nothrow @nogc
    {
        import flint.java.internal.fdlibm : fdLog;

        return fdLog(a);
    }

    /// Base-10 logarithm of `a` (FDLIBM).
    static double log10()(double a) pure nothrow @nogc
    {
        import flint.java.internal.fdlibm : fdLog10;

        return fdLog10(a);
    }

    /// Correctly rounded positive square root of `a` (FDLIBM).
    static double sqrt()(double a) pure nothrow @nogc
    {
        import flint.java.internal.fdlibm : fdSqrt;

        return fdSqrt(a);
    }

    /// Cube root of `a` (FDLIBM).
    static double cbrt()(double a) pure nothrow @nogc
    {
        import flint.java.internal.fdlibm : fdCbrt;

        return fdCbrt(a);
    }

    private static double ieeeRemainderImpl()(double f1, double f2) pure nothrow @nogc
    {
        import flint.java.internal.fdlibm : fdIEEEremainder;

        return fdIEEEremainder(f1, f2);
    }

    /// IEEE-754 remainder of `f1` divided by `f2` (FDLIBM).
    alias IEEEremainder = ieeeRemainderImpl;

    /// Polar angle `theta` in `[-pi, pi]` for rectangular coordinates `(x, y)` (FDLIBM).
    static double atan2()(double y, double x) pure nothrow @nogc
    {
        import flint.java.internal.fdlibm : fdAtan2;

        return fdAtan2(y, x);
    }

    /// `a` raised to the power of `b` (FDLIBM).
    static double pow()(double a, double b) pure nothrow @nogc
    {
        import flint.java.internal.fdlibm : fdPow;

        return fdPow(a, b);
    }

    /// Hyperbolic sine of `x` (FDLIBM).
    static double sinh()(double x) pure nothrow @nogc
    {
        import flint.java.internal.fdlibm : fdSinh;

        return fdSinh(x);
    }

    /// Hyperbolic cosine of `x` (FDLIBM).
    static double cosh()(double x) pure nothrow @nogc
    {
        import flint.java.internal.fdlibm : fdCosh;

        return fdCosh(x);
    }

    /// Hyperbolic tangent of `x` (FDLIBM).
    static double tanh()(double x) pure nothrow @nogc
    {
        import flint.java.internal.fdlibm : fdTanh;

        return fdTanh(x);
    }

    /// `sqrt(x^2 + y^2)` without intermediate overflow or underflow (FDLIBM).
    static double hypot()(double x, double y) pure nothrow @nogc
    {
        import flint.java.internal.fdlibm : fdHypot;

        return fdHypot(x, y);
    }

    /// `e^x - 1` accurate near zero (FDLIBM).
    static double expm1()(double x) pure nothrow @nogc
    {
        import flint.java.internal.fdlibm : fdExpm1;

        return fdExpm1(x);
    }

    /// Natural logarithm of `x + 1` accurate near zero (FDLIBM).
    static double log1p()(double x) pure nothrow @nogc
    {
        import flint.java.internal.fdlibm : fdLog1p;

        return fdLog1p(x);
    }
}
