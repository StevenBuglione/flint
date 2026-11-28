module biginteger_bit_ops_tests;

import flint.java.lang : ArithmeticException, NullPointerException;
import flint.java.math.biginteger : BigInteger;
import std.conv : to;
import std.exception : assertThrown;
import std.string : split, splitLines;

@safe:

@("BigInteger static constants match Java SE 21 values")
unittest
{
    assert(BigInteger.ZERO.signum() == 0);
    assert(BigInteger.ZERO == BigInteger.valueOf(0));
    assert(BigInteger.ONE == BigInteger.valueOf(1));
    assert(BigInteger.TWO == BigInteger.valueOf(2));
    assert(BigInteger.TEN == BigInteger.valueOf(10));
    assert(BigInteger.ZERO.add(BigInteger.ONE).add(BigInteger.TWO).add(BigInteger.TEN) == BigInteger.valueOf(13));
}

@("BigInteger bit queries, bit mutations, bitwise ops and shifts match Java SE 21")
unittest
{
    size_t rows;
    foreach (line; import("biginteger-bits-java21.tsv").splitLines())
    {
        const fields = line.split("\t");
        auto value = new BigInteger(decodeHex(fields[1]));
        switch (fields[0])
        {
        case "u":
            assert(value.bitCount() == fields[2].to!int, line);
            assert(value.getLowestSetBit() == fields[3].to!int, line);
            assert(value.not().toByteArray() == decodeHex(fields[4]), line);
            break;
        case "b":
            const int bit = fields[2].to!int;
            assert(value.testBit(bit) == (fields[3] == "true"), line);
            assert(value.setBit(bit).toByteArray() == decodeHex(fields[4]), line);
            assert(value.clearBit(bit).toByteArray() == decodeHex(fields[5]), line);
            assert(value.flipBit(bit).toByteArray() == decodeHex(fields[6]), line);
            break;
        case "s":
            const int shift = fields[2].to!int;
            assert(value.shiftLeft(shift).toByteArray() == decodeHex(fields[3]), line);
            assert(value.shiftRight(shift).toByteArray() == decodeHex(fields[4]), line);
            break;
        case "p":
            auto right = new BigInteger(decodeHex(fields[2]));
            assert(value.and(right).toByteArray() == decodeHex(fields[3]), line);
            assert(value.or(right).toByteArray() == decodeHex(fields[4]), line);
            assert(value.xor(right).toByteArray() == decodeHex(fields[5]), line);
            assert(value.andNot(right).toByteArray() == decodeHex(fields[6]), line);
            break;
        default:
            assert(0, line);
        }
        ++rows;
    }
    assert(rows == 1444);
}

@("BigInteger bit and shift boundaries match Java SE 21 exceptions and no-ops")
unittest
{
    assertThrown!ArithmeticException(BigInteger.ZERO.testBit(-1));
    assertThrown!ArithmeticException(BigInteger.ZERO.setBit(-1));
    assertThrown!ArithmeticException(BigInteger.ZERO.clearBit(-1));
    assertThrown!ArithmeticException(BigInteger.ZERO.flipBit(-1));

    auto negOne = BigInteger.valueOf(-1);
    assert(BigInteger.ZERO.testBit(int.max) == false);
    assert(negOne.testBit(int.max) == true);
    assert(negOne.setBit(int.max) is negOne);
    auto zero = BigInteger.ZERO;
    assert(zero.clearBit(int.max) is zero);

    assertThrown!ArithmeticException(BigInteger.ZERO.setBit(int.max));
    assertThrown!ArithmeticException(negOne.clearBit(int.max));
    assertThrown!ArithmeticException(BigInteger.ZERO.flipBit(int.max));

    assert(BigInteger.ONE.shiftLeft(int.min).signum() == 0);
    assert(negOne.shiftLeft(int.min) == negOne);
    assert(BigInteger.ZERO.shiftRight(int.min).signum() == 0);
    assertThrown!ArithmeticException(BigInteger.ONE.shiftRight(int.min));
    assertThrown!ArithmeticException(BigInteger.ONE.shiftLeft(int.max));

    assertThrown!NullPointerException(BigInteger.ONE.and(null));
    assertThrown!NullPointerException(BigInteger.ONE.or(null));
    assertThrown!NullPointerException(BigInteger.ONE.xor(null));
    assertThrown!NullPointerException(BigInteger.ONE.andNot(null));
}

private int nogcBitSummary(scope const BigInteger value) pure nothrow @nogc
{
    return value.bitCount() + value.getLowestSetBit();
}

@("BigInteger bitCount and getLowestSetBit are pure nothrow @nogc")
unittest
{
    assert(nogcBitSummary(BigInteger.valueOf(-8)) == 6);
    assert(nogcBitSummary(BigInteger.ZERO) == -1);
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
