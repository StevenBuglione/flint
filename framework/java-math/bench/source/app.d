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
    auto total = a.add(b).subtract(b).toByteArray();
    if (b.longValueExact() != operand)
        return 1;
    printf("%d %d\n", cast(int) total.length, cast(int) total[$ - 1]);
    return 0;
}
