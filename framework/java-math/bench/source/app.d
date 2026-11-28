module app;

import core.stdc.stdio : printf;
import flint.java.math.biginteger : BigInteger;
import flint.java.math.mathcontext : MathContext;
import flint.java.math.roundingmode : name, valueOf, values;

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
    if (b.pow(2).compareTo(b) <= 0)
        return 1;
    const text = total.toString(16);
    if (text.length != 11 || text[0] != '1')
        return 1;
    const int roundingCode = (cast(ubyte) last) & 7;
    const rounding = valueOf(roundingCode);
    if (valueOf(rounding.name()) != rounding || values()[roundingCode] != rounding)
        return 1;
    auto context = new MathContext(roundingCode, rounding);
    if (!new MathContext(context.toString()).equals(context))
        return 1;
    printf("%d %d\n", cast(int) bytes.length, cast(int) bytes[$ - 1]);
    return 0;
}
