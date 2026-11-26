/*
 * Copyright (c) 1995, 2020, Oracle and/or its affiliates. All rights reserved.
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

// Ported from openjdk 21.0.13, src/java.base/share/classes/java/util/BitSet.java
// Modified by the Flint authors.
module flint.java.util.bitset;

import core.bitop : bsf, bsr, popcnt;

@safe:

/// A growable vector of bits indexed by nonnegative Java integers.
class BitSet
{
    private enum wordShift = 6;
    private enum wordBits = 1 << wordShift;
    private enum bitMask = wordBits - 1;

    private ulong[] words;
    private int wordsInUse;

    /// Creates an empty bit set with one word of capacity.
    this() pure nothrow
    {
        words = new ulong[1];
    }

    /// Tests the bit at the given index. Unallocated bits are clear.
    bool get(int bitIndex) const pure
    {
        checkIndex(bitIndex, 0, "bitIndex < 0: ");
        const word = bitIndex >> wordShift;
        return word < wordsInUse && (words[word] & maskAt(bitIndex)) != 0;
    }

    /// Sets one bit, growing the capacity if necessary.
    void set(int bitIndex) pure
    {
        checkIndex(bitIndex, 0, "bitIndex < 0: ");
        const word = bitIndex >> wordShift;
        expandTo(word);
        words[word] |= maskAt(bitIndex);
    }

    /// Sets or clears one bit according to the supplied value.
    void set(int bitIndex, bool value) pure
    {
        if (value)
            set(bitIndex);
        else
            clear(bitIndex);
    }

    /// Clears one bit without changing the capacity.
    void clear(int bitIndex) pure
    {
        checkIndex(bitIndex, 0, "bitIndex < 0: ");
        const word = bitIndex >> wordShift;
        if (word >= wordsInUse)
            return;
        words[word] &= ~maskAt(bitIndex);
        recalculateWordsInUse();
    }

    /// Clears all bits without changing the capacity.
    void clear() pure nothrow @nogc
    {
        words[0 .. wordsInUse] = 0;
        wordsInUse = 0;
    }

    /// Toggles one bit, growing the capacity if necessary.
    void flip(int bitIndex) pure
    {
        checkIndex(bitIndex, 0, "bitIndex < 0: ");
        const word = bitIndex >> wordShift;
        expandTo(word);
        words[word] ^= maskAt(bitIndex);
        recalculateWordsInUse();
    }

    /// Finds the first set bit at or after the index, or returns -1.
    int nextSetBit(int fromIndex) const pure
    {
        checkIndex(fromIndex, 0, "fromIndex < 0: ");
        return nextBit(fromIndex, true);
    }

    /// Finds the first clear bit at or after the index.
    int nextClearBit(int fromIndex) const pure
    {
        checkIndex(fromIndex, 0, "fromIndex < 0: ");
        return nextBit(fromIndex, false);
    }

    /// Finds the last set bit at or before the index, or returns -1.
    int previousSetBit(int fromIndex) const pure
    {
        checkIndex(fromIndex, -1, "fromIndex < -1: ");
        return previousBit(fromIndex, true);
    }

    /// Finds the last clear bit at or before the index, or returns -1.
    int previousClearBit(int fromIndex) const pure
    {
        checkIndex(fromIndex, -1, "fromIndex < -1: ");
        return previousBit(fromIndex, false);
    }

    /// Returns one more than the highest set bit, or zero for an empty set.
    int length() const pure nothrow @nogc
    {
        if (wordsInUse == 0)
            return 0;
        return cast(int)((wordsInUse - 1u) * wordBits + bsr(words[wordsInUse - 1]) + 1u);
    }

    /// Returns the number of addressable bits in the allocated words.
    int size() const pure nothrow @nogc
    {
        return cast(int)(words.length * wordBits);
    }

    /// Tests whether any bit is set.
    bool isEmpty() const pure nothrow @nogc
    {
        return wordsInUse == 0;
    }

    /// Counts the bits that are set.
    int cardinality() const pure nothrow @nogc
    {
        uint count;
        foreach (word; words[0 .. wordsInUse])
            count += popcnt(word);
        return cast(int) count;
    }

    private static ulong maskAt(int index) pure nothrow @nogc
    {
        return 1UL << (index & bitMask);
    }

    private static void checkIndex(int index, int minimum, string label) pure
    {
        if (index < minimum)
        {
            import flint.java.lang : IndexOutOfBoundsException, Integer;

            throw new IndexOutOfBoundsException(label ~ Integer.toString(index));
        }
    }

    private void expandTo(int word) pure nothrow
    {
        const required = cast(size_t) word + 1;
        if (required > words.length)
        {
            const doubled = 2 * words.length;
            words.length = doubled > required ? doubled : required;
        }
        if (word >= wordsInUse)
            wordsInUse = cast(int) required;
    }

    private void recalculateWordsInUse() pure nothrow @nogc
    {
        while (wordsInUse != 0 && words[wordsInUse - 1] == 0)
            --wordsInUse;
    }

    private int nextBit(int fromIndex, bool set) const pure nothrow @nogc
    {
        auto word = fromIndex >> wordShift;
        if (word >= wordsInUse)
            return set ? -1 : fromIndex;

        const invert = set ? 0UL : ulong.max;
        auto matches = (words[word] ^ invert) & (ulong.max << (fromIndex & bitMask));
        while (matches == 0)
        {
            if (++word == wordsInUse)
                return set ? -1 : cast(int)(cast(uint) word * wordBits);
            matches = words[word] ^ invert;
        }
        return word * wordBits + bsf(matches);
    }

    private int previousBit(int fromIndex, bool set) const pure nothrow @nogc
    {
        if (fromIndex == -1)
            return -1;

        auto word = fromIndex >> wordShift;
        const invert = set ? 0UL : ulong.max;
        ulong matches;
        if (word >= wordsInUse)
        {
            if (!set)
                return fromIndex;
            if (wordsInUse == 0)
                return -1;
            word = wordsInUse - 1;
            matches = words[word];
        }
        else
        {
            const mask = ulong.max >> (bitMask - (fromIndex & bitMask));
            matches = (words[word] ^ invert) & mask;
        }
        while (matches == 0)
        {
            if (--word < 0)
                return -1;
            matches = words[word] ^ invert;
        }
        return word * wordBits + bsr(matches);
    }
}
