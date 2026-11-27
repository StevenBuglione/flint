module app;

import flint.java.lang.short_ : Short;

@safe:

int main(string[] args)
{
    const s = cast(short)(args.length * 9_973 - 20_000);
    const t = Short.reverseBytes(Short.valueOf(cast(short)(s ^ Short.MIN_VALUE)));
    const order = Short.compare(s, t) ^ Short.compareUnsigned(s, t);
    const wide = Short.toUnsignedInt(s) + Short.toUnsignedLong(t) + Short.hashCode(s) + Short.SIZE * Short.BYTES;
    return cast(int)((order ^ wide ^ Short.toString(s).length ^ Short.MAX_VALUE) & 127);
}
