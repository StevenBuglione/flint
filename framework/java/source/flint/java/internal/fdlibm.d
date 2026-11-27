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
private enum double DOUBLE_MAX_VALUE = double.max;
private enum double TWO24 = 0x1.0p24;
private enum double TWO54 = 0x1.0p54;
private enum double PI_CONST = 3.141592653589793;
private enum double TWO_TO_THE_DOUBLE_SCALE_UP = 0x1.0p512;
private enum double TWO_TO_THE_DOUBLE_SCALE_DOWN = 0x1.0p-512;
private enum int SIGN_BIT = cast(int) 0x8000_0000U;
private enum int EXP_BITS = 0x7ff0_0000;
private enum int EXP_SIGNIF_BITS = 0x7fff_ffff;

private double floorD(double a) pure nothrow @nogc
{
    const long bits = doubleToRawLongBits(a);
    const int exp = cast(int)((bits & 0x7FF0_0000_0000_0000L) >> 52) - 1023;
    if (exp < 0)
    {
        if (a == 0.0)
            return a;
        return a < 0.0 ? -1.0 : 0.0;
    }
    if (exp >= 52)
        return a;
    const long fracMask = 0x000F_FFFF_FFFF_FFFFL >> exp;
    if ((bits & fracMask) == 0)
        return a;
    const double trunc = longBitsToDouble(bits & ~fracMask);
    return a < 0.0 ? trunc - 1.0 : trunc;
}

private double scalbD(double d, int scaleFactor) pure nothrow @nogc
{
    enum int MAX_SCALE = 1023 + 1022 + 53 + 1;
    int scaleIncrement;
    double expDelta;

    if (scaleFactor < 0)
    {
        if (scaleFactor < -MAX_SCALE)
            scaleFactor = -MAX_SCALE;
        scaleIncrement = -512;
        expDelta = TWO_TO_THE_DOUBLE_SCALE_DOWN;
    }
    else
    {
        if (scaleFactor > MAX_SCALE)
            scaleFactor = MAX_SCALE;
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

private void expReduce(ref double x, int hx, int xsb, out double hi, out double lo, out int k) pure nothrow @nogc
{
    static immutable double[2] half = [0.5, -0.5];
    static immutable double[2] ln2HI = [0x1.62e42feep-1, -0x1.62e42feep-1];
    static immutable double[2] ln2LO = [0x1.a39ef35793c76p-33, -0x1.a39ef35793c76p-33];
    enum double invln2 = 0x1.71547652b82fep0;

    if (hx < 0x3FF0_A2B2)
    {
        hi = x - ln2HI[xsb];
        lo = ln2LO[xsb];
        k = 1 - xsb - xsb;
    }
    else
    {
        k = cast(int)(invln2 * x + half[xsb]);
        const double t = k;
        hi = x - t * ln2HI[0];
        lo = t * ln2LO[0];
    }
    x = hi - lo;
}

/// Bit-exact FDLIBM exponential (`FdLibm.Exp.compute`).
package(flint.java) double fdExp(double x) pure nothrow @nogc
{
    enum double huge = 1.0e+300;
    enum double twom1000 = 0x1.0p-1000;
    enum double oThreshold = 0x1.62e42fefa39efp9;
    enum double uThreshold = -0x1.74910d52d3051p9;

    enum double P1 = 0x1.555555555553ep-3;
    enum double P2 = -0x1.6c16c16bebd93p-9;
    enum double P3 = 0x1.1566aaf25de2cp-14;
    enum double P4 = -0x1.bbd41c5d26bf1p-20;
    enum double P5 = 0x1.6376972bea4d0p-25;

    int hx = __HI(x);
    const int xsb = (hx >> 31) & 1;
    hx &= EXP_SIGNIF_BITS;

    if (hx >= 0x4086_2E42)
    {
        if (hx >= EXP_BITS)
        {
            if (((hx & 0xf_ffff) | __LO(x)) != 0)
                return x + x;
            return xsb == 0 ? x : 0.0;
        }
        if (x > oThreshold)
            return INFINITY;
        if (x < uThreshold)
            return 0.0;
    }

    double hi = 0.0;
    double lo = 0.0;
    int k = 0;

    if (hx > 0x3fd6_2e42)
    {
        expReduce(x, hx, xsb, hi, lo, k);
    }
    else if (hx < 0x3e30_0000)
    {
        if (huge + x > 1.0)
            return 1.0 + x;
    }

    const double t = x * x;
    const double c = x - t * (P1 + t * (P2 + t * (P3 + t * (P4 + t * P5))));
    if (k == 0)
        return 1.0 - ((x * c) / (c - 2.0) - x);

    double y = 1.0 - ((lo - (x * c) / (2.0 - c)) - hi);
    if (k >= -1021)
    {
        y = __HI(y, __HI(y) + (k << 20));
        return y;
    }
    y = __HI(y, __HI(y) + ((k + 1000) << 20));
    return y * twom1000;
}

private double expm1Scale(double x, double e, int k) pure nothrow @nogc
{
    if (k == -1)
        return 0.5 * (x - e) - 0.5;
    if (k == 1)
    {
        if (x < -0.25)
            return -2.0 * (e - (x + 0.5));
        return 1.0 + 2.0 * (x - e);
    }
    if (k <= -2 || k > 56)
    {
        double y = 1.0 - (e - x);
        y = __HI(y, __HI(y) + (k << 20));
        return y - 1.0;
    }
    double t = 1.0;
    double y;
    if (k < 20)
    {
        t = __HI(t, 0x3ff0_0000 - (0x2_00000 >> k));
        y = t - (e - x);
        y = __HI(y, __HI(y) + (k << 20));
    }
    else
    {
        t = __HI(t, (0x3ff - k) << 20);
        y = x - (e + t);
        y += 1.0;
        y = __HI(y, __HI(y) + (k << 20));
    }
    return y;
}

private void expm1Reduce(ref double x, int hx, int xsb, out double c, out int k) pure nothrow @nogc
{
    enum double ln2Hi = 0x1.62e42feep-1;
    enum double ln2Lo = 0x1.a39ef35793c76p-33;
    enum double invln2 = 0x1.71547652b82fep0;

    double hi;
    double lo;
    if (hx < 0x3FF0_A2B2)
    {
        if (xsb == 0)
        {
            hi = x - ln2Hi;
            lo = ln2Lo;
            k = 1;
        }
        else
        {
            hi = x + ln2Hi;
            lo = -ln2Lo;
            k = -1;
        }
    }
    else
    {
        k = cast(int)(invln2 * x + (xsb == 0 ? 0.5 : -0.5));
        const double t = k;
        hi = x - t * ln2Hi;
        lo = t * ln2Lo;
    }
    x = hi - lo;
    c = (hi - x) - lo;
}

/// Bit-exact FDLIBM `exp(x) - 1` (`FdLibm.Expm1.compute`).
package(flint.java) double fdExpm1(double x) pure nothrow @nogc
{
    enum double oThreshold = 0x1.62e42fefa39efp9;
    enum double Q1 = -0x1.11111111110f4p-5;
    enum double Q2 = 0x1.a01a019fe5585p-10;
    enum double Q3 = -0x1.4ce199eaadbb7p-14;
    enum double Q4 = 0x1.0cfca86e65239p-18;
    enum double Q5 = -0x1.afdb76e09c32dp-23;

    int hx = __HI(x);
    const int xsb = hx & SIGN_BIT;
    hx &= EXP_SIGNIF_BITS;

    if (hx >= 0x4043_687A)
    {
        if (hx >= 0x4086_2E42)
        {
            if (hx >= EXP_BITS)
            {
                if (((hx & 0xf_ffff) | __LO(x)) != 0)
                    return x + x;
                return xsb == 0 ? x : -1.0;
            }
            if (x > oThreshold)
                return INFINITY;
        }
        if (xsb != 0)
            return -1.0;
    }

    double c = 0.0;
    int k = 0;

    if (hx > 0x3fd6_2e42)
        expm1Reduce(x, hx, xsb, c, k);
    else if (hx < 0x3c90_0000)
        return x;

    const double hfx = 0.5 * x;
    const double hxs = x * hfx;
    const double r1 = 1.0 + hxs * (Q1 + hxs * (Q2 + hxs * (Q3 + hxs * (Q4 + hxs * Q5))));
    const double t = 3.0 - r1 * hfx;
    double e = hxs * ((r1 - t) / (6.0 - x * t));
    if (k == 0)
        return x - (x * e - hxs);

    e = (x * (e - c) - c) - hxs;
    return expm1Scale(x, e, k);
}

private double logNearOne(double f, int k) pure nothrow @nogc
{
    enum double ln2Hi = 0x1.62e42feep-1;
    enum double ln2Lo = 0x1.a39ef35793c76p-33;

    if (f == 0.0)
    {
        if (k == 0)
            return 0.0;
        const double dk = cast(double) k;
        return dk * ln2Hi + dk * ln2Lo;
    }
    const double R = f * f * (0.5 - 0.33333333333333333 * f);
    if (k == 0)
        return f - R;
    const double dk = cast(double) k;
    return dk * ln2Hi - ((R - dk * ln2Lo) - f);
}

/// Bit-exact FDLIBM natural logarithm (`FdLibm.Log.compute`).
package(flint.java) double fdLog(double x) pure nothrow @nogc
{
    enum double ln2Hi = 0x1.62e42feep-1;
    enum double ln2Lo = 0x1.a39ef35793c76p-33;
    enum double Lg1 = 0x1.5555555555593p-1;
    enum double Lg2 = 0x1.999999997fa04p-2;
    enum double Lg3 = 0x1.2492494229359p-2;
    enum double Lg4 = 0x1.c71c51d8e78afp-3;
    enum double Lg5 = 0x1.7466496cb03dep-3;
    enum double Lg6 = 0x1.39a09d078c69fp-3;
    enum double Lg7 = 0x1.2f112df3e5244p-3;

    int hx = __HI(x);
    const int lx = __LO(x);

    int k = 0;
    if (hx < 0x0010_0000)
    {
        if (((hx & EXP_SIGNIF_BITS) | lx) == 0)
            return -INFINITY;
        if (hx < 0)
            return double.nan;
        k -= 54;
        x *= TWO54;
        hx = __HI(x);
    }
    if (hx >= EXP_BITS)
        return x + x;

    k += (hx >> 20) - 1023;
    hx &= 0x000f_ffff;
    int i = (hx + 0x9_5f64) & 0x10_0000;
    x = __HI(x, hx | (i ^ 0x3ff0_0000));
    k += (i >> 20);
    const double f = x - 1.0;

    if ((0x000f_ffff & (2 + hx)) < 3)
        return logNearOne(f, k);

    const double s = f / (2.0 + f);
    const double dk = cast(double) k;
    const double z = s * s;
    i = hx - 0x6_147a;
    const double w = z * z;
    const int j = 0x6b851 - hx;
    const double t1 = w * (Lg2 + w * (Lg4 + w * Lg6));
    const double t2 = z * (Lg1 + w * (Lg3 + w * (Lg5 + w * Lg7)));
    i |= j;
    const double R = t2 + t1;
    if (i > 0)
    {
        const double hfsq = 0.5 * f * f;
        if (k == 0)
            return f - (hfsq - s * (hfsq + R));
        return dk * ln2Hi - ((hfsq - (s * (hfsq + R) + dk * ln2Lo)) - f);
    }
    if (k == 0)
        return f - s * (f - R);
    return dk * ln2Hi - ((s * (f - R) - dk * ln2Lo) - f);
}

/// Bit-exact FDLIBM base-10 logarithm (`FdLibm.Log10.compute`).
package(flint.java) double fdLog10(double x) pure nothrow @nogc
{
    enum double ivln10 = 0x1.bcb7b1526e50ep-2;
    enum double log10_2hi = 0x1.34413509f6p-2;
    enum double log10_2lo = 0x1.9fef311f12b36p-42;

    int hx = __HI(x);
    const int lx = __LO(x);

    int k = 0;
    if (hx < 0x0010_0000)
    {
        if (((hx & EXP_SIGNIF_BITS) | lx) == 0)
            return -INFINITY;
        if (hx < 0)
            return double.nan;
        k -= 54;
        x *= TWO54;
        hx = __HI(x);
    }
    if (hx >= EXP_BITS)
        return x + x;

    k += (hx >> 20) - 1023;
    const int i = (k & SIGN_BIT) >>> 31;
    hx = (hx & 0x000f_ffff) | ((0x3ff - i) << 20);
    const double y = cast(double)(k + i);
    x = __HI(x, hx);
    const double z = y * log10_2lo + ivln10 * fdLog(x);
    return z + y * log10_2hi;
}

private void log1pReduce(double x, int hx, out int k, out int hu, out double f, out double c) pure nothrow @nogc
{
    double u;
    if (hx < 0x4340_0000)
    {
        u = 1.0 + x;
        hu = __HI(u);
        k = (hu >> 20) - 1023;
        c = k > 0 ? 1.0 - (u - x) : x - (u - 1.0);
        c /= u;
    }
    else
    {
        u = x;
        hu = __HI(u);
        k = (hu >> 20) - 1023;
        c = 0.0;
    }
    hu &= 0x000f_ffff;
    if (hu < 0x6_a09e)
    {
        u = __HI(u, hu | 0x3ff0_0000);
    }
    else
    {
        k += 1;
        u = __HI(u, hu | 0x3fe0_0000);
        hu = (0x0010_0000 - hu) >> 2;
    }
    f = u - 1.0;
}

private double log1pNearZeroF(double f, double hfsq, int k, double c) pure nothrow @nogc
{
    enum double ln2Hi = 0x1.62e42feep-1;
    enum double ln2Lo = 0x1.a39ef35793c76p-33;

    if (f == 0.0)
    {
        if (k == 0)
            return 0.0;
        c += k * ln2Lo;
        return k * ln2Hi + c;
    }
    const double R = hfsq * (1.0 - 0.66666666666666666 * f);
    if (k == 0)
        return f - R;
    return k * ln2Hi - ((R - (k * ln2Lo + c)) - f);
}

private bool log1pSmall(double x, int ax, out double res) pure nothrow @nogc
{
    if (ax >= 0x3ff0_0000)
    {
        res = x == -1.0 ? -INFINITY : double.nan;
        return true;
    }
    if (ax < 0x3e20_0000)
    {
        res = (TWO54 + x > 0.0 && ax < 0x3c90_0000) ? x : x - x * x * 0.5;
        return true;
    }
    res = 0.0;
    return false;
}

/// Bit-exact FDLIBM `log(1 + x)` (`FdLibm.Log1p.compute`).
package(flint.java) double fdLog1p(double x) pure nothrow @nogc
{
    enum double ln2Hi = 0x1.62e42feep-1;
    enum double ln2Lo = 0x1.a39ef35793c76p-33;
    enum double Lp1 = 0x1.5555555555593p-1;
    enum double Lp2 = 0x1.999999997fa04p-2;
    enum double Lp3 = 0x1.2492494229359p-2;
    enum double Lp4 = 0x1.c71c51d8e78afp-3;
    enum double Lp5 = 0x1.7466496cb03dep-3;
    enum double Lp6 = 0x1.39a09d078c69fp-3;
    enum double Lp7 = 0x1.2f112df3e5244p-3;

    const int hx = __HI(x);
    const int ax = hx & EXP_SIGNIF_BITS;

    int k = 1;
    int hu = 0;
    double f = 0.0;
    double c = 0.0;

    if (hx < 0x3FDA_827A)
    {
        double smallRes;
        if (log1pSmall(x, ax, smallRes))
            return smallRes;
        if (hx > 0 || hx <= cast(int) 0xbfd2_bec3U)
        {
            k = 0;
            f = x;
            hu = 1;
        }
    }

    if (hx >= EXP_BITS)
        return x + x;

    if (k != 0)
        log1pReduce(x, hx, k, hu, f, c);

    const double hfsq = 0.5 * f * f;
    if (hu == 0)
        return log1pNearZeroF(f, hfsq, k, c);

    const double s = f / (2.0 + f);
    const double z = s * s;
    const double R = z * (Lp1 + z * (Lp2 + z * (Lp3 + z * (Lp4 + z * (Lp5 + z * (Lp6 + z * Lp7))))));
    if (k == 0)
        return f - (hfsq - s * (hfsq + R));
    return k * ln2Hi - ((hfsq - (s * (hfsq + R) + (k * ln2Lo + c))) - f);
}

private void powLog2Normal(double xAbs, int ix, out double t1, out double t2) pure nothrow @nogc
{
    enum double CP = 0x1.ec709dc3a03fdp-1;
    enum double CP_H = 0x1.ec709ep-1;
    enum double CP_L = -0x1.e2fe0145b01f5p-28;
    static immutable double[2] BP = [1.0, 1.5];
    static immutable double[2] DP_H = [0.0, 0x1.2b8034p-1];
    static immutable double[2] DP_L = [0.0, 0x1.cfdeb43cfd006p-27];
    enum double L1 = 0x1.3333333333303p-1;
    enum double L2 = 0x1.b6db6db6fabffp-2;
    enum double L3 = 0x1.55555518f264dp-2;
    enum double L4 = 0x1.17460a91d4101p-2;
    enum double L5 = 0x1.d864a93c9db65p-3;
    enum double L6 = 0x1.a7e284a454eefp-3;

    int n = 0;
    if (ix < 0x0010_0000)
    {
        xAbs *= 0x1.0p53;
        n -= 53;
        ix = __HI(xAbs);
    }
    n += (ix >> 20) - 0x3ff;
    const int j = ix & 0x000f_ffff;
    ix = j | 0x3ff0_0000;
    int k;
    if (j <= 0x3988E)
    {
        k = 0;
    }
    else if (j < 0xBB67A)
    {
        k = 1;
    }
    else
    {
        k = 0;
        n += 1;
        ix -= 0x0010_0000;
    }
    xAbs = __HI(xAbs, ix);

    double u = xAbs - BP[k];
    double v = 1.0 / (xAbs + BP[k]);
    const double ss = u * v;
    double sH = ss;
    sH = __LO(sH, 0);
    double tH = 0.0;
    tH = __HI(tH, ((ix >> 1) | 0x2000_0000) + 0x0008_0000 + (k << 18));
    double tL = xAbs - (tH - BP[k]);
    const double sL = v * ((u - sH * tH) - sH * tL);

    double s2 = ss * ss;
    double r = s2 * s2 * (L1 + s2 * (L2 + s2 * (L3 + s2 * (L4 + s2 * (L5 + s2 * L6)))));
    r += sL * (sH + ss);
    s2 = sH * sH;
    tH = 3.0 + s2 + r;
    tH = __LO(tH, 0);
    tL = r - ((tH - 3.0) - s2);

    u = sH * tH;
    v = sL * tH + tL * ss;
    double pH = u + v;
    pH = __LO(pH, 0);
    const double pL = v - (pH - u);
    const double zH = CP_H * pH;
    const double zL = CP_L * pH + pL * CP + DP_L[k];
    const double t = cast(double) n;
    t1 = ((zH + zL) + DP_H[k]) + t;
    t1 = __LO(t1, 0);
    t2 = zL - (((t1 - t) - DP_H[k]) - zH);
}

private double powExp2(double pH, double pL, double z, double s) pure nothrow @nogc
{
    enum double OVT = 8.0085662595372944372e-17;
    enum double P1 = 0x1.555555555553ep-3;
    enum double P2 = -0x1.6c16c16bebd93p-9;
    enum double P3 = 0x1.1566aaf25de2cp-14;
    enum double P4 = -0x1.bbd41c5d26bf1p-20;
    enum double P5 = 0x1.6376972bea4d0p-25;
    enum double LG2 = 0x1.62e42fefa39efp-1;
    enum double LG2_H = 0x1.62e43p-1;
    enum double LG2_L = -0x1.05c610ca86c39p-29;

    int j = __HI(z);
    int i = __LO(z);
    if (j >= 0x4090_0000)
    {
        if (((j - 0x4090_0000) | i) != 0)
            return s * INFINITY;
        if (pL + OVT > z - pH)
            return s * INFINITY;
    }
    else if ((j & EXP_SIGNIF_BITS) >= 0x4090_cc00)
    {
        if (((j - cast(int) 0xc090_cc00U) | i) != 0)
            return s * 0.0;
        if (pL <= z - pH)
            return s * 0.0;
    }

    i = j & EXP_SIGNIF_BITS;
    int k = (i >> 20) - 0x3ff;
    int n = 0;
    if (i > 0x3fe0_0000)
    {
        n = j + (0x0010_0000 >> (k + 1));
        k = ((n & EXP_SIGNIF_BITS) >> 20) - 0x3ff;
        double t = 0.0;
        t = __HI(t, n & ~(0x000f_ffff >> k));
        n = ((n & 0x000f_ffff) | 0x0010_0000) >> (20 - k);
        if (j < 0)
            n = -n;
        pH -= t;
    }

    double t = pL + pH;
    t = __LO(t, 0);
    const double u = t * LG2_H;
    const double v = (pL - (t - pH)) * LG2 + t * LG2_L;
    z = u + v;
    const double w = v - (z - u);
    t = z * z;
    const double t1 = z - t * (P1 + t * (P2 + t * (P3 + t * (P4 + t * P5))));
    const double r = (z * t1) / (t1 - 2.0) - (w + z * w);
    z = 1.0 - (r - z);
    j = __HI(z) + (n << 20);
    if ((j >> 20) <= 0)
    {
        z = scalbD(z, n);
    }
    else
    {
        z = __HI(z, __HI(z) + (n << 20));
    }
    return s * z;
}

private int powClassifyYInt(double yAbs) pure nothrow @nogc
{
    if (yAbs >= 0x1.0p53)
        return 2;
    if (yAbs >= 1.0)
    {
        const long yAbsLong = cast(long) yAbs;
        if (cast(double) yAbsLong == yAbs)
            return 2 - cast(int)(yAbsLong & 0x1L);
    }
    return 0;
}

private bool powSpecialY(double x, double y, double xAbs, double yAbs, out double res) pure nothrow @nogc
{
    if (y == 2.0)
    {
        res = x * x;
        return true;
    }
    if (y == 0.5 && x >= -DOUBLE_MAX_VALUE)
    {
        res = fdSqrt(x + 0.0);
        return true;
    }
    if (yAbs == 1.0)
    {
        res = y == 1.0 ? x : 1.0 / x;
        return true;
    }
    if (yAbs == INFINITY)
    {
        if (xAbs == 1.0)
            res = double.nan;
        else if (xAbs > 1.0)
            res = y >= 0.0 ? y : 0.0;
        else
            res = y < 0.0 ? -y : 0.0;
        return true;
    }
    res = 0.0;
    return false;
}

private double powSpecialX(double xAbs, double y, int hx, int ix, int yIsInt) pure nothrow @nogc
{
    double z = xAbs;
    if (y < 0.0)
        z = 1.0 / z;
    if (hx < 0)
    {
        if (((ix - 0x3ff0_0000) | yIsInt) == 0)
            return double.nan;
        if (yIsInt == 1)
            z = -1.0 * z;
    }
    return z;
}

private bool powHugeY(double xAbs, double y, double s, out double t1, out double t2, out double res) pure nothrow @nogc
{
    enum double INV_LN2 = 0x1.71547652b82fep0;
    enum double INV_LN2_H = 0x1.715476p0;
    enum double INV_LN2_L = 0x1.4ae0bf85ddf44p-26;

    if (xAbs < 0x1.fffff00000000p-1)
    {
        t1 = 0.0;
        t2 = 0.0;
        res = y < 0.0 ? s * INFINITY : s * 0.0;
        return true;
    }
    if (xAbs > 0x1.00000ffffffffp0)
    {
        t1 = 0.0;
        t2 = 0.0;
        res = y > 0.0 ? s * INFINITY : s * 0.0;
        return true;
    }

    const double t = xAbs - 1.0;
    const double w = (t * t) * (0.5 - t * (0.3333333333333333333333 - t * 0.25));
    const double u = INV_LN2_H * t;
    const double v = t * INV_LN2_L - w * INV_LN2;
    t1 = u + v;
    t1 = __LO(t1, 0);
    t2 = v - (t1 - u);
    res = 0.0;
    return false;
}

/// Bit-exact FDLIBM power `x^y` (`FdLibm.Pow.compute`).
package(flint.java) double fdPow(double x, double y) pure nothrow @nogc
{
    if (y == 0.0)
        return 1.0;
    if (x != x || y != y)
        return x + y;

    const double yAbs = absD(y);
    const double xAbs = absD(x);
    double specialRes;
    if (powSpecialY(x, y, xAbs, yAbs, specialRes))
        return specialRes;

    const int hx = __HI(x);
    const int ix = hx & EXP_SIGNIF_BITS;
    const int yIsInt = hx < 0 ? powClassifyYInt(yAbs) : 0;

    if (xAbs == 0.0 || xAbs == INFINITY || xAbs == 1.0)
        return powSpecialX(xAbs, y, hx, ix, yIsInt);

    const int n = (hx >> 31) + 1;
    if ((n | yIsInt) == 0)
        return double.nan;

    const double s = (n | (yIsInt - 1)) == 0 ? -1.0 : 1.0;

    double t1;
    double t2;
    if (yAbs > 0x1.00000ffffffffp31)
    {
        double res;
        if (powHugeY(xAbs, y, s, t1, t2, res))
            return res;
    }
    else
    {
        powLog2Normal(xAbs, ix, t1, t2);
    }

    double y1 = y;
    y1 = __LO(y1, 0);
    const double pL = (y - y1) * t1 + y * t2;
    const double pH = y1 * t1;
    return powExp2(pH, pL, pL + pH, s);
}

/// Bit-exact FDLIBM hyperbolic sine (`FdLibm.Sinh.compute`).
package(flint.java) double fdSinh(double x) pure nothrow @nogc
{
    enum double shuge = 1.0e307;

    const int jx = __HI(x);
    const int ix = jx & EXP_SIGNIF_BITS;

    if (ix >= EXP_BITS)
        return x + x;

    const double h = jx < 0 ? -0.5 : 0.5;
    if (ix < 0x4036_0000)
    {
        if (ix < 0x3e30_0000 && shuge + x > 1.0)
            return x;
        const double t = fdExpm1(absD(x));
        if (ix < 0x3ff0_0000)
            return h * (2.0 * t - t * t / (t + 1.0));
        return h * (t + t / (t + 1.0));
    }

    if (ix < 0x4086_2E42)
        return h * fdExp(absD(x));

    const int lx = __LO(x);
    if (ix < 0x4086_33CE || (ix == 0x4086_33ce && cast(uint) lx <= 0x8fb9_f87dU))
    {
        const double w = fdExp(0.5 * absD(x));
        const double t = h * w;
        return t * w;
    }

    return x * shuge;
}

/// Bit-exact FDLIBM hyperbolic cosine (`FdLibm.Cosh.compute`).
package(flint.java) double fdCosh(double x) pure nothrow @nogc
{
    const int ix = __HI(x) & EXP_SIGNIF_BITS;

    if (ix >= EXP_BITS)
        return x * x;

    if (ix < 0x3fd6_2e43)
    {
        const double t = fdExpm1(absD(x));
        const double w = 1.0 + t;
        if (ix < 0x3c80_0000)
            return w;
        return 1.0 + (t * t) / (w + w);
    }

    if (ix < 0x4036_0000)
    {
        const double t = fdExp(absD(x));
        return 0.5 * t + 0.5 / t;
    }

    if (ix < 0x4086_2E42)
        return 0.5 * fdExp(absD(x));

    const int lx = __LO(x);
    if (ix < 0x4086_33CE || (ix == 0x4086_33ce && cast(uint) lx <= 0x8fb9_f87dU))
    {
        const double w = fdExp(0.5 * absD(x));
        const double t = 0.5 * w;
        return t * w;
    }

    return INFINITY;
}

/// Bit-exact FDLIBM hyperbolic tangent (`FdLibm.Tanh.compute`).
package(flint.java) double fdTanh(double x) pure nothrow @nogc
{
    enum double tiny = 1.0e-300;

    const int jx = __HI(x);
    const int ix = jx & EXP_SIGNIF_BITS;

    if (ix >= EXP_BITS)
    {
        if (jx >= 0)
            return 1.0 / x + 1.0;
        return 1.0 / x - 1.0;
    }

    double z;
    if (ix < 0x4036_0000)
    {
        if (ix < 0x3c80_0000)
            return x * (1.0 + x);
        if (ix >= 0x3ff0_0000)
        {
            const double t = fdExpm1(2.0 * absD(x));
            z = 1.0 - 2.0 / (t + 2.0);
        }
        else
        {
            const double t = fdExpm1(-2.0 * absD(x));
            z = -t / (t + 2.0);
        }
    }
    else
    {
        z = 1.0 - tiny;
    }
    return jx >= 0 ? z : -z;
}

private void kernelRemPio2Invert(ref int[20] iq, int jz, int q0, int ih, ref double z) pure nothrow @nogc
{
    int carry = 0;
    for (int i = 0; i < jz; i++)
    {
        const int j = iq[i];
        if (carry == 0)
        {
            if (j != 0)
            {
                carry = 1;
                iq[i] = 0x100_0000 - j;
            }
        }
        else
        {
            iq[i] = 0xff_ffff - j;
        }
    }
    if (q0 == 1)
        iq[jz - 1] &= 0x7f_ffff;
    else if (q0 == 2)
        iq[jz - 1] &= 0x3f_ffff;
    if (ih == 2)
    {
        z = 1.0 - z;
        if (carry != 0)
            z -= scalbD(1.0, q0);
    }
}

private void kernelRemPio2Finish(ref int[20] iq, ref double[20] q, ref double[20] fq, int jz, int jp,
        int q0, int ih, double z, ref double[2] y) pure nothrow @nogc
{
    static immutable double[8] PIo2 = [
        0x1.921fb4p0, 0x1.4442dp-24, 0x1.846988p-48, 0x1.8cc516p-72, 0x1.01b838p-96,
        0x1.a25204p-120, 0x1.382228p-145, 0x1.9f31dp-169,
    ];
    enum double twon24 = 0x1.0p-24;

    if (z == 0.0)
    {
        jz -= 1;
        q0 -= 24;
        while (iq[jz] == 0)
        {
            jz--;
            q0 -= 24;
        }
    }
    else
    {
        z = scalbD(z, -q0);
        if (z >= TWO24)
        {
            const double fw = cast(double) cast(int)(twon24 * z);
            iq[jz] = cast(int)(z - TWO24 * fw);
            jz += 1;
            q0 += 24;
            iq[jz] = cast(int) fw;
        }
        else
        {
            iq[jz] = cast(int) z;
        }
    }

    double fw = scalbD(1.0, q0);
    for (int i = jz; i >= 0; i--)
    {
        q[i] = fw * cast(double) iq[i];
        fw *= twon24;
    }

    for (int i = jz; i >= 0; i--)
    {
        fw = 0.0;
        for (int k = 0; k <= jp && k <= jz - i; k++)
            fw += PIo2[k] * q[i + k];
        fq[jz - i] = fw;
    }

    // prec == 2: compress fq[] into y[0..2]
    fw = 0.0;
    for (int i = jz; i >= 0; i--)
        fw += fq[i];
    y[0] = ih == 0 ? fw : -fw;
    fw = fq[0] - fw;
    for (int i = 1; i <= jz; i++)
        fw += fq[i];
    y[1] = ih == 0 ? fw : -fw;
}

private int distillQ(ref int[20] iq, ref double[20] q, int jz, int q0, out double z, out int ih) pure nothrow @nogc
{
    enum double twon24 = 0x1.0p-24;

    double zVal = q[jz];
    for (int i = 0, jj = jz; jj > 0; i++, jj--)
    {
        const double fw = cast(double) cast(int)(twon24 * zVal);
        iq[i] = cast(int)(zVal - TWO24 * fw);
        zVal = q[jj - 1] + fw;
    }

    zVal = scalbD(zVal, q0);
    zVal -= 8.0 * floorD(zVal * 0.125);
    int n = cast(int) zVal;
    zVal -= cast(double) n;
    int ihVal = 0;
    if (q0 > 0)
    {
        const int ii = iq[jz - 1] >> (24 - q0);
        n += ii;
        iq[jz - 1] -= ii << (24 - q0);
        ihVal = iq[jz - 1] >> (23 - q0);
    }
    else if (q0 == 0)
    {
        ihVal = iq[jz - 1] >> 23;
    }
    else if (zVal >= 0.5)
    {
        ihVal = 2;
    }

    if (ihVal > 0)
    {
        n += 1;
        kernelRemPio2Invert(iq, jz, q0, ihVal, zVal);
    }
    z = zVal;
    ih = ihVal;
    return n;
}

private int kernelRemPio2(const ref double[3] x, ref double[2] y, int e0, int nx, const int[] ipio2) pure nothrow @nogc
{
    enum int jk = 4; // init_jk[2]
    enum int jp = jk;

    int[20] iq = void;
    double[20] f = void;
    double[20] fq = void;
    double[20] q = void;

    const int jx = nx - 1;
    int jv = (e0 - 3) / 24;
    if (jv < 0)
        jv = 0;
    const int q0 = e0 - 24 * (jv + 1);

    int j = jv - jx;
    const int m = jx + jk;
    for (int i = 0; i <= m; i++, j++)
        f[i] = j < 0 ? 0.0 : cast(double) ipio2[j];

    for (int i = 0; i <= jk; i++)
    {
        double fw = 0.0;
        for (j = 0; j <= jx; j++)
            fw += x[j] * f[jx + i - j];
        q[i] = fw;
    }

    int jz = jk;
    int n;
    int ih;
    double z;
    while (true)
    {
        n = distillQ(iq, q, jz, q0, z, ih);

        if (z != 0.0)
            break;

        j = 0;
        for (int i = jz - 1; i >= jk; i--)
            j |= iq[i];
        if (j != 0)
            break;

        int k = 1;
        while (iq[jk - k] == 0)
            k++;
        for (int i = jz + 1; i <= jz + k; i++)
        {
            f[jx + i] = cast(double) ipio2[jv + i];
            double fw = 0.0;
            for (j = 0; j <= jx; j++)
                fw += x[j] * f[jx + i - j];
            q[i] = fw;
        }
        jz += k;
    }

    kernelRemPio2Finish(iq, q, fq, jz, jp, q0, ih, z, y);
    return n & 7;
}

private int remPio2NearPi2(double x, int hx, int ix, ref double[2] y) pure nothrow @nogc
{
    enum double pio2_1 = 0x1.921fb544p0;
    enum double pio2_1t = 0x1.0b4611a626331p-34;
    enum double pio2_2 = 0x1.0b4611a6p-34;
    enum double pio2_2t = 0x1.3198a2e037073p-69;

    if (hx > 0)
    {
        double z = x - pio2_1;
        if (ix != 0x3ff9_21fb)
        {
            y[0] = z - pio2_1t;
            y[1] = (z - y[0]) - pio2_1t;
        }
        else
        {
            z -= pio2_2;
            y[0] = z - pio2_2t;
            y[1] = (z - y[0]) - pio2_2t;
        }
        return 1;
    }

    double z = x + pio2_1;
    if (ix != 0x3ff9_21fb)
    {
        y[0] = z + pio2_1t;
        y[1] = (z - y[0]) + pio2_1t;
    }
    else
    {
        z += pio2_2;
        y[0] = z + pio2_2t;
        y[1] = (z - y[0]) + pio2_2t;
    }
    return -1;
}

private int remPio2Medium(double x, int hx, int ix, ref double[2] y) pure nothrow @nogc
{
    static immutable int[32] npio2Hw = [
        0x3FF921FB, 0x400921FB, 0x4012D97C, 0x401921FB, 0x401F6A7A, 0x4022D97C, 0x4025FDBB, 0x402921FB,
        0x402C463A, 0x402F6A7A, 0x4031475C, 0x4032D97C, 0x40346B9C, 0x4035FDBB, 0x40378FDB, 0x403921FB,
        0x403AB41B, 0x403C463A, 0x403DD85A, 0x403F6A7A, 0x40407E4C, 0x4041475C, 0x4042106C, 0x4042D97C,
        0x4043A28C, 0x40446B9C, 0x404534AC, 0x4045FDBB, 0x4046C6CB, 0x40478FDB, 0x404858EB, 0x404921FB,
    ];
    enum double invpio2 = 0x1.45f306dc9c883p-1;
    enum double pio2_1 = 0x1.921fb544p0;
    enum double pio2_1t = 0x1.0b4611a626331p-34;
    enum double pio2_2 = 0x1.0b4611a6p-34;
    enum double pio2_2t = 0x1.3198a2e037073p-69;
    enum double pio2_3 = 0x1.3198a2ep-69;
    enum double pio2_3t = 0x1.b839a252049c1p-104;

    double t = absD(x);
    const int n = cast(int)(t * invpio2 + 0.5);
    const double fn = cast(double) n;
    double r = t - fn * pio2_1;
    double w = fn * pio2_1t;
    if (n < 32 && ix != npio2Hw[n - 1])
    {
        y[0] = r - w;
    }
    else
    {
        const int j = ix >> 20;
        y[0] = r - w;
        int i = j - ((__HI(y[0]) >> 20) & 0x7ff);
        if (i > 16)
        {
            t = r;
            w = fn * pio2_2;
            r = t - w;
            w = fn * pio2_2t - ((t - r) - w);
            y[0] = r - w;
            i = j - ((__HI(y[0]) >> 20) & 0x7ff);
            if (i > 49)
            {
                t = r;
                w = fn * pio2_3;
                r = t - w;
                w = fn * pio2_3t - ((t - r) - w);
                y[0] = r - w;
            }
        }
    }
    y[1] = (r - y[0]) - w;
    if (hx < 0)
    {
        y[0] = -y[0];
        y[1] = -y[1];
        return -n;
    }
    return n;
}

private int ieee754RemPio2(double x, ref double[2] y) pure nothrow @nogc
{
    static immutable int[66] twoOverPi = [
        0xA2F983, 0x6E4E44, 0x1529FC, 0x2757D1, 0xF534DD, 0xC0DB62, 0x95993C, 0x439041, 0xFE5163,
        0xABDEBB, 0xC561B7, 0x246E3A, 0x424DD2, 0xE00649, 0x2EEA09, 0xD1921C, 0xFE1DEB, 0x1CB129,
        0xA73EE8, 0x8235F5, 0x2EBB44, 0x84E99C, 0x7026B4, 0x5F7E41, 0x3991D6, 0x398353, 0x39F49C,
        0x845F8B, 0xBDF928, 0x3B1FF8, 0x97FFDE, 0x05980F, 0xEF2F11, 0x8B5A0A, 0x6D1F6D, 0x367ECF,
        0x27CB09, 0xB74F46, 0x3F669E, 0x5FEA2D, 0x7527BA, 0xC7EBE5, 0xF17B3D, 0x0739F7, 0x8A5292,
        0xEA6BFB, 0x5FB11F, 0x8D5D08, 0x560330, 0x46FC7B, 0x6BABF0, 0xCFBC20, 0x9AF436, 0x1DA9E3,
        0x91615E, 0xE61B08, 0x659985, 0x5F14A0, 0x68408D, 0xFFD880, 0x4D7327, 0x310606, 0x1556CA,
        0x73A8C9, 0x60E27B, 0xC08C6B,
    ];

    const int hx = __HI(x);
    const int ix = hx & EXP_SIGNIF_BITS;
    if (ix <= 0x3fe9_21fb)
    {
        y[0] = x;
        y[1] = 0.0;
        return 0;
    }
    if (ix < 0x4002_d97c)
        return remPio2NearPi2(x, hx, ix, y);
    if (ix <= 0x4139_21fb)
        return remPio2Medium(x, hx, ix, y);
    if (ix >= EXP_BITS)
    {
        y[0] = double.nan;
        y[1] = double.nan;
        return 0;
    }

    double z = 0.0;
    z = __LO(z, __LO(x));
    const int e0 = (ix >> 20) - 1046;
    z = __HI(z, ix - (e0 << 20));
    double[3] tx = void;
    for (int i = 0; i < 2; i++)
    {
        tx[i] = cast(double) cast(int) z;
        z = (z - tx[i]) * TWO24;
    }
    tx[2] = z;
    int nx = 3;
    while (tx[nx - 1] == 0.0)
        nx--;
    const int n = kernelRemPio2(tx, y, e0, nx, twoOverPi[]);
    if (hx < 0)
    {
        y[0] = -y[0];
        y[1] = -y[1];
        return -n;
    }
    return n;
}

private double kernelSin(double x, double y, int iy) pure nothrow @nogc
{
    enum double S1 = -0x1.5555555555549p-3;
    enum double S2 = 0x1.111111110f8a6p-7;
    enum double S3 = -0x1.a01a019c161d5p-13;
    enum double S4 = 0x1.71de357b1fe7dp-19;
    enum double S5 = -0x1.ae5e68a2b9cebp-26;
    enum double S6 = 0x1.5d93a5acfd57cp-33;

    const int ix = __HI(x) & EXP_SIGNIF_BITS;
    if (ix < 0x3e40_0000)
        return x;
    const double z = x * x;
    const double v = z * x;
    const double r = S2 + z * (S3 + z * (S4 + z * (S5 + z * S6)));
    if (iy == 0)
        return x + v * (S1 + z * r);
    return x - ((z * (0.5 * y - v * r) - y) - v * S1);
}

private double kernelCos(double x, double y) pure nothrow @nogc
{
    enum double C1 = 0x1.555555555554cp-5;
    enum double C2 = -0x1.6c16c16c15177p-10;
    enum double C3 = 0x1.a01a019cb159p-16;
    enum double C4 = -0x1.27e4f809c52adp-22;
    enum double C5 = 0x1.1ee9ebdb4b1c4p-29;
    enum double C6 = -0x1.8fae9be8838d4p-37;

    const int ix = __HI(x) & EXP_SIGNIF_BITS;
    if (ix < 0x3e40_0000)
        return 1.0;
    const double z = x * x;
    const double r = z * (C1 + z * (C2 + z * (C3 + z * (C4 + z * (C5 + z * C6)))));
    if (ix < 0x3FD3_3333)
        return 1.0 - (0.5 * z - (z * r - x * y));

    const double qx = ix > 0x3fe9_0000 ? 0.28125 : __HI_LO(ix - 0x0020_0000, 0);
    const double hz = 0.5 * z - qx;
    const double a = 1.0 - qx;
    return a - (hz - (z * r - x * y));
}

private double kernelTanTiny(double x, double y, int ix, int iy) pure nothrow @nogc
{
    if (((ix | __LO(x)) | (iy + 1)) == 0)
        return 1.0 / absD(x);
    if (iy == 1)
        return x;
    const double w = x + y;
    double z = w;
    z = __LO(z, 0);
    const double v = y - (z - x);
    const double a = -1.0 / w;
    double t = a;
    t = __LO(t, 0);
    const double s = 1.0 + t * z;
    return t + a * (s + t * v);
}

private double kernelTan(double x, double y, int iy) pure nothrow @nogc
{
    enum double pio4 = 0x1.921fb54442d18p-1;
    enum double pio4lo = 0x1.1a62633145c07p-55;
    static immutable double[13] T = [
        0x1.5555555555563p-2, 0x1.111111110fe7ap-3, 0x1.ba1ba1bb341fep-5, 0x1.664f48406d637p-6,
        0x1.226e3e96e8493p-7, 0x1.d6d22c9560328p-9, 0x1.7dbc8fee08315p-10, 0x1.344d8f2f26501p-11,
        0x1.026f71a8d1068p-12, 0x1.47e88a03792a6p-14, 0x1.2b80f32f0a7e9p-14,
        -0x1.375cbdb605373p-16, 0x1.b2a7074bf7ad4p-16,
    ];

    const int hx = __HI(x);
    const int ix = hx & EXP_SIGNIF_BITS;
    if (ix < 0x3e30_0000)
        return kernelTanTiny(x, y, ix, iy);

    if (ix >= 0x3FE5_9428)
    {
        if (hx < 0)
        {
            x = -x;
            y = -y;
        }
        const double z0 = pio4 - x;
        const double w0 = pio4lo - y;
        x = z0 + w0;
        y = 0.0;
    }

    const double z = x * x;
    const double w = z * z;
    double r = T[1] + w * (T[3] + w * (T[5] + w * (T[7] + w * (T[9] + w * T[11]))));
    const double v = z * (T[2] + w * (T[4] + w * (T[6] + w * (T[8] + w * (T[10] + w * T[12])))));
    const double s = z * x;
    r = y + z * (s * (r + v) + y);
    r += T[0] * s;
    const double ww = x + r;
    if (ix >= 0x3FE5_9428)
    {
        const double vv = cast(double) iy;
        return cast(double)(1 - ((hx >> 30) & 2)) * (vv - 2.0 * (x - (ww * ww / (ww + vv) - r)));
    }
    if (iy == 1)
        return ww;

    double zz = ww;
    zz = __LO(zz, 0);
    const double vv = r - (zz - x);
    const double a = -1.0 / ww;
    double t = a;
    t = __LO(t, 0);
    const double ss = 1.0 + t * zz;
    return t + a * (ss + t * vv);
}

/// Bit-exact FDLIBM sine (`FdLibm.Sin.compute`).
package(flint.java) double fdSin(double x) pure nothrow @nogc
{
    const int ix = __HI(x) & EXP_SIGNIF_BITS;
    if (ix <= 0x3fe9_21fb)
        return kernelSin(x, 0.0, 0);
    if (ix >= EXP_BITS)
        return double.nan;

    double[2] y = void;
    const int n = ieee754RemPio2(x, y);
    switch (n & 3)
    {
    case 0:
        return kernelSin(y[0], y[1], 1);
    case 1:
        return kernelCos(y[0], y[1]);
    case 2:
        return -kernelSin(y[0], y[1], 1);
    default:
        return -kernelCos(y[0], y[1]);
    }
}

/// Bit-exact FDLIBM cosine (`FdLibm.Cos.compute`).
package(flint.java) double fdCos(double x) pure nothrow @nogc
{
    const int ix = __HI(x) & EXP_SIGNIF_BITS;
    if (ix <= 0x3fe9_21fb)
        return kernelCos(x, 0.0);
    if (ix >= EXP_BITS)
        return double.nan;

    double[2] y = void;
    const int n = ieee754RemPio2(x, y);
    switch (n & 3)
    {
    case 0:
        return kernelCos(y[0], y[1]);
    case 1:
        return -kernelSin(y[0], y[1], 1);
    case 2:
        return -kernelCos(y[0], y[1]);
    default:
        return kernelSin(y[0], y[1], 1);
    }
}

/// Bit-exact FDLIBM tangent (`FdLibm.Tan.compute`).
package(flint.java) double fdTan(double x) pure nothrow @nogc
{
    const int ix = __HI(x) & EXP_SIGNIF_BITS;
    if (ix <= 0x3fe9_21fb)
        return kernelTan(x, 0.0, 1);
    if (ix >= EXP_BITS)
        return double.nan;

    double[2] y = void;
    const int n = ieee754RemPio2(x, y);
    return kernelTan(y[0], y[1], 1 - ((n & 1) << 1));
}

/// Bit-exact FDLIBM arcsine (`FdLibm.Asin.compute`).
package(flint.java) double fdAsin(double x) pure nothrow @nogc
{
    enum double pio2Hi = 0x1.921fb54442d18p0;
    enum double pio2Lo = 0x1.1a62633145c07p-54;
    enum double pio4Hi = 0x1.921fb54442d18p-1;
    enum double pS0 = 0x1.5555555555555p-3;
    enum double pS1 = -0x1.4d61203eb6f7dp-2;
    enum double pS2 = 0x1.9c1550e884455p-3;
    enum double pS3 = -0x1.48228b5688f3bp-5;
    enum double pS4 = 0x1.9efe07501b288p-11;
    enum double pS5 = 0x1.23de10dfdf709p-15;
    enum double qS1 = -0x1.33a271c8a2d4bp1;
    enum double qS2 = 0x1.02ae59c598ac8p1;
    enum double qS3 = -0x1.6066c1b8d0159p-1;
    enum double qS4 = 0x1.3b8c5b12e9282p-4;

    const int hx = __HI(x);
    const int ix = hx & EXP_SIGNIF_BITS;
    if (ix >= 0x3ff0_0000)
    {
        if (((ix - 0x3ff0_0000) | __LO(x)) == 0)
            return x * pio2Hi + x * pio2Lo;
        return double.nan;
    }
    if (ix < 0x3fe0_0000)
    {
        if (ix < 0x3e40_0000)
            return x;
        const double t = x * x;
        const double p = t * (pS0 + t * (pS1 + t * (pS2 + t * (pS3 + t * (pS4 + t * pS5)))));
        const double q = 1.0 + t * (qS1 + t * (qS2 + t * (qS3 + t * qS4)));
        return x + x * (p / q);
    }

    const double t = (1.0 - absD(x)) * 0.5;
    const double p = t * (pS0 + t * (pS1 + t * (pS2 + t * (pS3 + t * (pS4 + t * pS5)))));
    const double q = 1.0 + t * (qS1 + t * (qS2 + t * (qS3 + t * qS4)));
    const double s = fdSqrt(t);
    double res;
    if (ix >= 0x3FEF_3333)
    {
        const double w = p / q;
        res = pio2Hi - (2.0 * (s + s * w) - pio2Lo);
    }
    else
    {
        double w = s;
        w = __LO(w, 0);
        const double c = (t - w * w) / (s + w);
        const double r = p / q;
        const double pp = 2.0 * s * r - (pio2Lo - 2.0 * c);
        const double qq = pio4Hi - 2.0 * w;
        res = pio4Hi - (pp - qq);
    }
    return hx > 0 ? res : -res;
}

/// Bit-exact FDLIBM arccosine (`FdLibm.Acos.compute`).
package(flint.java) double fdAcos(double x) pure nothrow @nogc
{
    enum double pio2Hi = 0x1.921fb54442d18p0;
    enum double pio2Lo = 0x1.1a62633145c07p-54;
    enum double pS0 = 0x1.5555555555555p-3;
    enum double pS1 = -0x1.4d61203eb6f7dp-2;
    enum double pS2 = 0x1.9c1550e884455p-3;
    enum double pS3 = -0x1.48228b5688f3bp-5;
    enum double pS4 = 0x1.9efe07501b288p-11;
    enum double pS5 = 0x1.23de10dfdf709p-15;
    enum double qS1 = -0x1.33a271c8a2d4bp1;
    enum double qS2 = 0x1.02ae59c598ac8p1;
    enum double qS3 = -0x1.6066c1b8d0159p-1;
    enum double qS4 = 0x1.3b8c5b12e9282p-4;

    const int hx = __HI(x);
    const int ix = hx & EXP_SIGNIF_BITS;
    if (ix >= 0x3ff0_0000)
    {
        if (((ix - 0x3ff0_0000) | __LO(x)) == 0)
            return hx > 0 ? 0.0 : PI_CONST + 2.0 * pio2Lo;
        return double.nan;
    }
    if (ix < 0x3fe0_0000)
    {
        if (ix <= 0x3c60_0000)
            return pio2Hi + pio2Lo;
        const double z = x * x;
        const double p = z * (pS0 + z * (pS1 + z * (pS2 + z * (pS3 + z * (pS4 + z * pS5)))));
        const double q = 1.0 + z * (qS1 + z * (qS2 + z * (qS3 + z * qS4)));
        return pio2Hi - (x - (pio2Lo - x * (p / q)));
    }
    if (hx < 0)
    {
        const double z = (1.0 + x) * 0.5;
        const double p = z * (pS0 + z * (pS1 + z * (pS2 + z * (pS3 + z * (pS4 + z * pS5)))));
        const double q = 1.0 + z * (qS1 + z * (qS2 + z * (qS3 + z * qS4)));
        const double s = fdSqrt(z);
        const double w = (p / q) * s - pio2Lo;
        return PI_CONST - 2.0 * (s + w);
    }

    const double z = (1.0 - x) * 0.5;
    const double s = fdSqrt(z);
    double df = s;
    df = __LO(df, 0);
    const double c = (z - df * df) / (s + df);
    const double p = z * (pS0 + z * (pS1 + z * (pS2 + z * (pS3 + z * (pS4 + z * pS5)))));
    const double q = 1.0 + z * (qS1 + z * (qS2 + z * (qS3 + z * qS4)));
    const double w = (p / q) * s + c;
    return 2.0 * (df + w);
}

private double atanReduce(double x, int ix, out int id) pure nothrow @nogc
{
    x = absD(x);
    if (ix < 0x3ff3_0000)
    {
        if (ix < 0x3fe6_0000)
        {
            id = 0;
            return (2.0 * x - 1.0) / (2.0 + x);
        }
        id = 1;
        return (x - 1.0) / (x + 1.0);
    }
    if (ix < 0x4003_8000)
    {
        id = 2;
        return (x - 1.5) / (1.0 + 1.5 * x);
    }
    id = 3;
    return -1.0 / x;
}

/// Bit-exact FDLIBM arctangent (`FdLibm.Atan.compute`).
package(flint.java) double fdAtan(double x) pure nothrow @nogc
{
    static immutable double[4] atanhi = [
        0x1.dac670561bb4fp-2, 0x1.921fb54442d18p-1, 0x1.f730bd281f69bp-1, 0x1.921fb54442d18p0,
    ];
    static immutable double[4] atanlo = [
        0x1.a2b7f222f65e2p-56, 0x1.1a62633145c07p-55, 0x1.007887af0cbbdp-56, 0x1.1a62633145c07p-54,
    ];
    static immutable double[11] aT = [
        0x1.555555555550dp-2, -0x1.999999998ebc4p-3, 0x1.24924920083ffp-3, -0x1.c71c6fe231671p-4,
        0x1.745cdc54c206ep-4, -0x1.3b0f2af749a6dp-4, 0x1.10d66a0d03d51p-4, -0x1.dde2d52defd9ap-5,
        0x1.97b4b24760debp-5, -0x1.2b4442c6a6c2fp-5, 0x1.0ad3ae322da11p-6,
    ];

    const int hx = __HI(x);
    const int ix = hx & EXP_SIGNIF_BITS;
    if (ix >= 0x4410_0000)
    {
        if (ix > EXP_BITS || (ix == EXP_BITS && __LO(x) != 0))
            return x + x;
        return hx > 0 ? atanhi[3] + atanlo[3] : -atanhi[3] - atanlo[3];
    }

    int id;
    if (ix < 0x3fdc_0000)
    {
        if (ix < 0x3e20_0000)
            return x;
        id = -1;
    }
    else
    {
        x = atanReduce(x, ix, id);
    }

    const double z = x * x;
    const double w = z * z;
    const double s1 = z * (aT[0] + w * (aT[2] + w * (aT[4] + w * (aT[6] + w * (aT[8] + w * aT[10])))));
    const double s2 = w * (aT[1] + w * (aT[3] + w * (aT[5] + w * (aT[7] + w * aT[9]))));
    if (id < 0)
        return x - x * (s1 + s2);
    const double res = atanhi[id] - ((x * (s1 + s2) - atanlo[id]) - x);
    return hx < 0 ? -res : res;
}

private double atan2InfX(int m, int iy) pure nothrow @nogc
{
    enum double tiny = 1.0e-300;
    enum double piO4 = 0x1.921fb54442d18p-1;

    if (iy == EXP_BITS)
    {
        switch (m)
        {
        case 0:
            return piO4 + tiny;
        case 1:
            return -piO4 - tiny;
        case 2:
            return 3.0 * piO4 + tiny;
        default:
            return -3.0 * piO4 - tiny;
        }
    }
    switch (m)
    {
    case 0:
        return 0.0;
    case 1:
        return -0.0;
    case 2:
        return PI_CONST + tiny;
    default:
        return -PI_CONST - tiny;
    }
}

private bool atan2Special(double y, int ix, int lx, int hy, int iy, int ly, int m, out double res) pure nothrow @nogc
{
    enum double tiny = 1.0e-300;
    enum double piO2 = 0x1.921fb54442d18p0;

    if ((iy | ly) == 0)
    {
        if (m < 2)
            res = y;
        else
            res = m == 2 ? PI_CONST + tiny : -PI_CONST - tiny;
        return true;
    }
    if ((ix | lx) == 0 || iy == EXP_BITS)
    {
        if (ix == EXP_BITS)
            res = atan2InfX(m, iy);
        else
            res = hy < 0 ? -piO2 - tiny : piO2 + tiny;
        return true;
    }
    if (ix == EXP_BITS)
    {
        res = atan2InfX(m, iy);
        return true;
    }
    res = 0.0;
    return false;
}

/// Bit-exact FDLIBM two-argument arctangent (`FdLibm.Atan2.compute`).
package(flint.java) double fdAtan2(double y, double x) pure nothrow @nogc
{
    enum double piO2 = 0x1.921fb54442d18p0;
    enum double piLo = 0x1.1a62633145c07p-53;

    if (x != x || y != y)
        return x + y;

    const int hx = __HI(x);
    const int ix = hx & EXP_SIGNIF_BITS;
    const int lx = __LO(x);
    const int hy = __HI(y);
    const int iy = hy & EXP_SIGNIF_BITS;
    const int ly = __LO(y);

    if (((hx - 0x3ff0_0000) | lx) == 0)
        return fdAtan(y);

    const int m = ((hy >> 31) & 1) | ((hx >> 30) & 2);
    double special;
    if (atan2Special(y, ix, lx, hy, iy, ly, m, special))
        return special;

    const int k = (iy - ix) >> 20;
    double z;
    if (k > 60)
        z = piO2 + 0.5 * piLo;
    else if (hx < 0 && k < -60)
        z = 0.0;
    else
        z = fdAtan(absD(y / x));

    switch (m)
    {
    case 0:
        return z;
    case 1:
        return -z;
    case 2:
        return PI_CONST - (z - piLo);
    default:
        return (z - piLo) - PI_CONST;
    }
}
