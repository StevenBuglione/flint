// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module app;

import flint.java.util.bitset : BitSet;

@safe:

int main(string[] args)
{
    if (args.length == 0)
        return 1;
    const start = cast(int)(args.length & 1_023) + 64;
    auto bits = new BitSet();
    bits.set(start);
    bits.set(start + 1, true);
    bits.flip(start + 1);
    bits.clear(start + 2);
    if (!bits.get(start) || bits.cardinality() != 1 || bits.length() != start + 1 || bits.size() <= start)
        return 1;
    if (bits.nextSetBit(0) != start || bits.previousSetBit(start + 5) != start)
        return 1;
    if (bits.nextClearBit(start) != start + 1 || bits.previousClearBit(start) != start - 1)
        return 1;
    if (!BitSet.valueOf(bits.toLongArray()).get(start))
        return 1;
    bits.clear();
    return bits.isEmpty() ? 0 : 1;
}
