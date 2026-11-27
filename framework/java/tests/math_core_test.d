module math_core_test;

import core.memory : GC;
import flint.java.lang.math : Math;

@safe:

private union DoubleBits
{
    double value;
    ulong bits;
}

private union FloatBits
{
    float value;
    uint bits;
}

private ulong dbits(double d) pure nothrow @nogc
{
    DoubleBits u = void;
    u.value = d;
    return u.bits;
}

private double fromDbits(ulong bits) pure nothrow @nogc
{
    DoubleBits u = void;
    u.bits = bits;
    return u.value;
}

private uint fbits(float f) pure nothrow @nogc
{
    FloatBits u = void;
    u.value = f;
    return u.bits;
}

private float fromFbits(uint bits) pure nothrow @nogc
{
    FloatBits u = void;
    u.bits = bits;
    return u.value;
}

private bool sameDouble(double a, double b) pure nothrow @nogc
{
    if (a != a && b != b)
        return true;
    return dbits(a) == dbits(b);
}

private bool sameFloat(float a, float b) pure nothrow @nogc
{
    if (a != a && b != b)
        return true;
    return fbits(a) == fbits(b);
}

// The bit-reading members cannot run in CTFE, so they never fold at real precision (see Math's documentation).
static assert(!__traits(compiles, { enum x = Math.rint(0.5); }));
static assert(!__traits(compiles, { enum x = Math.floor(-0.5); }));
static assert(!__traits(compiles, { enum x = Math.ceil(-0.5); }));
static assert(!__traits(compiles, { enum x = Math.round(0.49999999999999994); }));
static assert(!__traits(compiles, { enum x = Math.round(0.5f); }));

@("Math rint, floor and round keep exact double rounding at run time")
unittest
{
    assert(sameDouble(Math.rint(0.5), 0.0));
    assert(sameDouble(Math.rint(1.5), 2.0));
    assert(sameDouble(Math.rint(2.5), 2.0));
    assert(sameDouble(Math.rint(0x1p52 - 0.5), 0x1p52));
    assert(sameDouble(Math.floor(-0.5), -1.0));
    assert(Math.round(0.49999999999999994) == 0);
}

@("Math constants and angle conversions match Java 21 bits")
unittest
{
    static assert(!__traits(compiles, Math()));
    assert(dbits(Math.E) == 0x4005_BF0A_8B14_5769UL);
    assert(dbits(Math.PI) == 0x4009_21FB_5444_2D18UL);
    assert(dbits(Math.TAU) == 0x4019_21FB_5444_2D18UL);
    assert(dbits(Math.toRadians(180.0)) == 0x4009_21FB_5444_2D18UL);
    assert(dbits(Math.toDegrees(Math.PI)) == 0x4066_8000_0000_0000UL);
    assert(sameDouble(Math.toRadians(-0.0), -0.0));
    assert(sameDouble(Math.toDegrees(-0.0), -0.0));
}

@("Math integer abs, min, max, multiplyFull, multiplyHigh, unsignedMultiplyHigh")
unittest
{
    assert(Math.abs(0) == 0);
    assert(Math.abs(-42) == 42);
    assert(Math.abs(int.max) == int.max);
    assert(Math.abs(int.min) == int.min);
    assert(Math.abs(0L) == 0L);
    assert(Math.abs(-42L) == 42L);
    assert(Math.abs(long.max) == long.max);
    assert(Math.abs(long.min) == long.min);

    assert(Math.min(3, -5) == -5 && Math.max(3, -5) == 3);
    assert(Math.min(int.min, int.max) == int.min && Math.max(int.min, int.max) == int.max);
    assert(Math.min(3L, -5L) == -5L && Math.max(3L, -5L) == 3L);
    assert(Math.min(long.min, long.max) == long.min && Math.max(long.min, long.max) == long.max);

    assert(Math.multiplyFull(int.max, int.max) == 4_611_686_014_132_420_609L);
    assert(Math.multiplyFull(int.min, int.min) == 4_611_686_018_427_387_904L);
    assert(Math.multiplyFull(int.min, int.max) == -4_611_686_016_279_904_256L);

    assert(Math.multiplyHigh(long.max, long.max) == 0x3FFF_FFFF_FFFF_FFFFL);
    assert(Math.multiplyHigh(long.min, long.min) == 0x4000_0000_0000_0000L);
    assert(Math.multiplyHigh(long.min, long.max) == -0x4000_0000_0000_0000L);
    assert(Math.multiplyHigh(-1L, -1L) == 0L);
    assert(Math.multiplyHigh(-1L, 1L) == -1L);
    assert(Math.multiplyHigh(0x1234_5678_9ABC_DEF0L, 0x0FED_CBA9_8765_4321L) == 0x0121_FA00_AD77_D742L);

    assert(Math.unsignedMultiplyHigh(-1L, -1L) == -2L);
    assert(Math.unsignedMultiplyHigh(-1L, 2L) == 1L);
    assert(Math.unsignedMultiplyHigh(long.min, long.min) == 0x4000_0000_0000_0000L);
    assert(Math.unsignedMultiplyHigh(long.min, 2L) == 1L);
    assert(Math.unsignedMultiplyHigh(0x1234_5678_9ABC_DEF0L, -1L) == 0x1234_5678_9ABC_DEEFL);
}

@("Math floating-point abs, min, max, signum, copySign, getExponent")
unittest
{
    assert(sameDouble(Math.abs(-0.0), 0.0));
    assert(sameDouble(Math.abs(-double.infinity), double.infinity));
    assert(Math.abs(double.nan) != Math.abs(double.nan));
    assert(sameFloat(Math.abs(-0.0f), 0.0f));
    assert(sameFloat(Math.abs(-float.infinity), float.infinity));
    assert(Math.abs(float.nan) != Math.abs(float.nan));

    assert(sameDouble(Math.max(-0.0, 0.0), 0.0));
    assert(sameDouble(Math.max(0.0, -0.0), 0.0));
    assert(sameDouble(Math.max(-0.0, -0.0), -0.0));
    assert(sameDouble(Math.min(-0.0, 0.0), -0.0));
    assert(sameDouble(Math.min(0.0, -0.0), -0.0));
    assert(sameDouble(Math.min(0.0, 0.0), 0.0));
    assert(Math.max(double.nan, 1.0) != Math.max(double.nan, 1.0));
    assert(Math.max(1.0, double.nan) != Math.max(1.0, double.nan));
    assert(Math.min(double.nan, 1.0) != Math.min(double.nan, 1.0));
    assert(Math.min(1.0, double.nan) != Math.min(1.0, double.nan));

    assert(sameFloat(Math.max(-0.0f, 0.0f), 0.0f));
    assert(sameFloat(Math.max(0.0f, -0.0f), 0.0f));
    assert(sameFloat(Math.min(-0.0f, 0.0f), -0.0f));
    assert(sameFloat(Math.min(0.0f, -0.0f), -0.0f));
    assert(Math.max(float.nan, 1.0f) != Math.max(float.nan, 1.0f));
    assert(Math.min(1.0f, float.nan) != Math.min(1.0f, float.nan));

    assert(sameDouble(Math.signum(0.0), 0.0));
    assert(sameDouble(Math.signum(-0.0), -0.0));
    assert(sameDouble(Math.signum(42.5), 1.0));
    assert(sameDouble(Math.signum(-0x1p-1074), -1.0));
    assert(sameDouble(Math.signum(double.nan), double.nan));
    assert(sameFloat(Math.signum(0.0f), 0.0f));
    assert(sameFloat(Math.signum(-0.0f), -0.0f));
    assert(sameFloat(Math.signum(-0x1p-149f), -1.0f));
    assert(sameFloat(Math.signum(float.nan), float.nan));

    assert(sameDouble(Math.copySign(3.5, -0.0), -3.5));
    assert(sameDouble(Math.copySign(-3.5, 0.0), 3.5));
    assert(sameFloat(Math.copySign(3.5f, -0.0f), -3.5f));
    assert(sameFloat(Math.copySign(-3.5f, 0.0f), 3.5f));

    assert(Math.getExponent(0.0) == -1023);
    assert(Math.getExponent(-0.0) == -1023);
    assert(Math.getExponent(0x1p-1074) == -1023);
    assert(Math.getExponent(0x1p-1022) == -1022);
    assert(Math.getExponent(1.0) == 0);
    assert(Math.getExponent(double.max) == 1023);
    assert(Math.getExponent(double.infinity) == 1024);
    assert(Math.getExponent(double.nan) == 1024);

    assert(Math.getExponent(0.0f) == -127);
    assert(Math.getExponent(0x1p-149f) == -127);
    assert(Math.getExponent(0x1p-126f) == -126);
    assert(Math.getExponent(1.0f) == 0);
    assert(Math.getExponent(float.max) == 127);
    assert(Math.getExponent(float.infinity) == 128);
    assert(Math.getExponent(float.nan) == 128);
}

@("Math ceil, floor, rint, round match Java 21 edge cases")
unittest
{
    assert(sameDouble(Math.ceil(-0.5), -0.0));
    assert(sameDouble(Math.ceil(-0.0), -0.0));
    assert(sameDouble(Math.ceil(0.0), 0.0));
    assert(sameDouble(Math.ceil(0x1p-1074), 1.0));
    assert(sameDouble(Math.ceil(-1.5), -1.0));
    assert(sameDouble(Math.ceil(1.5), 2.0));
    assert(sameDouble(Math.ceil(0x1p52), 0x1p52));
    assert(sameDouble(Math.ceil(double.infinity), double.infinity));
    assert(sameDouble(Math.ceil(double.nan), double.nan));

    assert(sameDouble(Math.floor(-0.5), -1.0));
    assert(sameDouble(Math.floor(-0.0), -0.0));
    assert(sameDouble(Math.floor(0.0), 0.0));
    assert(sameDouble(Math.floor(0.9999999999999999), 0.0));
    assert(sameDouble(Math.floor(-1.0), -1.0));
    assert(sameDouble(Math.floor(1.5), 1.0));
    assert(sameDouble(Math.floor(-double.infinity), -double.infinity));
    assert(sameDouble(Math.floor(double.nan), double.nan));

    assert(sameDouble(Math.rint(0.5), 0.0));
    assert(sameDouble(Math.rint(-0.5), -0.0));
    assert(sameDouble(Math.rint(1.5), 2.0));
    assert(sameDouble(Math.rint(-1.5), -2.0));
    assert(sameDouble(Math.rint(2.5), 2.0));
    assert(sameDouble(Math.rint(-2.5), -2.0));
    assert(sameDouble(Math.rint(-0.0), -0.0));
    assert(sameDouble(Math.rint(0x1p51 + 0.5), 0x1p51));
    assert(sameDouble(Math.rint(0x1p52 - 0.5), 0x1p52));
    assert(sameDouble(Math.rint(double.infinity), double.infinity));

    // Java 6 regression edge cases + saturation + NaN
    assert(Math.round(0.49999997f) == 0);
    assert(Math.round(0.5f) == 1);
    assert(Math.round(-0.5f) == 0);
    assert(Math.round(-0.50000006f) == -1);
    assert(Math.round(float.nan) == 0);
    assert(Math.round(float.infinity) == int.max);
    assert(Math.round(-float.infinity) == int.min);
    assert(Math.round(0x1p31f) == int.max);
    assert(Math.round(-0x1p31f) == int.min);
    assert(Math.round(0x1.fffffep30f) == 2_147_483_520);

    assert(Math.round(fromDbits(0x3FDF_FFFF_FFFF_FFFFUL)) == 0L); // nextDown(0.5)
    assert(Math.round(0.5) == 1L);
    assert(Math.round(-0.5) == 0L);
    assert(Math.round(fromDbits(0xBFE0_0000_0000_0001UL)) == -1L); // nextDown(-0.5)
    assert(Math.round(double.nan) == 0L);
    assert(Math.round(double.infinity) == long.max);
    assert(Math.round(-double.infinity) == long.min);
    assert(Math.round(0x1p63) == long.max);
    assert(Math.round(-0x1p63) == long.min);
    assert(Math.round(0x1.fffffffffffffp62) == 9_223_372_036_854_774_784L);
}

@("Math ulp, nextUp, nextDown, nextAfter, scalb match Java 21")
unittest
{
    assert(sameDouble(Math.ulp(0.0), 0x1p-1074));
    assert(sameDouble(Math.ulp(-0.0), 0x1p-1074));
    assert(sameDouble(Math.ulp(0x1p-1022), 0x1p-1074));
    assert(sameDouble(Math.ulp(1.0), 0x1p-52));
    assert(sameDouble(Math.ulp(double.max), 0x1p971));
    assert(sameDouble(Math.ulp(-double.infinity), double.infinity));
    assert(sameDouble(Math.ulp(double.nan), double.nan));

    assert(sameFloat(Math.ulp(0.0f), 0x1p-149f));
    assert(sameFloat(Math.ulp(-0.0f), 0x1p-149f));
    assert(sameFloat(Math.ulp(0x1p-126f), 0x1p-149f));
    assert(sameFloat(Math.ulp(1.0f), 0x1p-23f));
    assert(sameFloat(Math.ulp(float.max), 0x1p104f));
    assert(sameFloat(Math.ulp(-float.infinity), float.infinity));

    assert(sameDouble(Math.nextUp(-0.0), 0x1p-1074));
    assert(sameDouble(Math.nextUp(0.0), 0x1p-1074));
    assert(sameDouble(Math.nextUp(-0x1p-1074), -0.0));
    assert(sameDouble(Math.nextUp(double.max), double.infinity));
    assert(sameDouble(Math.nextUp(double.infinity), double.infinity));
    assert(sameDouble(Math.nextUp(-double.infinity), -double.max));
    assert(sameDouble(Math.nextDown(0.0), -0x1p-1074));
    assert(sameDouble(Math.nextDown(-0.0), -0x1p-1074));
    assert(sameDouble(Math.nextDown(0x1p-1074), 0.0));
    assert(sameDouble(Math.nextDown(-double.max), -double.infinity));
    assert(sameDouble(Math.nextDown(-double.infinity), -double.infinity));
    assert(sameDouble(Math.nextDown(double.infinity), double.max));

    assert(sameFloat(Math.nextUp(-0.0f), 0x1p-149f));
    assert(sameFloat(Math.nextUp(-0x1p-149f), -0.0f));
    assert(sameFloat(Math.nextDown(0.0f), -0x1p-149f));
    assert(sameFloat(Math.nextDown(0x1p-149f), 0.0f));

    assert(sameDouble(Math.nextAfter(0.0, -0.0), -0.0));
    assert(sameDouble(Math.nextAfter(-0.0, 0.0), 0.0));
    assert(sameDouble(Math.nextAfter(0.0, -1.0), -0x1p-1074));
    assert(sameDouble(Math.nextAfter(-0.0, 1.0), 0x1p-1074));
    assert(sameDouble(Math.nextAfter(double.infinity, 0.0), double.max));
    assert(sameDouble(Math.nextAfter(-double.infinity, 0.0), -double.max));

    assert(sameFloat(Math.nextAfter(0.0f, -0.0), -0.0f));
    assert(sameFloat(Math.nextAfter(-0.0f, 0.0), 0.0f));
    assert(sameFloat(Math.nextAfter(1.0f, 1.0 + 0x1p-52), fromFbits(fbits(1.0f) + 1)));
    assert(sameFloat(Math.nextAfter(1.0f, 1.0 - 0x1p-53), fromFbits(fbits(1.0f) - 1)));

    assert(sameDouble(Math.scalb(1.5, 3), 12.0));
    assert(sameDouble(Math.scalb(1.0, -1074), 0x1p-1074));
    assert(sameDouble(Math.scalb(0x1p-1074, 1074), 1.0));
    assert(sameDouble(Math.scalb(double.max, -2097), 0x1p-1073));
    assert(sameDouble(Math.scalb(-double.max, int.min), -0.0));
    assert(sameDouble(Math.scalb(-0x1p-1074, int.max), -double.infinity));
    assert(sameDouble(Math.scalb(-0.0, 1000), -0.0));
    assert(sameDouble(Math.scalb(double.nan, 10), double.nan));

    assert(sameFloat(Math.scalb(1.5f, 3), 12.0f));
    assert(sameFloat(Math.scalb(1.0f, -149), 0x1p-149f));
    assert(sameFloat(Math.scalb(0x1p-149f, 149), 1.0f));
    assert(sameFloat(Math.scalb(-float.max, int.min), -0.0f));
    assert(sameFloat(Math.scalb(-0x1p-149f, int.max), -float.infinity));
}

@("Math core operations perform zero GC allocations")
unittest
{
    // Warm up
    auto acc = Math.scalb(Math.rint(Math.ceil(Math.floor(1.5))), 2);
    const before = GC.stats.allocatedInCurrentThread;
    foreach (i; -8 .. 9)
    {
        const d = cast(double) i * 0.5;
        const f = cast(float) i * 0.5f;
        acc += Math.abs(d) + Math.min(d, -0.0) + Math.max(d, 0.0) + Math.signum(d);
        acc += Math.copySign(Math.ulp(d), -d) + Math.nextAfter(Math.nextUp(Math.nextDown(d)), 0.0);
        acc += Math.scalb(Math.ceil(d) + Math.floor(d) + Math.rint(d), i);
        acc += cast(double)(Math.round(f) + Math.round(d) + Math.getExponent(f) + Math.getExponent(d));
        acc += cast(double)(Math.multiplyHigh(i, long.max) ^ Math.unsignedMultiplyHigh(i, -1L));
    }
    const after = GC.stats.allocatedInCurrentThread;
    assert(after == before);
    assert(acc == acc);
}

@("Math fma rounds the exact product and sum once")
unittest
{
    // The unfused 0.1 * 10.0 - 1.0 rounds the product to 1.0 first and gives 0.0.
    const tenth = 0.1;
    assert(tenth * 10.0 - 1.0 == 0.0 && sameDouble(Math.fma(tenth, 10.0, -1.0), 0x1p-54));
    const u = 1 + 0x1p-52;
    assert(sameDouble(Math.fma(u, u, -(u * u)), 0x1p-104));
    const v = 1 + 0x1p-23f;
    assert(sameFloat(Math.fma(0.1f, 10.0f, -1.0f), 0x1p-26f) && sameFloat(Math.fma(v, v, -(v * v)), 0x1p-46f));

    // An intermediate overflow neither saturates nor becomes NaN against an infinite addend.
    assert(sameDouble(Math.fma(double.max, 2.0, -double.max), double.max));
    assert(sameDouble(Math.fma(double.max, 2.0, -double.infinity), -double.infinity));
    assert(sameFloat(Math.fma(float.max, 2.0f, -float.max), float.max));
    assert(sameFloat(Math.fma(float.max, 2.0f, -float.infinity), -float.infinity));
    assert(sameDouble(Math.fma(double.infinity, 0.0, 1.0), double.nan));
    assert(sameDouble(Math.fma(double.infinity, 1.0, -double.infinity), double.nan));
    assert(sameDouble(Math.fma(1.0, 1.0, double.nan), double.nan));
    assert(sameFloat(Math.fma(float.nan, 1.0f, 1.0f), float.nan));
}

@("Math fma signed zeros and subnormal rounding follow Java")
unittest
{
    assert(dbits(Math.fma(-0.0, 1.0, 0.0)) == 0 && dbits(Math.fma(-0.0, 1.0, -0.0)) == 0x8000_0000_0000_0000UL);
    // A nonzero product that underflows keeps its own sign; an exact zero sum is +0.0.
    assert(dbits(Math.fma(1e-200, -1e-200, 0.0)) == 0x8000_0000_0000_0000UL);
    assert(dbits(Math.fma(1e-200, 1e-200, -0.0)) == 0);
    assert(dbits(Math.fma(2.0, 3.0, -6.0)) == 0 && dbits(Math.fma(-2.0, 3.0, 6.0)) == 0);
    assert(sameDouble(Math.fma(0x1p-537, 0x1p-537, 0x1p-1074), 0x1p-1073));
    // 2^-1075 is a tie between 0 and the smallest subnormal, so it rounds to even (0); 1.5 * 2^-1075 rounds up.
    assert(dbits(Math.fma(0x1p-538, 0x1p-537, 0.0)) == 0 && dbits(Math.fma(0x1.8p-538, 0x1p-537, 0.0)) == 1);
    assert(fbits(Math.fma(0x1p-75f, 0x1p-75f, 0.0f)) == 0 && fbits(Math.fma(0x1.8p-75f, 0x1p-75f, 0.0f)) == 1);
}

// fma is usable from nothrow @nogc code (fmaNoGc compiles); the bit-reading core keeps it out of CTFE.
private double fmaNoGc() pure nothrow @nogc
{
    return Math.fma(1.0, 2.0, 3.0) + Math.fma(1.0f, 2.0f, 3.0f);
}

static assert(!__traits(compiles, { enum x = Math.fma(1.0, 2.0, 3.0); }));

@("Math sqrt, cbrt, hypot and IEEEremainder match Java special cases and exact values")
unittest
{
    // sqrt special cases, subnormals and exact roots
    assert(dbits(Math.sqrt(0.0)) == 0);
    assert(dbits(Math.sqrt(-0.0)) == 0x8000_0000_0000_0000UL);
    assert(sameDouble(Math.sqrt(double.infinity), double.infinity));
    assert(sameDouble(Math.sqrt(-double.infinity), double.nan));
    assert(sameDouble(Math.sqrt(-1.0), double.nan));
    assert(sameDouble(Math.sqrt(-double.min_normal), double.nan));
    assert(sameDouble(Math.sqrt(double.nan), double.nan));
    assert(sameDouble(Math.sqrt(4.0), 2.0));
    assert(sameDouble(Math.sqrt(0x1p-1074), 0x1p-537));
    assert(sameDouble(Math.sqrt(fromDbits(0x0000_0000_8000_0001UL)), fromDbits(0x1f56_a09e_6695_dc6bUL)));

    // cbrt special cases, signs and exact cubes
    assert(dbits(Math.cbrt(0.0)) == 0);
    assert(dbits(Math.cbrt(-0.0)) == 0x8000_0000_0000_0000UL);
    assert(sameDouble(Math.cbrt(double.infinity), double.infinity));
    assert(sameDouble(Math.cbrt(-double.infinity), -double.infinity));
    assert(sameDouble(Math.cbrt(double.nan), double.nan));
    assert(sameDouble(Math.cbrt(27.0), 3.0));
    assert(sameDouble(Math.cbrt(-27.0), -3.0));
    assert(sameDouble(Math.cbrt(0x1p-1074), 0x1p-358));

    // hypot special cases (Inf wins over NaN!) and scaling without overflow/underflow
    assert(sameDouble(Math.hypot(double.infinity, double.nan), double.infinity));
    assert(sameDouble(Math.hypot(double.nan, -double.infinity), double.infinity));
    assert(sameDouble(Math.hypot(double.nan, 1.0), double.nan));
    assert(dbits(Math.hypot(-0.0, -0.0)) == 0);
    assert(sameDouble(Math.hypot(3.0, 4.0), 5.0));
    assert(sameDouble(Math.hypot(3.0 * 0x1p600, 4.0 * 0x1p600), 5.0 * 0x1p600));
    assert(sameDouble(Math.hypot(3.0 * 0x1p-1074, 4.0 * 0x1p-1074), 5.0 * 0x1p-1074));

    // IEEEremainder special cases, ties-to-even and signed zero
    assert(sameDouble(Math.IEEEremainder(1.0, 0.0), double.nan));
    assert(sameDouble(Math.IEEEremainder(double.infinity, 1.0), double.nan));
    assert(sameDouble(Math.IEEEremainder(double.nan, 1.0), double.nan));
    assert(sameDouble(Math.IEEEremainder(1.0, double.nan), double.nan));
    assert(sameDouble(Math.IEEEremainder(5.0, double.infinity), 5.0));
    assert(sameDouble(Math.IEEEremainder(-5.0, double.infinity), -5.0));
    assert(sameDouble(Math.IEEEremainder(3.0, 2.0), -1.0)); // 3 / 2 = 1.5 -> nearest even is 2
    assert(sameDouble(Math.IEEEremainder(5.0, 2.0), 1.0)); // 5 / 2 = 2.5 -> nearest even is 2
    assert(dbits(Math.IEEEremainder(4.0, 2.0)) == 0);
    assert(dbits(Math.IEEEremainder(-4.0, 2.0)) == 0x8000_0000_0000_0000UL);
    assert(sameDouble(Math.IEEEremainder(0x1p-1073, 0x1p-1074), 0.0));
}

private double fdlibmSlice1NoGc() pure nothrow @nogc
{
    return Math.sqrt(2.0) + Math.cbrt(2.0) + Math.hypot(3.0, 4.0) + Math.IEEEremainder(5.0, 2.0);
}
