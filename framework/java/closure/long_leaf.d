module app;

import flint.java.lang.long_ : Long;

@safe:

int main(string[] args)
{
    const l = cast(long)(args.length * 0x9E37_79B9_7F4A_7C15UL - 7);
    const m = Long.reverseBytes(Long.rotateLeft(Long.valueOf(l ^ Long.MIN_VALUE), 29));
    const order = Long.compare(l, m) ^ Long.compareUnsigned(l, m) ^ Long.signum(m);
    const counts = Long.bitCount(l) + Long.numberOfLeadingZeros(m) + Long.numberOfTrailingZeros(l);
    const masks = Long.highestOneBit(m) + Long.compress(l, m) + Long.expand(m, l) + Long.reverse(l);
    const bits = counts + masks;
    const wide = Long.hashCode(m) + Long.max(l, m) + Long.SIZE * Long.BYTES;
    return cast(int)((order ^ bits ^ wide ^ Long.toString(l).length ^ Long.toHexString(m).length) & 127);
}
