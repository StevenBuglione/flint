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
pragma(inline, false) int lowestSetBit(scope const(uint)[] w) pure nothrow @nogc
{
    const size_t first = firstNonzeroLimb(w);
    return cast(int)(first * 32 + bsf(w[first]));
}

/// Return the number of bits in two's complement that differ from the sign bit.
pragma(inline, false) int signedBitCount(scope const(uint)[] w, bool neg) pure nothrow @nogc
{
    int count = 0;
    foreach (word; w)
        count += popCount32(word);
    if (neg && w.length)
        count += lowestSetBit(w) - 1;
    return count;
}

/// Return word `i` of the two's-complement representation given `firstNonzeroLimb(w)`.
pragma(inline, false) uint tcWord(scope const(uint)[] w, bool neg, size_t first, size_t i) pure nothrow @nogc
{
    if (!w.length)
        return 0;
    if (!neg)
        return i < w.length ? w[i] : 0;
    if (i >= w.length)
        return uint.max;
    if (i < first)
        return 0;
    const uint word = w[i];
    return i == first ? 0U - word : ~word;
}

/// Return bit `n` of the two's-complement representation.
pragma(inline, false) bool testTwosComplementBit(scope const(uint)[] w, bool neg, size_t n) pure nothrow @nogc
{
    const size_t first = neg ? firstNonzeroLimb(w) : 0;
    return ((tcWord(w, neg, first, n / 32) >> (n & 31)) & 1U) != 0;
}

/// Flip bit `n` in the two's-complement representation and write the resulting magnitude into `dst`.
/// `dst` must have length `count + (neg ? 1 : 0)` where `count = max(w.length, n / 32 + 1)`.
pragma(inline, false) void flipLimbs(scope uint[] dst, scope const(uint)[] w, bool neg, size_t n) pure nothrow @nogc
{
    const size_t target = n / 32;
    const size_t count = w.length > target + 1 ? w.length : target + 1;
    const size_t first = neg ? firstNonzeroLimb(w) : 0;
    foreach (i; 0 .. count)
        dst[i] = tcWord(w, neg, first, i);
    dst[target] ^= 1U << (n & 31);
    if (neg)
        negateTwosComplement(dst, count);
}

/// Apply a two's-complement bitwise operation and write the resulting magnitude into `dst`.
/// `dst` must have length `max(left.length, right.length) + (resultNeg ? 1 : 0)`.
pragma(inline, false) void bitwiseLimbs(scope uint[] dst, scope const(uint)[] left, bool leftNeg,
        scope const(uint)[] right, bool rightNeg, BitwiseOp op, bool resultNeg) pure nothrow @nogc
{
    const size_t count = left.length > right.length ? left.length : right.length;
    const size_t leftFirst = leftNeg ? firstNonzeroLimb(left) : 0;
    const size_t rightFirst = rightNeg ? firstNonzeroLimb(right) : 0;
    foreach (i; 0 .. count)
    {
        const uint aw = tcWord(left, leftNeg, leftFirst, i);
        const uint bw = tcWord(right, rightNeg, rightFirst, i);
        dst[i] = combineBitwise(aw, bw, op);
    }
    if (resultNeg)
        negateTwosComplement(dst, count);
}

/// Shift a normalized magnitude left by `distance` bits into `dst` (zero-initialized).
pragma(inline, false) void shlLimbs(scope uint[] dst, scope const(uint)[] w, size_t distance) pure nothrow @nogc
{
    const size_t wordShift = distance / 32;
    const uint bitShift = cast(uint)(distance & 31);
    if (bitShift == 0)
    {
        foreach (i, word; w)
            dst[wordShift + i] = word;
        return;
    }
    const uint complement = 32 - bitShift;
    uint carry = 0;
    foreach (i, word; w)
    {
        dst[wordShift + i] = (word << bitShift) | carry;
        carry = word >> complement;
    }
    if (carry)
        dst[wordShift + w.length] = carry;
}

/// Shift a normalized magnitude right by `dist` bits (< magnitudeBitLength) into `dst`.
/// When `neg` is true and any shifted-out bit is nonzero, adds 1 to round toward -infinity.
pragma(inline, false) void shrLimbs(scope uint[] dst, scope const(uint)[] w, size_t dist, bool neg) pure nothrow @nogc
{
    const size_t wordShift = dist / 32;
    const uint bitShift = cast(uint)(dist & 31);
    const size_t outLen = w.length - wordShift;
    bool lostBits = false;
    if (neg)
    {
        foreach (word; w[0 .. wordShift])
            if (word)
                lostBits = true;
        if (bitShift != 0 && (w[wordShift] << (32 - bitShift)) != 0)
            lostBits = true;
    }

    const uint complement = 32 - bitShift;
    foreach (i; 0 .. outLen)
    {
        uint word = w[wordShift + i] >> bitShift;
        if (bitShift != 0 && wordShift + i + 1 < w.length)
            word |= w[wordShift + i + 1] << complement;
        dst[i] = word;
    }

    if (lostBits)
    {
        ulong carry = 1;
        foreach (i; 0 .. outLen)
        {
            const ulong sum = cast(ulong) dst[i] + carry;
            dst[i] = cast(uint) sum;
            carry = sum >> 32;
        }
        if (carry)
            dst[outLen] = cast(uint) carry;
    }
}

pragma(inline, false) private void negateTwosComplement(scope uint[] dst, size_t count) pure nothrow @nogc
{
    ulong carry = 1;
    foreach (i; 0 .. count)
    {
        const ulong sum = cast(ulong)(~dst[i]) + carry;
        dst[i] = cast(uint) sum;
        carry = sum >> 32;
    }
    dst[count] = cast(uint) carry;
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
