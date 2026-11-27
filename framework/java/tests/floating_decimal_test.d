module flint.java.floating_decimal_test;

import flint.java.internal.math.floatingdecimal : FloatingDecimalResult, FloatingDecimalStatus,
    digitListToDouble, parseDouble;

@safe:

// Expected bits come from Double.doubleToRawLongBits on pinned Temurin 21.0.13.
private ulong bitsOf(FloatingDecimalResult result) pure nothrow @nogc
{
    assert(result.status == FloatingDecimalStatus.ok);
    union Bits
    {
        double d;
        ulong u;
    }

    Bits bits;
    bits.d = result.value;
    return bits.u;
}

private ulong parsedBits(scope const(char)[] text) pure nothrow @nogc
{
    return bitsOf(parseDouble(text));
}

private bool rejected(scope const(char)[] text) pure nothrow @nogc
{
    return parseDouble(text).status == FloatingDecimalStatus.numberFormat;
}

@("FloatingDecimal parses Java decimal syntax, trimming, suffixes and special values")
unittest
{
    assert(parsedBits("  1.5  ") == 0x3ff8000000000000);
    assert(parsedBits("\t1.5\n") == 0x3ff8000000000000);
    assert(parsedBits("1.5d") == 0x3ff8000000000000);
    assert(parsedBits("-0") == 0x8000000000000000);
    assert(parsedBits("-NaN") == 0x7ff8000000000000);
    assert(parsedBits("-Infinity") == 0xfff0000000000000);
    assert(parsedBits("2.675") == 0x4005666666666666);
    assert(parsedBits("1e23") == 0x44b52d02c7e14af6);
    assert(parsedBits("9007199254740993") == 0x4340000000000000);

    foreach (text; [
        "", " ", "-", ".", "e5", "1..5", "1e", "1ex", "1e5x", "1ff", "nan", "Infinityx", " 1.5",
        "１", "1_000"
    ])
        assert(rejected(text), text);
    assert(parseDouble("0x1p3").status == FloatingDecimalStatus.hexUnsupported);
}

@("FloatingDecimal rounds halfway, subnormal and overflow boundaries like Java")
unittest
{
    assert(parsedBits("2.2250738585072012e-308") == 0x0010000000000000);
    assert(parsedBits("4.9e-324") == 1);
    assert(parsedBits("2.4703282292062327e-324") == 0);
    assert(parsedBits("2.4703282292062328e-324") == 1);
    assert(parsedBits("1e-324") == 0);
    assert(parsedBits("1.7976931348623158e308") == 0x7fefffffffffffff);
    assert(parsedBits("1.7976931348623159e308") == 0x7ff0000000000000);
}

@("FloatingDecimal clamps out-of-range exponents before conversion")
unittest
{
    assert(parsedBits("1e2147483648") == 0x7ff0000000000000);
    assert(parsedBits("1e-2147483648") == 0);
    assert(parsedBits("0.0000000001e2147483647") == 0x7ff0000000000000);
    assert(parsedBits("123e-2147483647") == 0);
}

@("FloatingDecimal keeps a sticky digit past Java's 1,100-digit truncation")
unittest
{
    // 2^53 + 1 is a tie that rounds to even unless a later nonzero digit lifts it above the midpoint.
    char[1_200] text = '0';
    text[0 .. 17] = "9007199254740993.";
    assert(parsedBits(text[]) == 0x4340000000000000);
    assert(parsedBits(text[0 .. 1_117]) == 0x4340000000000000);
    text[$ - 1] = '1';
    assert(parsedBits(text[]) == 0x4340000000000001);
    text[$ - 1] = '0';
    text[1_100] = '1';
    assert(parsedBits(text[0 .. 1_101]) == 0x4340000000000001);
}

@("DigitList.getDouble parses the stored digits, implicit zeros and decimal exponent")
unittest
{
    assert(bitsOf(digitListToDouble("", 0, 309)) == 0);
    assert(bitsOf(digitListToDouble("1", 1, 0)) == 0x3fb999999999999a);
    assert(bitsOf(digitListToDouble("123", 3, 2)) == 0x402899999999999a);
    assert(bitsOf(digitListToDouble("1", 22, 22)) == 0x444b1ae4d6e2ef50);
    assert(bitsOf(digitListToDouble("1", 1, 309)) == 0x7fe1ccf385ebc8a0);
    assert(bitsOf(digitListToDouble("1", 1, -323)) == 0);
    assert(bitsOf(digitListToDouble("1", 1, int.min)) == 0);
    assert(digitListToDouble("12", 1, 0).status == FloatingDecimalStatus.capacity);
    assert(digitListToDouble("1x", 2, 0).status == FloatingDecimalStatus.numberFormat);
}
