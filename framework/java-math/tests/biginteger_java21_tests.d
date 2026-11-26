module biginteger_java21_tests;

import flint.java.math.biginteger : BigInteger;
import std.conv : to;
import std.string : split, splitLines;

@safe:

@("BigInteger matches Java SE 21 signed arithmetic and conversions")
unittest
{
    size_t rows;
    foreach (line; import("biginteger-java21.tsv").splitLines())
    {
        const fields = line.split("\t");
        auto value = new BigInteger(decodeHex(fields[1]));
        switch (fields[0])
        {
        case "value":
            checkValue(value, fields);
            break;
        case "pair":
            checkPair(value, fields);
            break;
        case "radix":
            assert(value.toString(fields[2].to!int) == fields[3], line);
            break;
        case "power":
            checkResult(value.pow(fields[2].to!int), fields[3], fields[4]);
            break;
        default:
            assert(0, line);
        }
        ++rows;
    }
    assert(rows == 552);
}

private void checkValue(BigInteger value, scope const(string)[] fields)
{
    const encoded = decodeHex(fields[1]);
    assert(value.toByteArray() == encoded);
    assert(value.signum() == fields[2].to!int);
    assert(value.bitLength() == fields[3].to!int);
    assert(value.hashCode() == fields[4].to!int);
    assert(value.intValue() == fields[5].to!int);
    assert(value.longValue() == fields[6].to!long);

    union FloatEncoding
    {
        float value;
        int bits;
    }

    union DoubleEncoding
    {
        double value;
        long bits;
    }

    FloatEncoding single;
    single.value = value.floatValue();
    DoubleEncoding full;
    full.value = value.doubleValue();
    assert(single.bits == fields[7].to!int, fields[1]);
    assert(full.bits == fields[8].to!long, fields[1]);
    assert(value.abs().toByteArray() == decodeHex(fields[9]));
    assert(value.negate().toByteArray() == decodeHex(fields[10]));

    const byte padding = value.signum() < 0 ? -1 : 0;
    auto equivalent = new BigInteger([padding] ~ encoded);
    assert(value.equals(equivalent));
    assert(value.hashCode() == equivalent.hashCode());
    if (value.bitLength() <= 63)
        assert(BigInteger.valueOf(value.longValue()).toByteArray() == encoded);
}

private void checkPair(BigInteger left, scope const(string)[] fields)
{
    auto right = new BigInteger(decodeHex(fields[2]));
    assert(left.compareTo(right) == fields[3].to!int);
    assert(left.equals(right) == (fields[4] == "true"));
    assert(left.min(right).toByteArray() == decodeHex(fields[5]));
    assert(left.max(right).toByteArray() == decodeHex(fields[6]));
    checkResult(left.add(right), fields[7], fields[8]);
    checkResult(left.subtract(right), fields[9], fields[10]);
    checkResult(left.multiply(right), fields[11], fields[12]);
}

private void checkResult(BigInteger actual, string hex, string sign)
{
    assert(actual.toByteArray() == decodeHex(hex), hex);
    assert(actual.signum() == sign.to!int, hex);
}

private byte[] decodeHex(string hex)
{
    assert(hex.length % 2 == 0);
    auto bytes = new byte[hex.length / 2];
    foreach (i, ref octet; bytes)
    {
        const ubyte high = hexDigit(hex[2 * i]);
        const ubyte low = hexDigit(hex[2 * i + 1]);
        octet = cast(byte)((high << 4) | low);
    }
    return bytes;
}

private ubyte hexDigit(char digit)
{
    if (digit >= '0' && digit <= '9')
        return cast(ubyte)(digit - '0');
    assert(digit >= 'a' && digit <= 'f');
    return cast(ubyte)(digit - 'a' + 10);
}
