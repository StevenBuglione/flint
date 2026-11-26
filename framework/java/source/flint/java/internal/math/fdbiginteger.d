/*
 * Copyright (c) 2013, 2020, Oracle and/or its affiliates. All rights reserved.
 * DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS FILE HEADER.
 *
 * This code is free software; you can redistribute it and/or modify it
 * under the terms of the GNU General Public License version 2 only, as
 * published by the Free Software Foundation.  Oracle designates this
 * particular file as subject to the "Classpath" exception as provided
 * by Oracle in the LICENSE file that accompanied this code.
 *
 * This code is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
 * FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
 * version 2 for more details (a copy is included in the LICENSE file that
 * accompanied this code).
 *
 * You should have received a copy of the GNU General Public License version
 * 2 along with this work; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin St, Fifth Floor, Boston, MA 02110-1301 USA.
 *
 * Please contact Oracle, 500 Oracle Parkway, Redwood Shores, CA 94065 USA
 * or visit www.oracle.com if you need additional information or have any
 * questions.
 */
// Ported from openjdk 21.0.13: src/java.base/share/classes/jdk/internal/math/FDBigInteger.java
// Modified by the Flint authors.
module flint.java.internal.math.fdbiginteger;

@safe:

/// Bounded unsigned arithmetic for the binary64 decimal conversion.
package(flint.java) struct FDBigInteger
{
    // The binary64 range needs fewer than 1,280 bits, including the decimal scaling margin.
    private enum wordCapacity = 40;
    private uint[wordCapacity] words;
    private size_t length;

    /// Forms `value * 5^^fives * 2^^twos`. Leaves `result` unchanged on overflow.
    static bool tryScale(ulong value, uint fives, uint twos, ref FDBigInteger result) pure nothrow @nogc
    {
        FDBigInteger scaled;
        if (value)
        {
            if (fives >= wordCapacity * 32 || twos >= wordCapacity * 32)
                return false;
            scaled.words[0] = cast(uint) value;
            scaled.words[1] = cast(uint)(value >> 32);
            scaled.length = scaled.words[1] ? 2 : 1;

            while (fives >= 13)
            {
                if (!scaled.multiplyWord(1_220_703_125))
                    return false;
                fives -= 13;
            }
            if (!scaled.multiplyWord(smallFivePowers[fives]) || !scaled.tryLeftShift(twos))
                return false;
        }
        result = scaled;
        return true;
    }

    /// Shifts left if the result fits. Overflow leaves the operand unchanged.
    bool tryLeftShift(uint bits) pure nothrow @nogc
    {
        if (length == 0 || bits == 0)
            return true;

        const offset = bits / 32;
        const shift = bits % 32;
        const high = shift == 0 ? 0 : words[length - 1] >> (32 - shift);
        if (length + offset + (high != 0) > wordCapacity)
            return false;

        if (high)
            words[length + offset] = high;
        foreach_reverse (i; 0 .. length)
        {
            uint word = words[i] << shift;
            if (shift && i)
                word |= words[i - 1] >> (32 - shift);
            words[i + offset] = word;
        }
        words[0 .. offset] = 0;
        length += offset + (high != 0);
        return true;
    }

    /// Multiplies by ten, leaving the operand unchanged on overflow.
    bool tryMultiplyBy10() pure nothrow @nogc
    {
        if (length < wordCapacity)
            return multiplyWord(10);
        auto scaled = this;
        if (!scaled.multiplyWord(10))
            return false;
        this = scaled;
        return true;
    }

    /// Compares the significant limbs from the most significant end.
    int cmp(ref scope const FDBigInteger other) const pure nothrow @nogc
    {
        if (length != other.length)
            return length < other.length ? -1 : 1;
        foreach_reverse (i; 0 .. length)
            if (words[i] != other.words[i])
                return words[i] < other.words[i] ? -1 : 1;
        return 0;
    }

    /// Compares this value with the sum of two operands without allocating a sum buffer.
    int addAndCmp(ref scope const FDBigInteger left, ref scope const FDBigInteger right) const pure nothrow @nogc
    {
        const sumLength = left.length > right.length ? left.length : right.length;
        const width = length > sumLength ? length : sumLength;
        ulong carry;
        int comparison;
        foreach (i; 0 .. width)
        {
            const sum = carry + left.wordAt(i) + right.wordAt(i);
            carry = sum >> 32;
            const low = cast(uint) sum;
            const word = wordAt(i);
            if (word != low)
                comparison = word < low ? -1 : 1;
        }
        return carry ? -1 : comparison;
    }

    /// Emits one quotient digit and replaces this value with ten times the remainder.
    /// Zero divisors, multi-digit quotients and overflow leave this value unchanged.
    bool tryQuoRemIteration(ref scope const FDBigInteger divisor, out uint digit) pure nothrow @nogc
    {
        if (divisor.length == 0)
            return false;
        auto remainder = this;
        uint quotient;
        while (remainder.cmp(divisor) >= 0)
        {
            if (++quotient == 10)
                return false;
            remainder.subtract(divisor);
        }
        if (!remainder.multiplyWord(10))
            return false;
        this = remainder;
        digit = quotient;
        return true;
    }

    private uint wordAt(size_t index) const pure nothrow @nogc
    {
        return index < length ? words[index] : 0;
    }

    // On overflow this scratch value is discarded by the caller.
    private bool multiplyWord(uint factor) pure nothrow @nogc
    {
        ulong carry;
        foreach (i; 0 .. length)
        {
            const product = cast(ulong) words[i] * factor + carry;
            words[i] = cast(uint) product;
            carry = product >> 32;
        }
        if (carry)
        {
            if (length == wordCapacity)
                return false;
            words[length++] = cast(uint) carry;
        }
        return true;
    }

    private void subtract(ref scope const FDBigInteger other) pure nothrow @nogc
    {
        ulong borrow;
        foreach (i; 0 .. length)
        {
            const subtrahend = borrow + other.wordAt(i);
            const minuend = words[i];
            words[i] = cast(uint)(minuend - subtrahend);
            borrow = minuend < subtrahend;
        }
        while (length && words[length - 1] == 0)
            --length;
    }

    private static immutable uint[13] smallFivePowers = [
        1, 5, 25, 125, 625, 3_125, 15_625, 78_125, 390_625, 1_953_125, 9_765_625, 48_828_125,
        244_140_625,
    ];
}
