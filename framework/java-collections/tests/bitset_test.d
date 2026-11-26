// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module bitset_test;

import core.memory : GC;
import flint.java.lang : IndexOutOfBoundsException, NullPointerException;
import flint.java.util.bitset : BitSet;
import std.exception : assertThrown;

@safe:

@("toLongArray copies the live words in increasing index order")
unittest
{
    auto bits = new BitSet();
    assert(bits.toLongArray().length == 0);
    bits.set(63);
    bits.set(64);
    bits.set(127);
    bits.set(4_096);
    bits.clear(4_096);
    assert(bits.size() > 128);

    auto copy = bits.toLongArray();
    assert(copy.length == 2);
    assert(copy[0] == long.min && copy[1] == long.min + 1);
    copy[0] = 0;
    assert(bits.get(63));
    bits.clear();
    assert(copy[1] == long.min + 1 && bits.toLongArray().length == 0);
}

@("toLongArray agrees with the Temurin 21.0.13+9 oracle")
unittest
{
    auto bits = new BitSet();
    uint state = 0x42ae_99bb;
    uint digest;
    foreach (step; 0 .. 512)
    {
        state = state * 1_664_525 + 1_013_904_223;
        if ((step & 15) == 0)
            bits.clear();
        bits.flip(cast(int)((state >> 13) & 511));
        const words = bits.toLongArray();
        digest = 31 * digest + cast(uint) words.length;
        foreach (word; words)
            digest = 31 * digest + cast(uint)(word ^ (cast(ulong) word >> 32));
    }
    assert(digest == 944_109_785);
}

@("and clears unmatched words without shrinking or growing capacity")
unittest
{
    auto left = new BitSet();
    left.set(63, 130);
    auto shortMask = new BitSet();
    shortMask.set(63);
    const capacity = left.size();

    assertThrown!NullPointerException(left.and(null));
    left.and(left);
    assert(left.size() == capacity && left.cardinality() == 67);
    left.and(shortMask);
    assert(left.size() == capacity && left.length() == 64 && left.cardinality() == 1);
    assert(shortMask.length() == 64 && shortMask.cardinality() == 1 && shortMask.get(63));
    left.set(129);
    assert(left.cardinality() == 2 && !left.get(128) && !left.get(64));

    auto longMask = new BitSet();
    longMask.set(129);
    longMask.set(4_096);
    left.and(longMask);
    assert(left.size() == capacity && left.cardinality() == 1 && left.get(129));
    assert(longMask.length() == 4_097 && longMask.cardinality() == 2);
    left.and(new BitSet());
    assert(left.size() == capacity && left.isEmpty());
}

@("warmed and does not allocate")
unittest
{
    auto left = new BitSet();
    left.set(129);
    auto mask = new BitSet();
    mask.set(63, 66);
    const before = GC.stats().allocatedInCurrentThread;
    foreach (_; 0 .. 500)
    {
        left.set(62, 130);
        left.and(mask);
        assert(left.cardinality() == 3 && left.length() == 66 && left.get(63));
    }
    assert(GC.stats().allocatedInCurrentThread == before);
}

@("and agrees with the Temurin 21.0.13+9 oracle")
unittest
{
    auto left = new BitSet();
    auto mask = new BitSet();
    uint state = 0x374e_2063;
    uint digest;
    foreach (step; 0 .. 512)
    {
        state = state * 1_664_525 + 1_013_904_223;
        const start = cast(int)((state >> 13) % 320);
        left.set(start, start + 1 + cast(int)(state & 63));
        if ((step & 7) == 0)
            mask.clear();
        const selected = cast(int)((state >> 3) % 257);
        mask.flip(selected, selected + 1 + cast(int)((state >> 9) & 31));
        left.and((step & 31) == 0 ? left : mask);
        digest = 31 * digest + cast(uint) left.size();
        digest = 31 * digest + cast(uint) left.length();
        digest = 31 * digest + cast(uint) left.cardinality();
        foreach (bit; 0 .. 384)
            digest = 31 * digest + (left.get(bit) ? 1u : 0u);
    }
    assert(digest == 3_021_186_246);
}

@("intersects checks both operands without changing capacity or allocating")
unittest
{
    auto left = new BitSet();
    auto right = new BitSet();
    assertThrown!NullPointerException(left.intersects(null));
    assert(!left.intersects(left) && !left.intersects(right));
    left.set(1);
    left.set(127);
    right.set(63);
    right.set(128);
    right.set(4_096);
    assert(!left.intersects(right) && !right.intersects(left));
    right.set(127);
    const leftSize = left.size();
    const rightSize = right.size();

    const before = GC.stats().allocatedInCurrentThread;
    foreach (_; 0 .. 500)
        assert(left.intersects(right) && right.intersects(left) && left.intersects(left));
    assert(GC.stats().allocatedInCurrentThread == before);
    assert(left.size() == leftSize && left.length() == 128 && left.cardinality() == 2);
    assert(right.size() == rightSize && right.length() == 4_097 && right.cardinality() == 4);
}

@("intersects agrees with the Temurin 21.0.13+9 oracle")
unittest
{
    auto left = new BitSet();
    auto right = new BitSet();
    uint state = 0x18c0_5f23;
    uint digest;
    foreach (step; 0 .. 512)
    {
        state = state * 1_664_525 + 1_013_904_223;
        if ((step & 7) == 0)
            left.clear();
        if ((step & 15) == 8)
            right.clear();
        left.set(cast(int)((state >> 3) % 193));
        right.set(cast(int)((state >> 14) % 257));
        digest = 31 * digest + (left.intersects(right) ? 1u : 0u);
        digest = 31 * digest + (right.intersects(left) ? 1u : 0u);
    }
    assert(digest == 437_498_016);
}

@("andNot preserves capacity and clears only overlapping bits")
unittest
{
    auto bits = new BitSet();
    bits.set(64, 140);
    bits.set(1);
    auto mask = new BitSet();
    mask.set(128, 144);
    mask.set(2);
    mask.set(4_096);
    const maskSize = mask.size();

    bits.andNot(mask);
    assert(bits.size() == 192 && bits.length() == 128 && bits.cardinality() == 65);
    assert(bits.get(1) && bits.get(64) && bits.get(127) && !bits.get(128));
    assert(mask.size() == maskSize && mask.length() == 4_097 && mask.cardinality() == 18);
    assert(mask.get(2) && mask.get(128) && mask.get(143) && mask.get(4_096));

    auto shortMask = new BitSet();
    bits.andNot(shortMask);
    assert(bits.cardinality() == 65);
    shortMask.set(1);
    bits.andNot(shortMask);
    assert(bits.size() == 192 && bits.length() == 128 && bits.cardinality() == 64);
    assert(!bits.get(1) && bits.get(64) && bits.get(127));
}

@("andNot rejects null and self-subtraction clears without shrinking")
unittest
{
    auto bits = new BitSet();
    bits.set(63, 130);
    assertThrown!NullPointerException(bits.andNot(null));
    assert(bits.length() == 130 && bits.cardinality() == 67);
    bits.andNot(bits);
    assert(bits.size() == 192 && bits.isEmpty() && bits.cardinality() == 0);
    bits.set(129);
    assert(bits.cardinality() == 1);
}

@("warmed andNot does not allocate")
unittest
{
    auto bits = new BitSet();
    bits.set(129);
    auto mask = new BitSet();
    mask.set(64, 129);
    const before = GC.stats().allocatedInCurrentThread;
    foreach (_; 0 .. 500)
    {
        bits.set(63, 130);
        bits.andNot(mask);
        assert(bits.get(63) && bits.get(129) && bits.cardinality() == 2);
    }
    assert(GC.stats().allocatedInCurrentThread == before);
}

@("andNot agrees with the Temurin 21.0.13+9 oracle")
unittest
{
    auto bits = new BitSet();
    auto mask = new BitSet();
    mask.set(2_048);
    uint state = 0x376a_c921;
    uint digest;
    foreach (step; 0 .. 1_024)
    {
        state = state * 1_664_525 + 1_013_904_223;
        const a = cast(int)((state >> 16) % 321);
        const b = cast(int)((state >> 3) % 321);
        const start = a < b ? a : b;
        const end = a > b ? a : b;
        bits.set(start, end, (state & 64) != 0);
        mask.flip(b);
        if ((step & 7) == 0)
            mask.set(start, end);
        bits.andNot((step & 31) == 0 ? bits : mask);
        foreach (value; [bits.size(), bits.length(), bits.cardinality(), mask.cardinality()])
            digest = 31 * digest + cast(uint) value;
        foreach (bit; 0 .. 321)
        {
            digest = 31 * digest + (bits.get(bit) ? 1u : 0u);
            digest = 31 * digest + (mask.get(bit) ? 1u : 0u);
        }
    }
    assert(digest == 3_409_050_004);
}

@("bit set capacity grows by words and survives clears")
unittest
{
    auto bits = new BitSet();
    assert(bits.size() == 64 && bits.length() == 0 && bits.isEmpty());
    assert(!bits.get(65));

    bits.set(63);
    bits.set(65, true);
    assert(bits.size() == 128 && bits.length() == 66 && bits.cardinality() == 2);
    assert(bits.get(63) && !bits.get(64) && bits.get(65));
    bits.set(65, false);
    assert(bits.length() == 64 && bits.cardinality() == 1 && !bits.get(65));

    bits.flip(128);
    assert(bits.size() == 256 && bits.length() == 129 && bits.cardinality() == 2);
    bits.flip(128);
    bits.clear(600);
    assert(bits.size() == 256 && bits.length() == 64 && bits.cardinality() == 1);
    assert(!bits.get(128));
    bits.clear();
    assert(bits.size() == 256 && bits.isEmpty() && bits.cardinality() == 0);
    assert(!bits.get(63));
}

@("bit searches agree with a scalar model across dense and sparse words")
unittest
{
    auto bits = new BitSet();
    bool[320] model;
    foreach (index, ref value; model[])
    {
        const bit = cast(int) index;
        value = bit < 66 || (bit >= 119 && bit < 199) || (bit % 13 == 3);
        bits.set(bit, value);
    }

    foreach (int from; 0 .. 350)
    {
        int nextSet = -1;
        int nextClear = from;
        while (nextClear < model.length && model[nextClear])
            ++nextClear;
        foreach (int index; from .. cast(int) model.length)
        {
            if (model[index])
            {
                nextSet = index;
                break;
            }
        }
        int previousSet = from < model.length ? from : cast(int) model.length - 1;
        while (previousSet >= 0 && !model[previousSet])
            --previousSet;
        int previousClear = from;
        while (previousClear >= 0 && previousClear < model.length && model[previousClear])
            --previousClear;

        assert(bits.nextSetBit(from) == nextSet);
        assert(bits.nextClearBit(from) == nextClear);
        assert(bits.previousSetBit(from) == previousSet);
        assert(bits.previousClearBit(from) == previousClear);
    }
}

@("bit index validation and warmed operations preserve their contracts")
unittest
{
    auto bits = new BitSet();
    assert(bits.previousSetBit(-1) == -1 && bits.previousClearBit(-1) == -1);
    assert(bits.nextSetBit(0) == -1 && bits.nextClearBit(0) == 0);
    assertThrown!IndexOutOfBoundsException(bits.get(-1));
    assertThrown!IndexOutOfBoundsException(bits.set(-1));
    assertThrown!IndexOutOfBoundsException(bits.clear(-1));
    assertThrown!IndexOutOfBoundsException(bits.flip(-1));
    assertThrown!IndexOutOfBoundsException(bits.nextSetBit(-1));
    assertThrown!IndexOutOfBoundsException(bits.nextClearBit(-1));
    assertThrown!IndexOutOfBoundsException(bits.previousSetBit(int.min));
    assertThrown!IndexOutOfBoundsException(bits.previousClearBit(-2));

    bits.set(130);
    const before = GC.stats().allocatedInCurrentThread;
    foreach (_; 0 .. 500)
    {
        bits.set(64);
        assert(bits.get(64) && bits.nextSetBit(0) == 64 && bits.previousSetBit(140) == 130);
        assert(bits.nextClearBit(64) == 65 && bits.previousClearBit(64) == 63);
        bits.clear(64);
        assert(bits.cardinality() == 1 && bits.length() == 131);
    }
    assert(GC.stats().allocatedInCurrentThread == before);
}

@("bit operations agree with the Temurin 21.0.13+9 oracle")
unittest
{
    auto bits = new BitSet();
    uint state = 0x1357_9ace;
    uint digest;
    foreach (step; 0 .. 1_024)
    {
        state = state * 1_664_525 + 1_013_904_223;
        const index = cast(int)((state >> 16) & 1_023);
        switch (state & 7)
        {
        case 0:
            bits.set(index);
            break;
        case 1:
            bits.set(index, (state & 16) != 0);
            break;
        case 2:
            bits.clear(index);
            break;
        case 3:
            bits.flip(index);
            break;
        case 4:
            if (step % 17 == 0)
                bits.clear();
            break;
        default:
            break;
        }
        const from = cast(int)((state >> 8) & 1_023);
        const int[9] values = [
            bits.get(index) ? 1 : 0, bits.length(), bits.cardinality(), bits.size(),
            bits.isEmpty() ? 1 : 0, bits.nextSetBit(from), bits.nextClearBit(from),
            bits.previousSetBit(from), bits.previousClearBit(from)
        ];
        foreach (value; values)
            digest = 31 * digest + cast(uint) value;
    }
    assert(digest == 1_624_333_499);
}

@("half-open ranges preserve neighbors and clear never grows capacity")
unittest
{
    auto bits = new BitSet();
    bits.set(int.max, int.max);
    bits.flip(int.max, int.max);
    bits.clear(200, int.max);
    assert(bits.size() == 64 && bits.isEmpty());

    bits.set(62, 130);
    assert(bits.size() == 192 && bits.length() == 130 && bits.cardinality() == 68);
    assert(!bits.get(61) && bits.get(62) && bits.get(129) && !bits.get(130));
    bits.set(0, 64, true);
    assert(bits.cardinality() == 130);

    bits.flip(63, 128);
    assert(bits.get(62) && !bits.get(63) && !bits.get(127) && bits.get(128));
    assert(bits.nextSetBit(63) == 128 && bits.cardinality() == 65);
    bits.clear(129, int.max);
    assert(bits.size() == 192 && bits.length() == 129 && bits.cardinality() == 64);
    bits.set(128, 129, false);
    assert(bits.length() == 63 && bits.cardinality() == 63);
}

private void expectRangeFailure(scope void delegate() @safe operation, string message)
{
    try
    {
        operation();
        assert(false, "invalid range succeeded");
    }
    catch (IndexOutOfBoundsException failure)
    {
        assert(failure.msg == message);
    }
}

@("range validation precedes empty checks and preserves Java diagnostics")
unittest
{
    auto bits = new BitSet();
    bits.set(5);
    expectRangeFailure(() => bits.set(-2, -3), "fromIndex < 0: -2");
    expectRangeFailure(() => bits.clear(3, -2), "toIndex < 0: -2");
    expectRangeFailure(() => bits.flip(9, 3), "fromIndex: 9 > toIndex: 3");
    expectRangeFailure(() => bits.set(-1, -1, false), "fromIndex < 0: -1");
    assert(bits.length() == 6 && bits.cardinality() == 1 && bits.get(5));
}

@("warmed range mutations use whole words without allocating")
unittest
{
    auto bits = new BitSet();
    bits.set(129);
    const before = GC.stats().allocatedInCurrentThread;
    foreach (_; 0 .. 500)
    {
        bits.set(63, 130);
        bits.flip(64, 128);
        assert(bits.cardinality() == 3);
        bits.clear(63, int.max);
        assert(bits.isEmpty());
    }
    assert(bits.size() == 192 && GC.stats().allocatedInCurrentThread == before);
}

@("range mutation agrees with the Temurin 21.0.13+9 oracle")
unittest
{
    auto bits = new BitSet();
    uint state = 0x2468_ace1;
    uint digest;
    foreach (step; 0 .. 2_048)
    {
        state = state * 1_664_525 + 1_013_904_223;
        const a = cast(int)((state >> 16) % 321);
        const b = cast(int)((state >> 4) % 321);
        const start = a < b ? a : b;
        const end = (step & 31) == 0 ? start : (a > b ? a : b);
        switch (state & 3)
        {
        case 0:
            bits.set(start, end);
            break;
        case 1:
            bits.clear(start, end);
            break;
        case 2:
            bits.flip(start, end);
            break;
        default:
            bits.set(start, end, (state & 128) != 0);
            break;
        }
        digest = 31 * digest + cast(uint) bits.size();
        digest = 31 * digest + cast(uint) bits.length();
        digest = 31 * digest + cast(uint) bits.cardinality();
        foreach (bit; 0 .. 320)
            digest = 31 * digest + (bits.get(bit) ? 1 : 0);
    }
    assert(digest == 2_742_021_820);
}
