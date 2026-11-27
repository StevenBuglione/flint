/*
 * Copyright (c) 2026 the Flint authors.
 * SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
 */
/// Java SE 21 pseudorandom generator interface hierarchy (`java.util.random.RandomGenerator`).
module flint.java.util.random.randomgenerator;

@safe:

/// Uniform interface for pseudorandom number generators.
interface RandomGenerator
{
    /// Return a pseudorandomly chosen 64-bit signed integer.
    long nextLong();

    /// Report whether this generator implementation is deprecated.
    bool isDeprecated();

    /// Return a pseudorandomly chosen boolean derived from the sign bit of `nextInt()`.
    bool nextBoolean();

    /// Fill `bytes` with pseudorandom bytes, 8 low-order bytes per `nextLong()` call (R26).
    void nextBytes(scope byte[] bytes);

    /// Return a pseudorandomly chosen 32-bit signed integer from the high 32 bits of `nextLong()`.
    int nextInt();

    /// Return a pseudorandomly chosen float in `[0.0f, 1.0f)` from the high 24 bits of `nextInt()`.
    float nextFloat();

    /// Return a pseudorandomly chosen double in `[0.0, 1.0)` from the high 53 bits of `nextLong()`.
    double nextDouble();

    /// Java's default method implementations for `RandomGenerator` (R3).
    ///
    /// A class that implements any of these members itself with stricter attributes (for example
    /// `pure nothrow @nogc`) must not mix this in: the compiler then binds the interface slot to the
    /// mixin's member, not the class's. Spell the remaining defaults out instead, as
    /// `SplittableRandom` does.
    mixin template Defaults()
    {
        bool isDeprecated()
        {
            return false;
        }

        bool nextBoolean()
        {
            return this.nextInt() < 0;
        }

        void nextBytes(scope byte[] bytes)
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

        int nextInt()
        {
            return cast(int)(cast(ulong) nextLong() >>> 32);
        }

        float nextFloat()
        {
            return cast(float)(cast(uint) this.nextInt() >>> 8) * 0x1.0p-24f;
        }

        double nextDouble()
        {
            return cast(double)(cast(ulong) nextLong() >>> 11) * 0x1.0p-53;
        }
    }

    /// Marker subinterface for generators that can produce streams of new generators.
    interface StreamableGenerator : RandomGenerator
    {
    }

    /// Subinterface for generators that can split off independent generators.
    interface SplittableGenerator : StreamableGenerator
    {
        /// Return a new generator split off from this generator.
        SplittableGenerator split();

        /// Return a new generator split off from this generator using `source` for initial state.
        SplittableGenerator split(SplittableGenerator source);
    }

    /// Subinterface for generators that can jump forward by a moderate fixed distance.
    interface JumpableGenerator : StreamableGenerator
    {
        /// Return a new generator with the same internal state as this generator.
        JumpableGenerator copy();

        /// Advance this generator's state by `jumpDistance()`.
        void jump();

        /// Return the number of steps advanced by `jump()`.
        double jumpDistance();

        /// Copy this generator, advance this generator by `jump()`, and return the copy.
        RandomGenerator copyAndJump();

        /// Java's default method implementations for `JumpableGenerator` (R3).
        mixin template Defaults()
        {
            RandomGenerator copyAndJump()
            {
                RandomGenerator.JumpableGenerator self = this;
                auto copy = self.copy();
                self.jump();
                return copy;
            }
        }
    }

    /// Subinterface for generators that can also leap forward by a larger fixed distance.
    interface LeapableGenerator : JumpableGenerator
    {
        /// Return a new generator with the same internal state as this generator.
        LeapableGenerator copy();

        /// Advance this generator's state by `leapDistance()`.
        void leap();

        /// Return the number of steps advanced by `leap()`.
        double leapDistance();

        /// Copy this generator, advance this generator by `leap()`, and return the copy.
        JumpableGenerator copyAndLeap();

        /// Java's default method implementations for `LeapableGenerator` (R3).
        mixin template Defaults()
        {
            RandomGenerator.JumpableGenerator copyAndLeap()
            {
                RandomGenerator.LeapableGenerator self = this;
                auto copy = self.copy();
                self.leap();
                return copy;
            }
        }
    }

    /// Subinterface for generators that can jump forward by an arbitrary distance.
    interface ArbitrarilyJumpableGenerator : LeapableGenerator
    {
        /// Return a new generator with the same internal state as this generator.
        ArbitrarilyJumpableGenerator copy();

        /// Advance this generator's state by `2^^logDistance` steps.
        void jumpPowerOfTwo(int logDistance);

        /// Advance this generator's state by `distance` steps.
        void jump(double distance);

        /// Advance this generator's state by `jumpDistance()`.
        void jump();

        /// Advance this generator's state by `leapDistance()`.
        void leap();

        /// Copy this generator, advance this generator by `distance`, and return the copy.
        ArbitrarilyJumpableGenerator copyAndJump(double distance);

        /// Java's default method implementations for `ArbitrarilyJumpableGenerator` (R3).
        mixin template Defaults()
        {
            void jump()
            {
                RandomGenerator.ArbitrarilyJumpableGenerator self = this;
                self.jump(self.jumpDistance());
            }

            void leap()
            {
                RandomGenerator.ArbitrarilyJumpableGenerator self = this;
                self.jump(self.leapDistance());
            }

            RandomGenerator.ArbitrarilyJumpableGenerator copyAndJump(double distance)
            {
                RandomGenerator.ArbitrarilyJumpableGenerator self = this;
                auto copy = self.copy();
                self.jump(distance);
                return copy;
            }
        }
    }
}
