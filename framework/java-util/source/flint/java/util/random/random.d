/*
 * Copyright (c) 2026 the Flint authors.
 * SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
 */
/// Java SE 21's deterministic seeded random generator.
module flint.java.util.random.random;

import core.atomic : atomicLoad, atomicStore, cas;

@safe:

/// The Java 48-bit generator and its subclass hooks.
class Random
{
    private enum ulong multiplier = 0x5DEECE66DUL;
    private enum ulong increment = 0xB;
    private enum int seedBits = 48;
    private enum ulong seedMask = (1UL << seedBits) - 1;

    private shared ulong state;

    /// Initialize the generator through the receiver's seed method.
    this(long seed)
    {
        setSeed(seed);
    }

    /// Restart the generator with the given Java seed.
    void setSeed(long seed)
    {
        atomicStore(state, (cast(ulong) seed ^ multiplier) & seedMask);
    }

    /// Advance the state and return the requested high bits.
    protected int next(int bits)
    {
        ulong previous;
        ulong updated;
        do
        {
            previous = atomicLoad(state);
            updated = (previous * multiplier + increment) & seedMask;
        }
        while (!cas(&state, previous, updated));
        return cast(int)(updated >> (seedBits - bits));
    }

    /// Return the next signed 32-bit value.
    int nextInt()
    {
        return next(32);
    }

    /// Return the next signed 64-bit value built from two virtual `next(32)` draws.
    long nextLong()
    {
        return (cast(long) next(32) << 32) + next(32);
    }

    /// Return the next boolean from one virtual `next(1)` bit.
    bool nextBoolean()
    {
        return next(1) != 0;
    }

    /// Return the next float in `[0.0f, 1.0f)` from `next(24)`.
    float nextFloat()
    {
        return cast(float) next(24) * 0x1.0p-24f;
    }

    /// Return the next double in `[0.0, 1.0)` from `next(26)` and `next(27)`.
    double nextDouble()
    {
        return cast(double)((cast(long) next(26) << 27) + next(27)) * 0x1.0p-53;
    }

    /// Fill the slice using the low bytes of successive virtual nextInt calls.
    void nextBytes(scope byte[] bytes)
    {
        size_t index;
        while (index < bytes.length)
        {
            uint word = cast(uint) nextInt();
            const count = bytes.length - index < 4 ? bytes.length - index : 4;
            foreach (i; 0 .. count)
            {
                bytes[index++] = cast(byte) word;
                word >>= 8;
            }
        }
    }
}
