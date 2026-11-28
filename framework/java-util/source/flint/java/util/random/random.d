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

    /// Return the next value in `[0, bound)` following Java's rejection algorithm.
    int nextInt(int bound)
    {
        import flint.java.lang.runtimeexception : IllegalArgumentException;

        if (bound <= 0)
            throw new IllegalArgumentException("bound must be positive");
        int r = next(31);
        const int m = bound - 1;
        if ((bound & m) == 0)
        {
            r = cast(int)((cast(long) bound * r) >> 31);
        }
        else
        {
            for (int u = r; u - (r = u % bound) + m < 0; u = next(31))
            {
            }
        }
        return r;
    }

    /// Return the next value in `[origin, bound)` using one `nextInt` draw per attempt.
    int nextInt(int origin, int bound)
    {
        import flint.java.lang.runtimeexception : IllegalArgumentException;

        if (origin >= bound)
            throw new IllegalArgumentException("bound must be greater than origin");
        int r = nextInt();
        const int n = bound - origin;
        const int m = n - 1;
        if ((n & m) == 0)
        {
            r = (r & m) + origin;
        }
        else if (n > 0)
        {
            for (int u = logicalShiftRight(r); u + m - (r = u % n) < 0; u = logicalShiftRight(nextInt()))
            {
            }
            r += origin;
        }
        else
        {
            while (r < origin || r >= bound)
                r = nextInt();
        }
        return r;
    }

    /// Return the next signed 64-bit value built from two virtual `next(32)` draws.
    long nextLong()
    {
        return (cast(long) next(32) << 32) + next(32);
    }

    /// Return the next value in `[0, bound)` from full-width draws.
    long nextLong(long bound)
    {
        import flint.java.lang.runtimeexception : IllegalArgumentException;

        if (bound <= 0)
            throw new IllegalArgumentException("bound must be positive");
        const long m = bound - 1;
        long r = nextLong();
        if ((bound & m) == 0L)
        {
            r &= m;
        }
        else
        {
            for (long u = logicalShiftRight(r); u + m - (r = u % bound) < 0L; u = logicalShiftRight(nextLong()))
            {
            }
        }
        return r;
    }

    /// Return the next value in `[origin, bound)` from full-width draws.
    long nextLong(long origin, long bound)
    {
        import flint.java.lang.runtimeexception : IllegalArgumentException;

        if (origin >= bound)
            throw new IllegalArgumentException("bound must be greater than origin");
        long r = nextLong();
        const long n = bound - origin;
        const long m = n - 1;
        if ((n & m) == 0L)
        {
            r = (r & m) + origin;
        }
        else if (n > 0L)
        {
            for (long u = logicalShiftRight(r); u + m - (r = u % n) < 0L; u = logicalShiftRight(nextLong()))
            {
            }
            r += origin;
        }
        else
        {
            while (r < origin || r >= bound)
                r = nextLong();
        }
        return r;
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

    /// Return the next double in `[0.0, bound)`.
    double nextDouble(double bound)
    {
        import flint.java.lang.runtimeexception : IllegalArgumentException;

        if (!(0.0 < bound && bound < double.infinity))
            throw new IllegalArgumentException("bound must be positive and finite");
        double r = nextDouble() * bound;
        if (r >= bound)
            r = nextDown(bound);
        return r;
    }

    /// Return the next double in `[origin, bound)`.
    double nextDouble(double origin, double bound)
    {
        import flint.java.lang.runtimeexception : IllegalArgumentException;

        if (!(-double.infinity < origin && origin < bound && bound < double.infinity))
            throw new IllegalArgumentException("bound must be greater than origin");
        double r = nextDouble();
        if (bound - origin < double.infinity)
        {
            r = r * (bound - origin) + origin;
        }
        else
        {
            const double halfOrigin = 0.5 * origin;
            r = (r * (0.5 * bound - halfOrigin) + halfOrigin) * 2.0;
        }
        if (r >= bound)
            r = nextDown(bound);
        return r;
    }

    /// Java's unsigned right shift for a signed 32-bit value.
    private static int logicalShiftRight(int value) pure nothrow @nogc
    {
        return cast(int)(cast(uint) value >> 1);
    }

    /// Java's unsigned right shift for a signed 64-bit value.
    private static long logicalShiftRight(long value) pure nothrow @nogc
    {
        return cast(long)(cast(ulong) value >> 1);
    }

    /// Java's `Math.nextDown` for a finite upper bound.
    private static double nextDown(double value) pure nothrow @nogc
    {
        import std.math : nextDown;

        return nextDown(value);
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
