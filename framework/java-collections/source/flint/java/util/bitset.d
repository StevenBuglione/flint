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
    private enum RangeChange : ubyte
    {
        set,
        clear,
        flip
    }

    private ulong[] words;
    private int wordsInUse;

    /// Creates an empty bit set with one word of capacity.
    this() pure nothrow
    {
        words = new ulong[1];
    }

    private this(ulong[] ownedWords) pure nothrow
    {
        words = ownedWords;
        wordsInUse = cast(int) ownedWords.length;
    }

    /// Copies the signed words, lowest bit indices first, and drops unused capacity.
    static BitSet valueOf(scope const(long)[] values) pure nothrow
    {
        auto count = values.length;
        while (count != 0 && values[count - 1] == 0)
            --count;
        return new BitSet(copyWords(cast(const(ulong)[]) values[0 .. count]));
    }

    /// Tests the bit at the given index. Unallocated bits are clear.
    bool get(int bitIndex) const pure
    {
        checkIndex(bitIndex, 0, "bitIndex < 0: ");
        const word = cast(uint) bitIndex >> wordShift;
        // Unused capacity holds zero words, so the capacity check also guards the load.
        return word < words.length && (words[word] & maskAt(bitIndex)) != 0;
    }

    /// Sets one bit, growing the capacity if necessary.
    void set(int bitIndex) pure
    {
        changeBit(bitIndex, RangeChange.set);
    }

    /// Sets or clears one bit according to the supplied value.
    void set(int bitIndex, bool value) pure
    {
        if (value)
            set(bitIndex);
        else
            clear(bitIndex);
    }

    /// Sets the bits in the half-open range [fromIndex, toIndex).
    void set(int fromIndex, int toIndex) pure
    {
        changeRange(fromIndex, toIndex, RangeChange.set);
    }

    /// Sets or clears the bits in the half-open range [fromIndex, toIndex).
    void set(int fromIndex, int toIndex, bool value) pure
    {
        if (value)
            set(fromIndex, toIndex);
        else
            clear(fromIndex, toIndex);
    }

    /// Clears one bit without changing the capacity.
    void clear(int bitIndex) pure
    {
        changeBit(bitIndex, RangeChange.clear);
    }

    /// Clears the half-open range [fromIndex, toIndex) without growing the capacity.
    void clear(int fromIndex, int toIndex) pure
    {
        changeRange(fromIndex, toIndex, RangeChange.clear);
    }

    /// Clears all bits without changing the capacity.
    void clear() pure nothrow @nogc
    {
        clearTail(0);
    }

    /// Toggles one bit, growing the capacity if necessary.
    void flip(int bitIndex) pure
    {
        changeBit(bitIndex, RangeChange.flip);
    }

    /// Toggles the bits in the half-open range [fromIndex, toIndex).
    void flip(int fromIndex, int toIndex) pure
    {
        changeRange(fromIndex, toIndex, RangeChange.flip);
    }

    /// Finds the first set bit at or after the index, or returns -1.
    int nextSetBit(int fromIndex) const pure
    {
        return findBit(fromIndex, true, true);
    }

    /// Finds the first clear bit at or after the index.
    int nextClearBit(int fromIndex) const pure
    {
        return findBit(fromIndex, false, true);
    }

    /// Finds the last set bit at or before the index, or returns -1.
    int previousSetBit(int fromIndex) const pure
    {
        return findBit(fromIndex, true, false);
    }

    /// Finds the last clear bit at or before the index, or returns -1.
    int previousClearBit(int fromIndex) const pure
    {
        return findBit(fromIndex, false, false);
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
        for (int remaining = wordsInUse; remaining > 0; --remaining)
            count += popcnt(words[remaining - 1]);
        return cast(int) count;
    }

    /// Returns the live bits as an owned little-endian byte array without trailing zero bytes.
    byte[] toByteArray() const pure nothrow
    {
        auto copy = copyLiveWords();
        if (copy.length == 0)
            return null;

        const trailingBytes = (bitMask - bsr(copy[$ - 1])) >> 3;
        version (BigEndian)
        {
            import core.bitop : bswap;

            foreach (ref word; copy)
                word = bswap(word);
        }
        return (cast(byte[]) copy)[0 .. $ - trailingBytes];
    }

    /// Returns the set bits as an owned array of signed words, lowest indices first.
    long[] toLongArray() const pure nothrow
    {
        return cast(long[]) copyLiveWords();
    }

    pragma(inline, false) private ulong[] copyLiveWords() const pure nothrow
    {
        return copyWords(words[0 .. wordsInUse]);
    }

    pragma(inline, false) private static ulong[] copyWords(scope const(ulong)[] source) pure nothrow
    {
        auto copy = new ulong[source.length];
        copy[] = source;
        return copy;
    }

    /// Reports whether the two bit sets have any set bit in common.
    bool intersects(BitSet set) const pure
    {
        if (set is null)
            rejectNullSet();

        const common = wordsInUse < set.wordsInUse ? wordsInUse : set.wordsInUse;
        foreach_reverse (word; 0 .. common)
            if ((words[word] & set.words[word]) != 0)
                return true;
        return false;
    }

    /// Keeps the bits that are also set in the supplied mask.
    void and(BitSet set) pure
    {
        if (this !is set)
            applyMask(set, 0);
    }

    /// Clears the bits that are also set in the supplied mask.
    void andNot(BitSet set) pure
    {
        applyMask(set, ulong.max);
    }

    pragma(inline, false) private void applyMask(scope BitSet set, ulong invert) pure
    {
        if (set is null)
            rejectNullSet();

        int common = wordsInUse < set.wordsInUse ? wordsInUse : set.wordsInUse;
        if (invert == 0 && common < wordsInUse)
            clearTail(common);
        while (common > 0)
        {
            --common;
            words[common] &= set.words[common] ^ invert;
        }
        recalculateWordsInUse();
    }

    pragma(inline, false) private static void rejectNullSet() pure
    {
        import flint.java.lang : NullPointerException;

        throw new NullPointerException();
    }

    private static ulong maskAt(int index) pure nothrow @nogc
    {
        return 1UL << (index & bitMask);
    }

    private void changeBit(int bitIndex, RangeChange change) pure
    {
        checkIndex(bitIndex, 0, "bitIndex < 0: ");
        changeIncludedBits(bitIndex, bitIndex, change);
    }

    private static void checkIndex(int index, int minimum, string label) pure
    {
        if (index < minimum)
            rejectIndex(index, label);
    }

    pragma(inline, false) private static void rejectIndex(int index, string label) pure
    {
        import flint.java.lang : Integer;

        rejectBounds(label ~ Integer.toString(index));
    }

    pragma(inline, false) private static void rejectRange(int fromIndex, int toIndex) pure
    {
        import flint.java.lang : Integer;

        if (fromIndex < 0)
            rejectIndex(fromIndex, "fromIndex < 0: ");
        if (toIndex < 0)
            rejectIndex(toIndex, "toIndex < 0: ");
        rejectBounds("fromIndex: " ~ Integer.toString(fromIndex) ~ " > toIndex: " ~ Integer.toString(toIndex));
    }

    pragma(inline, false) private static void rejectBounds(string message) pure
    {
        import flint.java.lang : IndexOutOfBoundsException;

        throw new IndexOutOfBoundsException(message);
    }

    private void changeRange(int fromIndex, int toIndex, RangeChange change) pure
    {
        if (fromIndex < 0 || toIndex < fromIndex)
            rejectRange(fromIndex, toIndex);
        if (fromIndex != toIndex)
            changeIncludedBits(fromIndex, toIndex - 1, change);
    }

    pragma(inline, false) private void changeIncludedBits(int fromIndex, int lastBit, RangeChange change) pure
    {
        const firstWord = cast(uint) fromIndex >> wordShift;
        auto lastWord = cast(uint) lastBit >> wordShift;
        ulong lastMask = ulong.max >> (bitMask - (lastBit & bitMask));
        if (lastWord >= cast(uint) wordsInUse)
        {
            if (change == RangeChange.clear)
            {
                if (firstWord >= cast(uint) wordsInUse)
                    return;
                lastWord = cast(uint) wordsInUse - 1;
                lastMask = ulong.max;
            }
            else
                expandTo(lastWord);
        }

        const firstMask = ulong.max << (fromIndex & bitMask);
        // Set writes ones, clear writes zeroes, and flip XORs the selected bits.
        const overwrite = change == RangeChange.flip ? 0UL : ulong.max;
        const writeOnes = change == RangeChange.clear ? 0UL : ulong.max;
        auto affected = words[firstWord .. lastWord + 1];
        const first = affected.length == 1 ? firstMask & lastMask : firstMask;
        affected[0] = (affected[0] & ~(first & overwrite)) ^ (first & writeOnes);
        if (affected.length > 1)
        {
            affected[$ - 1] = (affected[$ - 1] & ~(lastMask & overwrite)) ^ (lastMask & writeOnes);
            foreach (ref word; affected[1 .. $ - 1])
                word = (word & ~overwrite) ^ writeOnes;
        }
        if (change != RangeChange.set)
            recalculateWordsInUse();
    }

    pragma(inline, false) private void expandTo(uint word) pure nothrow
    {
        const required = cast(size_t) word + 1;
        if (required > words.length)
        {
            const doubled = 2 * words.length;
            words.length = doubled > required ? doubled : required;
        }
        wordsInUse = cast(int) required;
    }

    pragma(inline, false) private void clearTail(int retained) pure nothrow @nogc
    {
        words[retained .. wordsInUse] = 0;
        wordsInUse = retained;
    }

    pragma(inline, false) private void recalculateWordsInUse() pure nothrow @nogc
    {
        while (wordsInUse != 0 && words[wordsInUse - 1] == 0)
            --wordsInUse;
    }

    pragma(inline, false) private int findBit(int fromIndex, bool set, bool forward) const pure
    {
        const minimum = forward ? 0 : -1;
        if (fromIndex < minimum)
            rejectIndex(fromIndex, forward ? "fromIndex < 0: " : "fromIndex < -1: ");
        return scanBit(fromIndex, set, forward);
    }

    private int scanBit(int fromIndex, bool set, bool forward) const pure nothrow @nogc
    {
        const liveWords = wordsInUse;
        auto word = fromIndex >> wordShift;
        ulong mask = ulong.max;
        if (word >= liveWords)
        {
            if (!set)
                return fromIndex;
            word = forward ? -1 : liveWords - 1;
        }
        else
        {
            const offset = fromIndex & bitMask;
            mask = forward ? mask << offset : mask >> (bitMask - offset);
        }
        if (word < 0)
            return -1;

        const stop = forward ? liveWords : -1;
        const step = forward ? 1 : -1;
        const invert = set ? 0UL : ulong.max;
        auto matches = (words[word] ^ invert) & mask;
        while (matches == 0)
        {
            word += step;
            if (word == stop)
                return forward && !set ? cast(int)(cast(uint) word * wordBits) : -1;
            matches = words[word] ^ invert;
        }
        return word * wordBits + (forward ? bsf(matches) : bsr(matches));
    }
}
