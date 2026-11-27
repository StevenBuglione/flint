module app;

import flint.java.lang.byte_ : Byte;

@safe:

int main(string[] args)
{
    const b = cast(byte)(args.length * 37 - 100);
    const c = Byte.valueOf(cast(byte)(b ^ Byte.MIN_VALUE));
    const order = Byte.compare(b, c) ^ Byte.compareUnsigned(b, c);
    const wide = Byte.toUnsignedInt(b) + Byte.toUnsignedLong(c) + Byte.hashCode(b) + Byte.SIZE * Byte.BYTES;
    return cast(int)((order ^ wide ^ Byte.toString(b).length ^ Byte.MAX_VALUE) & 127);
}
