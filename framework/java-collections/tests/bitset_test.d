// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module bitset_test;

import core.memory : GC;
import flint.java.lang : IndexOutOfBoundsException;
import flint.java.util.bitset : BitSet;
import std.exception : assertThrown;

@safe:

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
    assert(bits.length() == 64 && bits.cardinality() == 1);

    bits.flip(128);
    assert(bits.size() == 256 && bits.length() == 129 && bits.cardinality() == 2);
    bits.flip(128);
    bits.clear(600);
    assert(bits.size() == 256 && bits.length() == 64 && bits.cardinality() == 1);
    bits.clear();
    assert(bits.size() == 256 && bits.isEmpty() && bits.cardinality() == 0);
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
