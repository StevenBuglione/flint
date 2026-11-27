// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module flint.java.lang.strictmath_test;

import flint.java.lang : ArithmeticException, IllegalArgumentException;
import flint.java.lang.strictmath : StrictMath;

@safe:

private long doubleBits(double d) pure nothrow @nogc
{
    union U
    {
        double v;
        long b;
    }

    U u = void;
    u.v = d;
    return u.b;
}

private int floatBits(float f) pure nothrow @nogc
{
    union U
    {
        float v;
        int b;
    }

    U u = void;
    u.v = f;
    return u.b;
}

private double bitsToDouble(long b) pure nothrow @nogc
{
    union U
    {
        double v;
        long b;
    }

    U u = void;
    u.b = b;
    return u.v;
}

private float bitsToFloat(int b) pure nothrow @nogc
{
    union U
    {
        float v;
        int b;
    }

    U u = void;
    u.b = b;
    return u.v;
}

@("StrictMath constants and core IEEE-754 operations are pure nothrow @nogc and match Java 21")
unittest
{
    static void checkCore() pure nothrow @nogc
    {
        assert(doubleBits(StrictMath.E) == 0x4005_BF0A_8B14_5769L);
        assert(doubleBits(StrictMath.PI) == 0x4009_21FB_5444_2D18L);
        assert(doubleBits(StrictMath.TAU) == 0x4019_21FB_5444_2D18L);

        assert(doubleBits(StrictMath.toRadians(180.0)) == doubleBits(StrictMath.PI));
        assert(doubleBits(StrictMath.toDegrees(StrictMath.PI)) == doubleBits(180.0));
        assert(doubleBits(StrictMath.ceil(-0.5)) == cast(long) 0x8000_0000_0000_0000UL);
        assert(doubleBits(StrictMath.floor(-0.5)) == doubleBits(-1.0));
        assert(doubleBits(StrictMath.rint(2.5)) == doubleBits(2.0));
        assert(doubleBits(StrictMath.rint(-0.5)) == cast(long) 0x8000_0000_0000_0000UL);

        assert(StrictMath.round(-0.5f) == 0);
        assert(StrictMath.round(double.infinity) == long.max);
        assert(StrictMath.round(-double.infinity) == long.min);
        assert(StrictMath.round(double.nan) == 0);

        assert(StrictMath.multiplyFull(int.min, int.min) == (cast(long) int.min) * (cast(long) int.min));
        assert(StrictMath.multiplyHigh(long.min, long.min) == (1L << 62));
        assert(StrictMath.unsignedMultiplyHigh(-1L, -1L) == -2L);

        assert(StrictMath.abs(int.min) == int.min);
        assert(StrictMath.abs(long.min) == long.min);
        assert(floatBits(StrictMath.abs(-0.0f)) == 0);
        assert(doubleBits(StrictMath.abs(-0.0)) == 0);
        assert(doubleBits(StrictMath.max(-0.0, 0.0)) == 0);
        assert(doubleBits(StrictMath.min(-0.0, 0.0)) == cast(long) 0x8000_0000_0000_0000UL);
        assert(floatBits(StrictMath.max(-0.0f, 0.0f)) == 0);
        assert(floatBits(StrictMath.min(-0.0f, 0.0f)) == cast(int) 0x8000_0000U);

        assert(doubleBits(StrictMath.fma(1.0 + 0x1p-52, 1.0 + 0x1p-52, -1.0)) == doubleBits(0x1p-51 + 0x1p-104));
        assert(floatBits(StrictMath.fma(1.0f + 0x1p-23f, 1.0f + 0x1p-23f, -1.0f)) == floatBits(0x1p-22f + 0x1p-46f));

        assert(doubleBits(StrictMath.ulp(0.0)) == 1L);
        assert(floatBits(StrictMath.ulp(0.0f)) == 1);
        assert(doubleBits(StrictMath.signum(-0.0)) == cast(long) 0x8000_0000_0000_0000UL);
        assert(floatBits(StrictMath.signum(-0.0f)) == cast(int) 0x8000_0000U);
        assert(doubleBits(StrictMath.copySign(2.0, -0.0)) == doubleBits(-2.0));
        assert(floatBits(StrictMath.copySign(2.0f, -0.0f)) == floatBits(-2.0f));
        // StrictMath.copySign treats every NaN sign (even with sign bit set) as positive.
        const negNanD = bitsToDouble(cast(long) 0xFFF8_0000_0000_0001UL);
        const negNanF = bitsToFloat(cast(int) 0xFFC0_0001U);
        assert(doubleBits(StrictMath.copySign(-2.0, negNanD)) == doubleBits(2.0));
        assert(floatBits(StrictMath.copySign(-2.0f, negNanF)) == floatBits(2.0f));
        assert(StrictMath.getExponent(1.0) == 0);
        assert(StrictMath.getExponent(1.0f) == 0);
        assert(doubleBits(StrictMath.nextUp(0.0)) == 1L);
        assert(doubleBits(StrictMath.nextDown(0.0)) == cast(long) 0x8000_0000_0000_0001UL);
        assert(floatBits(StrictMath.nextUp(0.0f)) == 1);
        assert(floatBits(StrictMath.nextDown(0.0f)) == cast(int) 0x8000_0001U);
        assert(doubleBits(StrictMath.nextAfter(1.0, 2.0)) == doubleBits(1.0) + 1);
        assert(floatBits(StrictMath.nextAfter(1.0f, 2.0)) == floatBits(1.0f) + 1);
        assert(doubleBits(StrictMath.scalb(1.5, 4)) == doubleBits(24.0));
        assert(floatBits(StrictMath.scalb(1.5f, 4)) == floatBits(24.0f));
    }

    checkCore();
}

@("StrictMath FDLIBM methods are pure nothrow @nogc and bit-exact against Java 21")
unittest
{
    static void checkFdlibm() pure nothrow @nogc
    {
        // Known OpenJDK 21.0.13 StrictMath bit patterns (verified via Temurin oracle)
        assert(doubleBits(StrictMath.sqrt(2.0)) == 0x3FF6_A09E_667F_3BCDL);
        assert(doubleBits(StrictMath.sqrt(-0.0)) == cast(long) 0x8000_0000_0000_0000UL);
        assert(doubleBits(StrictMath.sqrt(-1.0)) == 0x7FF8_0000_0000_0000L);

        assert(doubleBits(StrictMath.cbrt(2.0)) == 0x3FF4_28A2_F98D_728BL);
        assert(doubleBits(StrictMath.cbrt(-8.0)) == doubleBits(-2.0));

        assert(doubleBits(StrictMath.hypot(3.0, 4.0)) == doubleBits(5.0));
        assert(doubleBits(StrictMath.hypot(0x1p1020, 0x1p1020)) == 0x7FB6_A09E_667F_3BCDL);
        assert(doubleBits(StrictMath.hypot(double.infinity, double.nan)) == doubleBits(double.infinity));

        assert(doubleBits(StrictMath.IEEEremainder(5.0, 2.0)) == doubleBits(1.0));
        assert(doubleBits(StrictMath.IEEEremainder(3.0, 2.0)) == doubleBits(-1.0));
        assert(doubleBits(StrictMath.IEEEremainder(1.0, 0.0)) == 0x7FF8_0000_0000_0000L);

        assert(doubleBits(StrictMath.exp(1.0)) == 0x4005_BF0A_8B14_576AL);
        assert(doubleBits(StrictMath.expm1(1e-10)) == 0x3DDB_7CDF_D9DD_A4E3L);
        assert(doubleBits(StrictMath.log(2.0)) == 0x3FE6_2E42_FEFA_39EFL);
        assert(doubleBits(StrictMath.log10(1000.0)) == doubleBits(3.0));
        assert(doubleBits(StrictMath.log1p(1e-10)) == 0x3DDB_7CDF_D9D1_D693L);
        assert(doubleBits(StrictMath.log1p(-2.0)) == 0x7FF8_0000_0000_0000L);
        assert(doubleBits(StrictMath.pow(2.0, 10.0)) == doubleBits(1024.0));
        assert(doubleBits(StrictMath.pow(-2.0, 3.0)) == doubleBits(-8.0));
        assert(doubleBits(StrictMath.pow(1.0, double.nan)) == 0x7FF8_0000_0000_0000L);
        assert(doubleBits(StrictMath.sinh(1.0)) == 0x3FF2_CD9F_C44E_B982L);
        assert(doubleBits(StrictMath.cosh(1.0)) == 0x3FF8_B075_51D9_F551L);
        assert(doubleBits(StrictMath.tanh(1.0)) == 0x3FE8_5EFA_B514_F394L);

        assert(doubleBits(StrictMath.sin(1.0)) == 0x3FEA_ED54_8F09_0CEEL);
        assert(doubleBits(StrictMath.cos(1.0)) == 0x3FE1_4A28_0FB5_068CL);
        assert(doubleBits(StrictMath.tan(1.0)) == 0x3FF8_EB24_5CBE_E3A6L);
        // Large Payne-Hanek range reduction
        assert(doubleBits(StrictMath.sin(0x1p100)) == cast(long) 0xBFEB_E8ED_97AC_1F59UL);
        assert(doubleBits(StrictMath.cos(0x1p100)) == 0x3FDF_4EB3_FF66_E36DL);
        assert(doubleBits(StrictMath.asin(0.5)) == 0x3FE0_C152_382D_7366L);
        assert(doubleBits(StrictMath.acos(0.5)) == 0x3FF0_C152_382D_7366L);
        assert(doubleBits(StrictMath.atan(1.0)) == 0x3FE9_21FB_5444_2D18L);
        assert(doubleBits(StrictMath.atan2(1.0, 1.0)) == 0x3FE9_21FB_5444_2D18L);
        assert(doubleBits(StrictMath.atan2(-0.0, -1.0)) == doubleBits(-StrictMath.PI));
        assert(doubleBits(StrictMath.sin(double.infinity)) == 0x7FF8_0000_0000_0000L);
    }

    checkFdlibm();
}

@("StrictMath exact integer, floor/ceil div/mod, and clamp match Java 21 including exceptions")
unittest
{
    assert(StrictMath.addExact(3, 4) == 7);
    assert(StrictMath.addExact(3L, 4L) == 7L);
    assert(StrictMath.subtractExact(10, 3) == 7);
    assert(StrictMath.subtractExact(10L, 3L) == 7L);
    assert(StrictMath.multiplyExact(6, 7) == 42);
    assert(StrictMath.multiplyExact(6L, 7) == 42L);
    assert(StrictMath.multiplyExact(6L, 7L) == 42L);
    assert(StrictMath.divideExact(7, 2) == 3);
    assert(StrictMath.divideExact(7L, 2L) == 3L);
    assert(StrictMath.floorDivExact(-7, 2) == -4);
    assert(StrictMath.floorDivExact(-7L, 2L) == -4L);
    assert(StrictMath.ceilDivExact(7, 2) == 4);
    assert(StrictMath.ceilDivExact(7L, 2L) == 4L);
    assert(StrictMath.incrementExact(41) == 42);
    assert(StrictMath.incrementExact(41L) == 42L);
    assert(StrictMath.decrementExact(43) == 42);
    assert(StrictMath.decrementExact(43L) == 42L);
    assert(StrictMath.negateExact(-42) == 42);
    assert(StrictMath.negateExact(-42L) == 42L);
    assert(StrictMath.toIntExact(42L) == 42);
    assert(StrictMath.absExact(-42) == 42);
    assert(StrictMath.absExact(-42L) == 42L);

    assert(StrictMath.floorDiv(-7, 2) == -4);
    assert(StrictMath.floorDiv(-7L, 2) == -4L);
    assert(StrictMath.floorDiv(-7L, 2L) == -4L);
    assert(StrictMath.floorMod(-7, 2) == 1);
    assert(StrictMath.floorMod(-7L, 2) == 1);
    assert(StrictMath.floorMod(-7L, 2L) == 1L);
    assert(StrictMath.ceilDiv(7, 2) == 4);
    assert(StrictMath.ceilDiv(7L, 2) == 4L);
    assert(StrictMath.ceilDiv(7L, 2L) == 4L);
    assert(StrictMath.ceilMod(7, 2) == -1);
    assert(StrictMath.ceilMod(7L, 2) == -1);
    assert(StrictMath.ceilMod(7L, 2L) == -1L);

    assert(StrictMath.clamp(100L, 0, 50) == 50);
    assert(StrictMath.clamp(-100L, -50L, 50L) == -50L);
    assert(StrictMath.clamp(2.5, 0.0, 1.0) == 1.0);
    assert(StrictMath.clamp(-2.5f, -1.0f, 1.0f) == -1.0f);
    assert(doubleBits(StrictMath.clamp(0.0, -0.0, 0.0)) == 0);

    bool threw = false;
    try
    {
        cast(void) StrictMath.addExact(int.max, 1);
    }
    catch (ArithmeticException e)
    {
        threw = e.getMessage() == "integer overflow";
    }
    assert(threw);

    threw = false;
    try
    {
        cast(void) StrictMath.divideExact(long.min, -1L);
    }
    catch (ArithmeticException e)
    {
        threw = e.getMessage() == "long overflow";
    }
    assert(threw);

    threw = false;
    try
    {
        cast(void) StrictMath.clamp(0.0, 0.0, -0.0);
    }
    catch (IllegalArgumentException)
    {
        threw = true;
    }
    assert(threw);
}
