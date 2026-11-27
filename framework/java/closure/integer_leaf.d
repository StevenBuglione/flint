module app;

import flint.java.lang.integer : Integer;

@safe:

int main(string[] args)
{
    const i = cast(int)(args.length * 0x9E37_79B9 - 7);
    const j = Integer.reverseBytes(Integer.rotateLeft(Integer.valueOf(i ^ Integer.MIN_VALUE), 13));
    const order = Integer.compare(i, j) ^ Integer.compareUnsigned(i, j) ^ Integer.signum(j);
    const counts = Integer.bitCount(i) + Integer.numberOfLeadingZeros(j) + Integer.numberOfTrailingZeros(i);
    const masks = Integer.highestOneBit(j) + Integer.compress(i, j) + Integer.expand(j, i) + Integer.reverse(i);
    const bits = counts + masks;
    const wide = Integer.toUnsignedLong(i) + Integer.hashCode(j) + Integer.max(i, j) + Integer.SIZE * Integer.BYTES;
    return cast(int)((order ^ bits ^ wide ^ Integer.toString(i).length ^ Integer.toHexString(j).length) & 127);
}
