module flint.java.text.internal.binary_integer_decimal_test;

import flint.java.text.internal.binarydecimal : BinaryDecimal, tryIntegerBinaryDecimal;

@safe:

@("FloatingDecimal integer branch preserves its digits, sign and flags")
unittest
{
    static void check(ulong bits, string text, int point, bool negative = false)
    {
        BinaryDecimal result;
        result.roundedUp = true;
        result.exact = true;
        assert(tryIntegerBinaryDecimal(bits, result));
        assert(result.digits[0 .. result.count] == text && result.decimalAt == point);
        assert(result.negative == negative && !result.roundedUp && !result.exact);
    }

    check(0, "0", 0);
    check(0x8000_0000_0000_0000, "0", 0, true);
    check(0x3ff0_0000_0000_0000, "1", 1);
    check(0x4340_0000_0000_0000, "9007199254740992", 16);
    check(0x43d0_0000_0000_0000, "46116860184273879", 19);
    check(0xc3df_ffff_ffff_ffff, "92233720368547748", 19, true);
}

@("FloatingDecimal integer branch leaves output untouched outside its domain")
unittest
{
    BinaryDecimal result;
    assert(tryIntegerBinaryDecimal(0x3ff0_0000_0000_0000, result));
    const previous = result;
    foreach (bits; [
        1UL, 0x3fe0_0000_0000_0000, 0x3ff8_0000_0000_0000, 0x43e0_0000_0000_0000,
        0x7ff0_0000_0000_0000, 0x7ff8_0000_0000_0000
    ])
    {
        assert(!tryIntegerBinaryDecimal(bits, result));
        assert(result == previous);
    }
}
