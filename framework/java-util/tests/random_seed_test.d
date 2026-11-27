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
