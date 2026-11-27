/*
 * Copyright (c) 2026 the Flint authors.
 * SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
 */
/// Java SE 21's deterministic seeded splittable pseudorandom generator.
module flint.java.util.splittablerandom;

@safe:

/// Java's SplitMix64-based splittable pseudorandom number generator.
final class SplittableRandom
{
    private enum ulong goldenGamma = 0x9e3779b97f4a7c15UL;

    private ulong seed;
    private immutable ulong gamma;

    private this(ulong seed, ulong gamma) pure nothrow @nogc
    {
        this.seed = seed;
        this.gamma = gamma;
    }

    /// Create a generator with the given initial seed and the golden gamma step.
    this(long seed) pure nothrow @nogc
    {
        this(cast(ulong) seed, goldenGamma);
    }

    /// Split off an independent generator from the current sequence.
    SplittableRandom split() pure nothrow
    {
        return new SplittableRandom(cast(ulong) nextLong(), mixGamma(nextSeed()));
    }

    /// Return the next signed 32-bit pseudorandom value.
    int nextInt() pure nothrow @nogc
    {
        return mix32(nextSeed());
    }

    /// Return the next signed 64-bit pseudorandom value.
    long nextLong() pure nothrow @nogc
    {
        return cast(long) mix64(nextSeed());
    }

    /// Fill the slice using the low bytes of successive nextLong draws (R26).
    void nextBytes(scope byte[] bytes) pure nothrow @nogc
    {
        size_t index;
        while (index < bytes.length)
        {
            ulong word = cast(ulong) nextLong();
            const count = bytes.length - index < 8 ? bytes.length - index : 8;
            foreach (i; 0 .. count)
            {
                bytes[index++] = cast(byte) word;
                word >>= 8;
            }
        }
    }

    private ulong nextSeed() pure nothrow @nogc
    {
        seed += gamma;
        return seed;
    }

    private static ulong mix64(ulong z) pure nothrow @nogc
    {
        z = (z ^ (z >> 30)) * 0xbf58476d1ce4e5b9UL;
        z = (z ^ (z >> 27)) * 0x94d049bb133111ebUL;
        return z ^ (z >> 31);
    }

    private static int mix32(ulong z) pure nothrow @nogc
    {
        z = (z ^ (z >> 33)) * 0x62a9d9ed799705f5UL;
        return cast(int)(((z ^ (z >> 28)) * 0xcb24d0a5c88c35b3UL) >> 32);
    }

    private static ulong mixGamma(ulong z) pure nothrow @nogc
    {
        z = (z ^ (z >> 33)) * 0xff51afd7ed558ccdUL;
        z = (z ^ (z >> 33)) * 0xc4ceb9fe1a85ec53UL;
        z = (z ^ (z >> 33)) | 1UL;
        const uint transitions = popCount64(z ^ (z >> 1));
        return transitions < 24 ? z ^ 0xaaaaaaaaaaaaaaaaUL : z;
    }

    private static uint popCount64(ulong x) pure nothrow @nogc
    {
        x -= (x >> 1) & 0x5555555555555555UL;
        x = (x & 0x3333333333333333UL) + ((x >> 2) & 0x3333333333333333UL);
        x = (x + (x >> 4)) & 0x0f0f0f0f0f0f0f0fUL;
        return cast(uint)((x * 0x0101010101010101UL) >> 56);
    }
}
