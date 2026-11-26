module app;

import core.stdc.stdio : printf;
import flint.java.math.biginteger : BigInteger;

@safe:

int main(string[] args) @system
{
    const byte last = args.length > 1 ? cast(byte) args[1].length : 7;
    auto a = new BigInteger([1, 0, 0, 0, 0, last]);
    const long operand = (1L << 40) + 1;
    auto b = BigInteger.valueOf(operand);
    auto total = a.add(b).subtract(b);
    const bytes = total.toByteArray();
    if (b.longValueExact() != operand)
        return 1;
    if (b.floatValue() != 0x1p40f || b.doubleValue() != operand)
        return 1;
    const text = total.toString(16);
    if (text.length != 11 || text[0] != '1')
        return 1;
    printf("%d %d\n", cast(int) bytes.length, cast(int) bytes[$ - 1]);
    return 0;
}
