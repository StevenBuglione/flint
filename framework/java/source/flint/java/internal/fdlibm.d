/*
 * Copyright (c) 1998, 2023, Oracle and/or its affiliates. All rights reserved.
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

// Ported from openjdk 21.0.13: src/java.base/share/classes/java/lang/FdLibm.java
// Modified by the Flint authors: @safe pure nothrow @nogc D implementation of OpenJDK's
// FDLIBM 5.3 routines shared by java.lang.Math and java.lang.StrictMath. Uses explicit
// NaN returns instead of (x - x) / (x - x) to avoid DMD's x - x constant folding, guards
// 32-bit shift counts against undefined 32-bit shifts in D, and uses explicit uint casts
// in place of Integer.compareUnsigned.

module flint.java.internal.fdlibm;

@safe:

private union DoubleBits
{
    double value;
    long bits;
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

private int __LO(double x) pure nothrow @nogc
{
    return cast(int) doubleToRawLongBits(x);
}

private double __LO(double x, int low) pure nothrow @nogc
{
    const long transX = doubleToRawLongBits(x);
    return longBitsToDouble((transX & cast(long) 0xFFFF_FFFF_0000_0000UL) | (cast(long) low & 0x0000_0000_FFFF_FFFFL));
}

private int __HI(double x) pure nothrow @nogc
{
    return cast(int)(doubleToRawLongBits(x) >> 32);
}

private double __HI(double x, int high) pure nothrow @nogc
{
    const long transX = doubleToRawLongBits(x);
    return longBitsToDouble((transX & 0x0000_0000_FFFF_FFFFL) | (cast(long) high << 32));
}

private double __HI_LO(int high, int low) pure nothrow @nogc
{
    return longBitsToDouble((cast(long) high << 32) | (cast(long) low & 0x0000_0000_FFFF_FFFFL));
}

private bool isFinite(double x) pure nothrow @nogc
{
    return (doubleToRawLongBits(x) & 0x7FF0_0000_0000_0000L) != 0x7FF0_0000_0000_0000L;
}

private double absD(double x) pure nothrow @nogc
{
    return longBitsToDouble(doubleToRawLongBits(x) & 0x7FFF_FFFF_FFFF_FFFFL);
}

private double powerOfTwoD(int n) pure nothrow @nogc
{
    return longBitsToDouble(((cast(long) n + 1023L) << 52) & 0x7FF0_0000_0000_0000L);
}

private enum double INFINITY = double.infinity;
private enum double DOUBLE_MIN_NORMAL = 0x1.0p-1022;
private enum int SIGN_BIT = cast(int) 0x8000_0000U;
private enum int EXP_BITS = 0x7ff0_0000;
private enum int EXP_SIGNIF_BITS = 0x7fff_ffff;

private void sqrtNormalizeSubnormal(ref int ix0, ref int ix1, ref int m) pure nothrow @nogc
{
    while (ix0 == 0)
    {
        m -= 21;
        ix0 |= (ix1 >>> 11);
        ix1 <<= 21;
    }
    int i = 0;
    for (; (ix0 & 0x0010_0000) == 0; i++)
        ix0 <<= 1;
    m -= i - 1;
    if (i != 0)
    {
        ix0 |= (ix1 >>> (32 - i));
        ix1 <<= i;
    }
}

private void sqrtLowWord(ref int ix0, ref int ix1, ref int s0, ref int s1, ref int q1) pure nothrow @nogc
{
    enum int sign = SIGN_BIT;
    int r = sign;
    while (r != 0)
    {
        const int t1 = s1 + r;
        const int t = s0;
        if (t < ix0 || (t == ix0 && cast(uint) t1 <= cast(uint) ix1))
        {
            s1 = t1 + r;
            if (((t1 & sign) == sign) && (s1 & sign) == 0)
                s0 += 1;
            ix0 -= t;
            if (cast(uint) ix1 < cast(uint) t1)
                ix0 -= 1;
            ix1 -= t1;
            q1 += r;
        }
        ix0 += ix0 + ((ix1 & sign) >>> 31);
        ix1 += ix1;
        r >>>= 1;
    }
}

/// Bit-exact IEEE-754 square root (`FdLibm.Sqrt.compute`).
package(flint.java) double fdSqrt(double x) pure nothrow @nogc
{
    enum int sign = SIGN_BIT;
    int ix0 = __HI(x);
    int ix1 = __LO(x);

    // Take care of Inf and NaN
    if ((ix0 & EXP_BITS) == EXP_BITS)
    {
        if (x != x || x == INFINITY)
            return x + x; // sqrt(NaN) = quiet NaN, sqrt(+inf) = +inf
        return double.nan; // sqrt(-inf) = NaN
    }
    // Take care of zero and negative numbers
    if (ix0 <= 0)
    {
        if (((ix0 & (~sign)) | ix1) == 0)
            return x; // sqrt(+-0) = +-0
        if (ix0 < 0)
            return double.nan;
    }

    // Normalize x
    int m = ix0 >> 20;
    if (m == 0)
        sqrtNormalizeSubnormal(ix0, ix1, m);
    m -= 1023; // unbias exponent
    ix0 = (ix0 & 0x000f_ffff) | 0x0010_0000;
    if ((m & 1) != 0)
    {
        // Odd m: double x to make it even
        ix0 += ix0 + ((ix1 & sign) >>> 31);
        ix1 += ix1;
    }
    m >>= 1; // m = [m/2]

    // Generate sqrt(x) bit by bit
    ix0 += ix0 + ((ix1 & sign) >>> 31);
    ix1 += ix1;
    int q = 0;
    int q1 = 0;
    int s0 = 0;
    int s1 = 0;
    int r = 0x0020_0000;

    while (r != 0)
    {
        const int t = s0 + r;
        if (t <= ix0)
        {
            s0 = t + r;
            ix0 -= t;
            q += r;
        }
        ix0 += ix0 + ((ix1 & sign) >>> 31);
        ix1 += ix1;
        r >>>= 1;
    }

    sqrtLowWord(ix0, ix1, s0, s1, q1);

    // Round to nearest even (Java's IEEE-754 default rounding mode)
    if ((ix0 | ix1) != 0)
    {
        if (cast(uint) q1 == 0xffff_ffffU)
        {
            q1 = 0;
            q += 1;
        }
        else
        {
            q1 += (q1 & 1);
        }
    }

    ix0 = (q >> 1) + 0x3fe0_0000;
    ix1 = q1 >>> 1;
    if ((q & 1) == 1)
        ix1 |= sign;
    ix0 += (m << 20);
    return __HI_LO(ix0, ix1);
}

/// Bit-exact FDLIBM cube root (`FdLibm.Cbrt.compute`).
package(flint.java) double fdCbrt(double x) pure nothrow @nogc
{
    enum int B1 = 715_094_163;
    enum int B2 = 696_219_795;
    enum double C = 0x1.15f15f15f15f1p-1;
    enum double D = -0x1.691de2532c834p-1;
    enum double E = 0x1.6a0ea0ea0ea0fp0;
    enum double F = 0x1.9b6db6db6db6ep0;
    enum double G = 0x1.6db6db6db6db7p-2;

    if (x == 0.0 || !isFinite(x))
        return x;

    const double sign = x < 0.0 ? -1.0 : 1.0;
    x = absD(x);

    double t = 0.0;
    if (x < 0x1.0p-1022)
    {
        t = 0x1.0p54;
        t *= x;
        t = __HI(t, __HI(t) / 3 + B2);
    }
    else
    {
        const int hx = __HI(x);
        t = __HI(t, hx / 3 + B1);
    }

    double r = t * t / x;
    double s = C + r * t;
    t *= G + F / (s + E + D / s);

    t = __LO(t, 0);
    t = __HI(t, __HI(t) + 0x0000_0001);

    s = t * t;
    r = x / s;
    const double w = t + t;
    r = (r - t) / (w + r);
    t = t + t * r;

    return sign * t;
}

/// Bit-exact FDLIBM hypotenuse (`FdLibm.Hypot.compute`).
package(flint.java) double fdHypot(double x, double y) pure nothrow @nogc
{
    enum double TWO_MINUS_600 = 0x1.0p-600;
    enum double TWO_PLUS_600 = 0x1.0p+600;

    double a = absD(x);
    double b = absD(y);

    if (!isFinite(a) || !isFinite(b))
    {
        if (a == INFINITY || b == INFINITY)
            return INFINITY;
        return a + b;
    }

    if (b > a)
    {
        const double tmp = a;
        a = b;
        b = tmp;
    }

    int ha = __HI(a);
    int hb = __HI(b);

    if ((ha - hb) > 0x3c0_0000)
        return a + b;

    int k = 0;
    if (a > 0x1.00000ffffffffp500)
    {
        ha -= 0x2580_0000;
        hb -= 0x2580_0000;
        a = a * TWO_MINUS_600;
        b = b * TWO_MINUS_600;
        k += 600;
    }

    double t1, t2;
    if (b < 0x1.0p-500)
    {
        if (b < DOUBLE_MIN_NORMAL)
        {
            if (b == 0.0)
                return a;
            t1 = 0x1.0p1022;
            b *= t1;
            a *= t1;
            k -= 1022;
        }
        else
        {
            ha += 0x2580_0000;
            hb += 0x2580_0000;
            a = a * TWO_PLUS_600;
            b = b * TWO_PLUS_600;
            k -= 600;
        }
    }

    double w = a - b;
    if (w > b)
    {
        t1 = 0.0;
        t1 = __HI(t1, ha);
        t2 = a - t1;
        w = fdSqrt(t1 * t1 - (b * (-b) - t2 * (a + t1)));
    }
    else
    {
        a = a + a;
        double y1 = 0.0;
        y1 = __HI(y1, hb);
        const double y2 = b - y1;
        t1 = 0.0;
        t1 = __HI(t1, ha + 0x0010_0000);
        t2 = a - t1;
        w = fdSqrt(t1 * y1 - (w * (-w) - (t1 * y2 + t2 * b)));
    }

    if (k != 0)
        return powerOfTwoD(k) * w;
    return w;
}

private double remSignedZero(int sign) pure nothrow @nogc
{
    return sign < 0 ? -0.0 : 0.0;
}

private int remIlogb(int hz, int lz) pure nothrow @nogc
{
    int iz;
    if (hz < 0x0010_0000)
    {
        if (hz == 0)
        {
            iz = -1043;
            for (int i = lz; i > 0; i <<= 1)
                iz -= 1;
        }
        else
        {
            iz = -1022;
            for (int i = hz << 11; i > 0; i <<= 1)
                iz -= 1;
        }
    }
    else
    {
        iz = (hz >> 20) - 1023;
    }
    return iz;
}

private void fmodAlign(ref int h, ref int l, int exp) pure nothrow @nogc
{
    if (exp >= -1022)
    {
        h = 0x0010_0000 | (0x000f_ffff & h);
        return;
    }
    const int n = -1022 - exp;
    if (n <= 31)
    {
        h = (h << n) | (l >>> (32 - n));
        l <<= n;
    }
    else
    {
        h = l << (n - 32);
        l = 0;
    }
}

private double fmodPackSubnormal(int hx, int lx, int iy, int sx) pure nothrow @nogc
{
    const int shift = -1022 - iy;
    if (shift <= 20)
    {
        lx = (lx >>> shift) | (hx << (32 - shift));
        hx >>= shift;
    }
    else if (shift <= 31)
    {
        lx = (hx << (32 - shift)) | (lx >>> shift);
        hx = sx;
    }
    else
    {
        lx = hx >> (shift - 32);
        hx = sx;
    }
    double x = __HI_LO(hx | sx, lx);
    x *= 1.0;
    return x;
}

private bool fmodReduce(ref int hx, ref int lx, int hy, int ly, int n) pure nothrow @nogc
{
    while (n-- != 0)
    {
        int hz = hx - hy;
        const int lz = lx - ly;
        if (cast(uint) lx < cast(uint) ly)
            hz -= 1;
        if (hz < 0)
        {
            hx = hx + hx + (lx >>> 31);
            lx = lx + lx;
        }
        else
        {
            if ((hz | lz) == 0)
                return true;
            hx = hz + hz + (lz >>> 31);
            lx = lz + lz;
        }
    }

    int hz = hx - hy;
    const int lz = lx - ly;
    if (cast(uint) lx < cast(uint) ly)
        hz -= 1;
    if (hz >= 0)
    {
        hx = hz;
        lx = lz;
    }
    return (hx | lx) == 0;
}

private double ieee754Fmod(double x, double y) pure nothrow @nogc
{
    int hx = __HI(x);
    int lx = __LO(x);
    int hy = __HI(y);
    int ly = __LO(y);
    const int sx = hx & SIGN_BIT;
    hx ^= sx;
    hy &= EXP_SIGNIF_BITS;

    if ((hy | ly) == 0 || hx >= EXP_BITS || ((hy | ((ly | -ly) >>> 31)) > EXP_BITS))
        return double.nan;

    if (hx <= hy)
    {
        if (hx < hy || cast(uint) lx < cast(uint) ly)
            return x;
        if (lx == ly)
            return remSignedZero(sx);
    }

    const int ix = remIlogb(hx, lx);
    int iy = remIlogb(hy, ly);
    fmodAlign(hx, lx, ix);
    fmodAlign(hy, ly, iy);

    if (fmodReduce(hx, lx, hy, ly, ix - iy))
        return remSignedZero(sx);

    while (hx < 0x0010_0000)
    {
        hx = hx + hx + (lx >>> 31);
        lx = lx + lx;
        iy -= 1;
    }

    if (iy >= -1022)
    {
        hx = (hx - 0x0010_0000) | ((iy + 1023) << 20);
        return __HI_LO(hx | sx, lx);
    }

    return fmodPackSubnormal(hx, lx, iy, sx);
}

/// Bit-exact IEEE-754 remainder (`FdLibm.IEEEremainder.compute`).
package(flint.java) double fdIEEEremainder(double x, double p) pure nothrow @nogc
{
    int hx = __HI(x);
    const int lx = __LO(x);
    int hp = __HI(p);
    const int lp = __LO(p);
    const int sx = hx & SIGN_BIT;
    hp &= EXP_SIGNIF_BITS;
    hx &= EXP_SIGNIF_BITS;

    if ((hp | lp) == 0)
        return double.nan;
    if (hx >= EXP_BITS || (hp >= EXP_BITS && (((hp - EXP_BITS) | lp) != 0)))
        return double.nan;

    if (hp <= 0x7fdf_ffff)
        x = ieee754Fmod(x, p + p);
    if (((hx - hp) | (lx - lp)) == 0)
        return 0.0 * x;

    x = absD(x);
    p = absD(p);
    if (hp < 0x0020_0000)
    {
        if (x + x > p)
        {
            x -= p;
            if (x + x >= p)
                x -= p;
        }
    }
    else
    {
        const double pHalf = 0.5 * p;
        if (x > pHalf)
        {
            x -= p;
            if (x >= pHalf)
                x -= p;
        }
    }
    return __HI(x, __HI(x) ^ sx);
}
