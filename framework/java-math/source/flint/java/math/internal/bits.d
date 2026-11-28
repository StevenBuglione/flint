/*
 * Copyright (c) 2026 the Flint authors.
 * SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
 */
/// Two's-complement bit queries, single-bit mutations, bitwise operations and shifts for BigInteger.
module flint.java.math.internal.bits;

import core.bitop : bsf;
import flint.java.math.internal.limbs : firstNonzeroLimb;

@safe:

package(flint.java.math):

enum BitwiseOp : ubyte
{
    and,
    or,
    xor,
    andNot,
}

/// Return the index of the lowest set bit in a non-empty normalized magnitude.
pragma(inline, false) int lowestSetBit(scope const(uint)[] words) pure nothrow @nogc
{
    const size_t first = firstNonzeroLimb(words);
    return cast(int)(first * 32 + bsf(words[first]));
}

/// Return the number of bits in two's complement that differ from the sign bit.
pragma(inline, false) int signedBitCount(scope const(uint)[] words, bool negative) pure nothrow @nogc
{
    int count = 0;
    foreach (word; words)
        count += popCount32(word);
    if (negative && words.length)
        count += lowestSetBit(words) - 1;
    return count;
}

/// Return word `index` of the two's-complement representation given `firstNonzeroLimb(words)`.
pragma(inline, false) uint twosComplementWord(scope const(uint)[] words, bool negative, size_t first, size_t index) pure nothrow @nogc
{
    if (!words.length)
        return 0;
    if (!negative)
        return index < words.length ? words[index] : 0;
    if (index >= words.length)
        return uint.max;
    if (index < first)
        return 0;
    const uint word = words[index];
    return index == first ? 0U - word : ~word;
}

/// Return bit `n` of the two's-complement representation.
pragma(inline, false) bool testTwosComplementBit(scope const(uint)[] words, bool negative, size_t n) pure nothrow @nogc
{
    const size_t first = negative ? firstNonzeroLimb(words) : 0;
    return ((twosComplementWord(words, negative, first, n / 32) >> (n & 31)) & 1U) != 0;
}

/// Flip bit `n` in the two's-complement representation and write the resulting magnitude into `dest`.
/// `dest` must have length `count + (negative ? 1 : 0)` where `count = max(words.length, n / 32 + 1)`.
pragma(inline, false) void toggleBitLimbs(scope uint[] dest, scope const(uint)[] words, bool negative, size_t n) pure nothrow @nogc
{
    const size_t targetWord = n / 32;
    const size_t count = words.length > targetWord + 1 ? words.length : targetWord + 1;
    const size_t first = negative ? firstNonzeroLimb(words) : 0;
    foreach (i; 0 .. count)
        dest[i] = twosComplementWord(words, negative, first, i);
    dest[targetWord] ^= 1U << (n & 31);
    if (negative)
        negateTwosComplement(dest, count);
}

/// Apply a two's-complement bitwise operation and write the resulting magnitude into `dest`.
/// `dest` must have length `max(left.length, right.length) + (resultNeg ? 1 : 0)`.
pragma(inline, false) void bitwiseLimbs(scope uint[] dest, scope const(uint)[] left, bool leftNeg,
    scope const(uint)[] right, bool rightNeg, BitwiseOp op, bool resultNeg) pure nothrow @nogc
{
    const size_t count = left.length > right.length ? left.length : right.length;
    const size_t leftFirst = leftNeg ? firstNonzeroLimb(left) : 0;
    const size_t rightFirst = rightNeg ? firstNonzeroLimb(right) : 0;
    foreach (i; 0 .. count)
    {
        const uint aw = twosComplementWord(left, leftNeg, leftFirst, i);
        const uint bw = twosComplementWord(right, rightNeg, rightFirst, i);
        dest[i] = combineBitwise(aw, bw, op);
    }
    if (resultNeg)
        negateTwosComplement(dest, count);
}

/// Shift a normalized magnitude left by `distance` bits into `dest` (zero-initialized).
pragma(inline, false) void shiftLeftLimbs(scope uint[] dest, scope const(uint)[] words, size_t distance) pure nothrow @nogc
{
    const size_t wordShift = distance / 32;
    const uint bitShift = cast(uint)(distance & 31);
    if (bitShift == 0)
    {
        foreach (i, word; words)
            dest[wordShift + i] = word;
        return;
    }
    const uint complement = 32 - bitShift;
    uint carry = 0;
    foreach (i, word; words)
    {
        dest[wordShift + i] = (word << bitShift) | carry;
        carry = word >> complement;
    }
    if (carry)
        dest[wordShift + words.length] = carry;
}

/// Shift a normalized magnitude right by `distance` bits (< magnitudeBitLength) into `dest`.
/// When `negative` is true and any shifted-out bit is nonzero, adds 1 to round toward -infinity.
pragma(inline, false) void shiftRightLimbs(scope uint[] dest, scope const(uint)[] words, size_t distance, bool negative) pure nothrow @nogc
{
    const size_t wordShift = distance / 32;
    const uint bitShift = cast(uint)(distance & 31);
    const size_t outLen = words.length - wordShift;
    bool lostBits = false;
    if (negative)
    {
        foreach (word; words[0 .. wordShift])
            if (word)
                lostBits = true;
        if (bitShift != 0 && (words[wordShift] << (32 - bitShift)) != 0)
            lostBits = true;
    }

    const uint complement = 32 - bitShift;
    foreach (i; 0 .. outLen)
    {
        uint word = words[wordShift + i] >> bitShift;
        if (bitShift != 0 && wordShift + i + 1 < words.length)
            word |= words[wordShift + i + 1] << complement;
        dest[i] = word;
    }

    if (lostBits)
    {
        ulong carry = 1;
        foreach (i; 0 .. outLen)
        {
            const ulong sum = cast(ulong) dest[i] + carry;
            dest[i] = cast(uint) sum;
            carry = sum >> 32;
        }
        if (carry)
            dest[outLen] = cast(uint) carry;
    }
}

pragma(inline, false) private void negateTwosComplement(scope uint[] dest, size_t count) pure nothrow @nogc
{
    ulong carry = 1;
    foreach (i; 0 .. count)
    {
        const ulong sum = cast(ulong)(~dest[i]) + carry;
        dest[i] = cast(uint) sum;
        carry = sum >> 32;
    }
    dest[count] = cast(uint) carry;
}

pragma(inline, false) private uint combineBitwise(uint a, uint b, BitwiseOp op) pure nothrow @nogc
{
    final switch (op)
    {
    case BitwiseOp.and:
        return a & b;
    case BitwiseOp.or:
        return a | b;
    case BitwiseOp.xor:
        return a ^ b;
    case BitwiseOp.andNot:
        return a & ~b;
    }
}

pragma(inline, false) private int popCount32(uint x) pure nothrow @nogc
{
    x -= (x >> 1) & 0x5555_5555U;
    x = (x & 0x3333_3333U) + ((x >> 2) & 0x3333_3333U);
    x = (x + (x >> 4)) & 0x0f0f_0f0fU;
    return cast(int)((x * 0x0101_0101U) >> 24);
}
