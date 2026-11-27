module flint.java.random_seed_test;

import flint.java.util.random.random : Random;

@safe:

private final class SeedWitness : Random
{
    int calls;
    long receivedSeed;
    bool initialized;
    bool dispatchedDuringConstruction;

    this(long seed)
    {
        super(seed);
        initialized = true;
    }

    override void setSeed(long seed)
    {
        ++calls;
        receivedSeed = seed;
        dispatchedDuringConstruction = !initialized;
        super.setSeed(seed);
    }

    override int nextInt()
    {
        return 0x4030_2010;
    }
}

@("Random dispatches seed setup during construction and uses virtual nextInt for bytes")
unittest
{
    auto random = new SeedWitness(-7);
    assert(random.calls == 1 && random.receivedSeed == -7 && random.dispatchedDuringConstruction);
    byte[6] bytes;
    random.nextBytes(bytes[]);
    assert(bytes[] == [0x10, 0x20, 0x30, 0x40, 0x10, 0x20]);
    random.setSeed(11);
    assert(random.calls == 2 && random.receivedSeed == 11 && !random.dispatchedDuringConstruction);
}

@("Random seeded ints restart and an empty byte request consumes no value")
unittest
{
    auto random = new Random(0);
    assert(random.nextInt() == -1_155_484_576);
    assert(random.nextInt() == -723_955_400);
    random.setSeed(0);
    random.nextBytes(cast(byte[]) null);
    assert(random.nextInt() == -1_155_484_576);
}

private uint floatRawBits(float value) pure nothrow @nogc
{
    union Bits
    {
        float f;
        uint u;
    }

    Bits bits = Bits(value);
    return bits.u;
}

private ulong doubleRawBits(double value) pure nothrow @nogc
{
    union Bits
    {
        double d;
        ulong u;
    }

    Bits bits = Bits(value);
    return bits.u;
}

private final class NextBitsWitness : Random
{
    private const(int)[] widths;
    private int[] requested;
    private size_t cursor;

    this(const(int)[] outputs)
    {
        super(0);
        widths = outputs;
    }

    override protected int next(int bits)
    {
        requested ~= bits;
        return widths[cursor++];
    }
}

@("Random nextLong, nextBoolean, nextFloat, and nextDouble match Java SE 21 bit-for-bit")
unittest
{
    struct Vector
    {
        long seed;
        long l1;
        bool b1;
        bool b2;
        uint f1Bits;
        ulong d1Bits;
        long l2;
    }

    // Verified against OpenJDK 21.0.13.1 java.util.Random.
    static immutable Vector[] vectors = [
        Vector(0L, -4_962_768_465_676_381_896L, false, true, 0x3f232dc9U, 0x3fd3c77c08ce970aUL,
                2_158_390_814_503_909_950L),
        Vector(1L, -4_964_420_948_893_066_024L, false, false, 0x3e54b330U, 0x3fa28d71aa9678f0UL,
                -6_292_788_870_224_356_907L),
        Vector(-1L, 4_961_115_982_468_162_243L, false, true, 0x3f297e5eU, 0x3fe339b76b54dd9cUL,
                7_365_572_370_171_403_210L),
        Vector(42L, -5_025_562_857_975_149_833L, true, false, 0x3e9e1078U, 0x3fee25776a3774ecUL,
                -5_391_787_952_107_853_122L),
        Vector(0x123456789abcdef0L, 347_762_063_794_264_619L, true, false, 0x3f4c2da0U, 0x3fe055c303d64ad7UL,
                -3_443_116_489_353_774_630L),
        Vector(long.min, -4_962_768_465_676_381_896L, false, true, 0x3f232dc9U, 0x3fd3c77c08ce970aUL,
                2_158_390_814_503_909_950L),
        Vector(long.max, 4_961_115_982_468_162_243L, false, true, 0x3f297e5eU,
                0x3fe339b76b54dd9cUL, 7_365_572_370_171_403_210L),
    ];

    foreach (v; vectors)
    {
        auto r = new Random(v.seed);
        assert(r.nextLong() == v.l1);
        assert(r.nextBoolean() == v.b1);
        assert(r.nextBoolean() == v.b2);
        assert(floatRawBits(r.nextFloat()) == v.f1Bits);
        assert(doubleRawBits(r.nextDouble()) == v.d1Bits);
        assert(r.nextLong() == v.l2);
    }

    // Verify virtual next(int) bit widths and signed addition in nextLong().
    auto witness = new NextBitsWitness([1, -1, 1, 0, 1 << 23, 1 << 25, 0]);
    assert(witness.nextLong() == (1L << 32) - 1);
    assert(witness.nextBoolean());
    assert(!witness.nextBoolean());
    assert(witness.nextFloat() == 0.5f);
    assert(witness.nextDouble() == 0.5);
    assert(witness.requested == [32, 32, 1, 1, 24, 26, 27]);
}
