/*
 * Copyright (c) 2026 the Flint authors.
 * SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
 */
module splittablerandom_test;

import flint.java.util.random : RandomGenerator;
import flint.java.util.splittablerandom : SplittableRandom;

@safe:

@("SplittableRandom seeded sequences and splits match Java SE 21")
unittest
{
    struct Case
    {
        long seed;
        int i1;
        long l1;
        int i2;
        long l2;
        int ci1;
        long cl1;
        long gl1;
    }

    static immutable Case[] cases = [
        Case(0L, 821_115_357, 7_960_286_522_194_355_700L, 172_035_578, 6_038_094_601_263_162_090L,
                187_882_220, 2_568_919_157_239_051_596L,
                -8_114_207_812_470_266_037L),
        Case(1L, 246_745_853, -4_689_498_862_643_123_097L, 1_225_156_423, -4_373_826_470_845_021_568L,
                -2_103_763_772, 4_663_119_361_160_627_409L, 6_938_794_751_010_724_324L),
        Case(-1L, -1_607_013_479, -1_612_297_016_619_662_647L, 1_848_859_375, -3_234_237_927_366_542_541L,
                299_319_251, -8_487_228_076_173_808_005L, -8_399_308_333_020_698_329L),
        Case(42L, -491_277_234, 2_949_826_092_126_892_291L, -1_540_993_733, -2_430_762_948_046_562_554L,
                1_285_726_101, -7_271_025_491_080_790_604L, -2_196_740_856_189_044_031L),
        Case(long.min, -1_178_737_004, -4_292_029_157_624_213_486L, 1_833_971_519, 5_584_017_301_749_351_935L,
                19_113_245, 2_636_561_876_824_897_058L, 3_031_403_085_690_294_931L),
        Case(long.max, -899_274_055, -1_005_427_240_264_861_369L, 901_851_768,
                2_076_871_689_085_313_299L, -1_890_371_115,
                -5_663_736_429_263_056_058L, -4_238_331_569_760_699_403L),
        Case(0x1234_5678_9abc_def0L, -693_548_133, -5_947_552_309_429_306_528L, -1_710_678_688,
                6_724_426_161_381_059_673L, 220_759_016, -4_264_965_762_478_865_572L, 9_171_596_206_566_329_372L),
    ];

    foreach (c; cases)
    {
        auto r = new SplittableRandom(c.seed);
        assert(r.nextInt() == c.i1);
        assert(r.nextLong() == c.l1);
        auto child = r.split();
        assert(r.nextInt() == c.i2);
        assert(r.nextLong() == c.l2);
        assert(child.nextInt() == c.ci1);
        assert(child.nextLong() == c.cl1);
        auto grand = child.split();
        assert(grand.nextLong() == c.gl1);
    }

    // Seed 11 hits mixGamma's transitions < 24 XOR adjustment on the first split.
    auto lowTrans = new SplittableRandom(11L);
    auto lowChild = lowTrans.split();
    assert(lowChild.nextLong() == 4_571_796_205_088_123_569L);
    assert(lowChild.nextInt() == 253_408_089);
}

@("SplittableRandom.nextBytes emits little-endian 64-bit chunks and skips empty draws")
unittest
{
    static immutable ubyte[17] expected = [
        0xa0, 0x11, 0xd1, 0xa9, 0x58, 0x82, 0x11, 0x22, 0xed, 0xf8, 0x13, 0xf7, 0xe5, 0xdc, 0x6e, 0x34,
        0x1d,
    ];

    auto empty = new SplittableRandom(12_345L);
    empty.nextBytes(cast(byte[]) null);
    byte[0] zero;
    empty.nextBytes(zero[]);
    assert(empty.nextLong() == 2_454_886_589_211_414_944L);

    foreach (len; [1, 3, 4, 7, 8, 9, 15, 16, 17])
    {
        auto r = new SplittableRandom(12_345L);
        auto buf = new byte[len];
        r.nextBytes(buf);
        foreach (i; 0 .. len)
            assert(cast(ubyte) buf[i] == expected[i]);
        const long after = r.nextLong();
        if (len <= 8)
            assert(after == 3_778_200_017_661_327_597L);
        else if (len <= 16)
            assert(after == 2_205_171_434_679_333_405L);
        else
            assert(after == 3_248_800_117_070_709_450L);
    }
}

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

@("SplittableRandom interface defaults and split(source) match Java SE 21")
unittest
{
    struct Case
    {
        long seed;
        bool b1;
        bool b2;
        uint floatBits;
        ulong doubleBits;
        long childLong;
        int childInt;
        long sourceAfter;
        long parentAfter;
    }

    // Verified against OpenJDK 21.0.13.1: two nextBoolean, nextFloat, nextDouble, then
    // split(new SplittableRandom(seed ^ 0x5DEECE66DL)), which draws seed and gamma from the source.
    static immutable Case[] cases = [
        Case(0L, false, false, 0x3f1ab522U, 0x3fef1177150e4990UL, 5_154_934_264_725_718_343L, -1_047_837_613,
                8_308_312_297_490_827_753L, 1_961_750_202_426_094_747L),
        Case(1L, false, true, 0x3e172864U, 0x3fdc7061a43b90b2UL, 5_464_317_558_951_610_270L, 1_174_284_237,
                2_010_107_843_054_164_608L, 8_195_237_237_126_968_761L),
        Case(-1L, true, false, 0x3ddffb00U, 0x3fdb476cdb32ea60UL, -985_859_862_726_190_515L,
                491_074_595, 3_461_050_000_980_081_823L, -5_431_262_886_246_717_010L),
        Case(42L, true, false, 0x3f101a55U, 0x3fd607387fc392b8UL, -1_811_208_052_134_430_950L,
                1_287_304_538, 3_982_747_700_749_827_168L, 701_532_786_141_963_250L),
        Case(long.min, true, true, 0x3ed0dcbaU, 0x3fd64b89a0e0f8d4UL, -3_556_888_039_135_185_266L,
                1_026_689_313, 4_780_342_463_487_050_087L, 903_114_586_442_990_803L),
        Case(long.max, true, false, 0x3e8ff42cU, 0x3fc01018cc4a4cacUL, 3_052_214_053_535_044_713L, -917_927_054,
                -8_367_861_547_587_271_144L, 5_990_184_416_167_851_723L),
        Case(0x1234_5678_9abc_def0L, true, true, 0x3f5623c5U, 0x3fd05f2e6a09b60cUL, 3_005_735_061_745_835_056L,
                1_758_396_878, -8_677_016_550_792_288_882L, -7_372_551_353_265_785_162L),
    ];

    foreach (c; cases)
    {
        auto r = new SplittableRandom(c.seed);
        RandomGenerator.SplittableGenerator g = r;
        assert(!g.isDeprecated());
        assert(g.nextBoolean() == c.b1);
        assert(g.nextBoolean() == c.b2);
        assert(floatBits(g.nextFloat()) == c.floatBits);
        assert(doubleBits(g.nextDouble()) == c.doubleBits);
        auto source = new SplittableRandom(c.seed ^ 0x5DEECE66DL);
        RandomGenerator.SplittableGenerator child = g.split(source);
        assert(child.nextLong() == c.childLong);
        assert(child.nextInt() == c.childInt);
        assert(source.nextLong() == c.sourceAfter);
        assert(r.nextLong() == c.parentAfter);
    }

    // The covariant overloads keep returning the concrete class.
    auto r = new SplittableRandom(7L);
    SplittableRandom a = r.split();
    const SplittableRandom b = r.split(a);
    assert(a !is b);
}
