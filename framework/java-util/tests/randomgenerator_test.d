/*
 * Copyright (c) 2026 the Flint authors.
 * SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
 */
module randomgenerator_test;

import flint.java.util.random : RandomGenerator;

@safe:

// java.util.Random belongs to java.util, never re-exported from flint.java.util.random.
static assert(!__traits(compiles, { import flint.java.util.random : Random; }));

private uint floatBits(float value) pure nothrow @nogc
{
    union Bits
    {
        float f;
        uint u;
    }

    Bits bits = Bits(value);
    return bits.u;
}

private ulong doubleBits(double value) pure nothrow @nogc
{
    union Bits
    {
        double d;
        ulong u;
    }

    Bits bits = Bits(value);
    return bits.u;
}

private final class FixedGenerator : RandomGenerator
{
    private const(long)[] values;
    private size_t cursor;

    this(const(long)[] values...) pure nothrow
    {
        this.values = values.dup;
    }

    override long nextLong()
    {
        return values[cursor++];
    }

    mixin RandomGenerator.Defaults;
}

private final class DummyArbitraryGenerator : RandomGenerator.ArbitrarilyJumpableGenerator
{
    private long state;
    private int lastPowerOfTwo;

    this(long state) pure nothrow @nogc
    {
        this.state = state;
    }

    override long nextLong()
    {
        return ++state;
    }

    mixin RandomGenerator.Defaults;
    mixin RandomGenerator.JumpableGenerator.Defaults;
    mixin RandomGenerator.LeapableGenerator.Defaults;
    mixin RandomGenerator.ArbitrarilyJumpableGenerator.Defaults;

    override RandomGenerator.ArbitrarilyJumpableGenerator copy()
    {
        return new DummyArbitraryGenerator(state);
    }

    override double jumpDistance()
    {
        return 10.0;
    }

    override double leapDistance()
    {
        return 100.0;
    }

    override void jumpPowerOfTwo(int logDistance)
    {
        lastPowerOfTwo = logDistance;
        state += 1L << logDistance;
    }

    override void jump(double distance)
    {
        state += cast(long) distance;
    }
}

private final class DummySplittableGenerator : RandomGenerator.SplittableGenerator
{
    private long state;

    this(long state) pure nothrow @nogc
    {
        this.state = state;
    }

    override long nextLong()
    {
        return ++state;
    }

    mixin RandomGenerator.Defaults;

    override RandomGenerator.SplittableGenerator split()
    {
        return new DummySplittableGenerator(nextLong());
    }

    override RandomGenerator.SplittableGenerator split(RandomGenerator.SplittableGenerator source)
    {
        return new DummySplittableGenerator(source.nextLong());
    }
}

@("RandomGenerator default methods match Java SE 21 bit-for-bit")
unittest
{
    struct Case
    {
        long input;
        bool expectedBool;
        int expectedInt;
        uint expectedFloatBits;
        ulong expectedDoubleBits;
        byte b0;
        byte b7;
        byte b8;
    }

    // Verified against OpenJDK 21.0.13.1 java.util.random.RandomGenerator default methods.
    static immutable Case[] cases = [
        Case(0x0000000000000000L, false, 0, 0x00000000U, 0x0000000000000000UL, 0, 0, -1),
        Case(0x0000000000000001L, false, 0, 0x00000000U, 0x0000000000000000UL, 1, 0, -2),
        Case(cast(long) 0xffffffffffffffffUL, true, -1, 0x3f7fffffU, 0x3fefffffffffffffUL, -1,
                -1, 0),
        Case(cast(long) 0x8000000000000000UL, true, int.min, 0x3f000000U, 0x3fe0000000000000UL, 0,
                -128, -1),
        Case(0x7fffffffffffffffL, false, int.max, 0x3efffffeU, 0x3fdffffffffffffeUL, -1, 127,
                0),
        Case(0x0123456789abcdefL, false, 19_088_743, 0x3b91a280U, 0x3f723456789abc80UL, -17, 1,
                16),
        Case(cast(long) 0xfedcba9876543210UL, true, -19_088_744, 0x3f7edcbaU,
                0x3fefdb97530eca86UL, 16, -2, -17),
        Case(0x00000000ffffffffL, false, 0, 0x00000000U, 0x3defffff00000000UL, -1, 0, 0),
        Case(cast(long) 0xffffffff00000000UL, true, -1, 0x3f7fffffU, 0x3fefffffffe00000UL, 0,
                -1, -1),
        Case(0x1234567890abcdefL, false, 305_419_896, 0x3d91a2b0U, 0x3fb234567890abc8UL, -17, 18, 16),
    ];

    foreach (c; cases)
    {
        RandomGenerator gDep = new FixedGenerator(c.input);
        assert(!gDep.isDeprecated());
        RandomGenerator gBool = new FixedGenerator(c.input);
        assert(gBool.nextBoolean() == c.expectedBool);
        RandomGenerator gInt = new FixedGenerator(c.input);
        assert(gInt.nextInt() == c.expectedInt);
        RandomGenerator gFloat = new FixedGenerator(c.input);
        assert(floatBits(gFloat.nextFloat()) == c.expectedFloatBits);
        RandomGenerator gDouble = new FixedGenerator(c.input);
        assert(doubleBits(gDouble.nextDouble()) == c.expectedDoubleBits);

        byte[9] bytes;
        RandomGenerator gBytes = new FixedGenerator(c.input, ~c.input);
        gBytes.nextBytes(bytes[]);
        assert(bytes[0] == c.b0);
        assert(bytes[7] == c.b7);
        assert(bytes[8] == c.b8);
    }

    // R26: null and empty byte slices consume no generator output.
    auto emptyGen = new FixedGenerator(42L);
    emptyGen.nextBytes(null);
    byte[0] zero;
    emptyGen.nextBytes(zero[]);
    assert(emptyGen.nextLong() == 42L);

    // Non-multiple of 8 lengths (1, 7, 8, 17).
    byte[17] partial;
    auto multi = new FixedGenerator(0x0807060504030201L, 0x100f0e0d0c0b0a09L, 0x1817161514131211L);
    multi.nextBytes(partial[]);
    foreach (i; 0 .. 17)
        assert(partial[i] == cast(byte)(i + 1));
}

@("RandomGenerator subinterfaces preserve copy-before-advance and split semantics")
unittest
{
    auto gen = new DummyArbitraryGenerator(100);
    RandomGenerator.JumpableGenerator jumpable = gen;
    RandomGenerator.LeapableGenerator leapable = gen;
    RandomGenerator.ArbitrarilyJumpableGenerator arb = gen;
    RandomGenerator.StreamableGenerator streamable = gen;
    assert(!streamable.isDeprecated());

    // copyAndJump returns the pre-jump copy while advancing the receiver by jumpDistance (10).
    RandomGenerator beforeJump = jumpable.copyAndJump();
    assert(beforeJump.nextLong() == 101);
    assert(gen.nextLong() == 111);

    // copyAndLeap returns the pre-leap copy while advancing the receiver by leapDistance (100).
    RandomGenerator.JumpableGenerator beforeLeap = leapable.copyAndLeap();
    assert(beforeLeap.nextLong() == 112);
    assert(gen.nextLong() == 212);

    // ArbitrarilyJumpableGenerator.copyAndJump(distance) copies first, then advances by distance.
    RandomGenerator.ArbitrarilyJumpableGenerator beforeCustom = arb.copyAndJump(25.0);
    assert(beforeCustom.nextLong() == 213);
    assert(gen.nextLong() == 238);

    arb.jumpPowerOfTwo(4);
    assert(gen.lastPowerOfTwo == 4);
    assert(gen.nextLong() == 255);

    auto splittable = new DummySplittableGenerator(50);
    auto source = new DummySplittableGenerator(500);
    RandomGenerator.SplittableGenerator child1 = splittable.split();
    RandomGenerator.SplittableGenerator child2 = splittable.split(source);
    assert(child1.nextLong() == 52);
    assert(child2.nextLong() == 502);
}
