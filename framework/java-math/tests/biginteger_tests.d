module biginteger_tests;

import flint.java.lang : IndexOutOfBoundsException, NullPointerException, NumberFormatException;
import flint.java.math.biginteger : BigInteger;

@safe:

@("Java 9 byte ranges copy only the selected bytes")
unittest
{
    byte[] input = [17, -1, 127, 23];
    auto negative = new BigInteger(input, 1, 2);
    auto positive = new BigInteger(1, input, 2, 1);
    input[1 .. 3] = 0;
    assert(negative.toByteArray() == [-1, 127]);
    assert(positive.toByteArray() == [127]);
    assert((new BigInteger(input, 2, 0)).toByteArray() == [0]);
    assert((new BigInteger(-1, input, 0, 0)).signum() == 0);

    auto copy = negative.toByteArray();
    copy[0] = 0;
    assert(negative.toByteArray() == [-1, 127]);
}

@("Signed bytes keep the sign bit at limb boundaries")
unittest
{
    const byte[][] encodings = [
        [0], [-1], [-128], [0, -128], [-1, 127], [-128, 0, 0, 0], [0, -128, 0, 0, 0],
        [-1, 127, -1, -1, -1], [0, -1, -1, -1, -1]
    ];
    foreach (bytes; encodings)
        assert((new BigInteger(bytes)).toByteArray() == bytes);
    assert((new BigInteger([0, 0, 0])).toByteArray() == [0]);
    assert((new BigInteger([-1, -1, -128])).toByteArray() == [-128]);
    assert((new BigInteger(-1, [0, 0, 0])).signum() == 0);
}

@("Binary constructors distinguish empty signed encodings from empty magnitudes")
unittest
{
    import std.exception : assertThrown;

    byte[] empty = [];
    assertThrown!NumberFormatException(new BigInteger(empty));
    assertThrown!NumberFormatException(new BigInteger(new byte[0]));
    assertThrown!NumberFormatException(new BigInteger(cast(byte[]) null));
    assertThrown!NumberFormatException(new BigInteger((new byte[1])[0 .. 0]));
    assert((new BigInteger(0, new byte[0])).signum() == 0);
    assert((new BigInteger(-1, cast(byte[]) null)).signum() == 0);
    assertThrown!NumberFormatException(new BigInteger(cast(byte[]) null, 0, 0));
    assert((new BigInteger(-1, cast(byte[]) null, 0, 0)).signum() == 0);
}

@("Binary constructors reject invalid signs and slices")
unittest
{
    import std.exception : assertThrown;

    assertThrown!NumberFormatException(new BigInteger(2, [1]));
    assertThrown!NumberFormatException(new BigInteger(0, [0, 1]));
    assertThrown!IndexOutOfBoundsException(new BigInteger([1], 1, 1));
    assertThrown!IndexOutOfBoundsException(new BigInteger(1, [1], int.max, 1));
}

@("Signed arithmetic cancels to zero and shares no mutable bytes")
unittest
{
    import std.exception : assertThrown;

    auto negative = new BigInteger([-128, 0, 0, 0]);
    auto positive = new BigInteger(1, [-128, 0, 0, 0]);
    assert(positive.add(negative).signum() == 0);
    assert(negative.subtract(negative).toByteArray() == [0]);
    assert(negative.add(negative).toByteArray() == [-1, 0, 0, 0, 0]);
    assert(positive.subtract(negative).toByteArray() == [1, 0, 0, 0, 0]);
    assert(negative.compareTo(positive) < 0);
    assert(positive.compareTo(negative) > 0);
    assert(negative.compareTo(new BigInteger([-1, -128, 0, 0, 0])) == 0);
    assertThrown!NullPointerException(negative.add(null));
}

@("Extrema reuse their operands and reject null") unittest
{
    import std.exception : assertThrown;

    auto negative = BigInteger.valueOf(long.min);
    auto positive = negative.negate();
    assert(positive.toByteArray() == [0, -128, 0, 0, 0, 0, 0, 0, 0]);
    assert(negative.longValueExact() == long.min);
    assert(negative.abs() == positive);
    assert(positive.abs() is positive);
    assert(negative.min(positive) is negative);
    assert(negative.max(positive) is positive);
    assertThrown!NullPointerException(negative.min(null));
    assertThrown!NullPointerException(negative.max(null));
}
