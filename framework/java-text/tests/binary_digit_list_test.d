module flint.java.text.internal.binary_digit_list_test;

import flint.java.text.internal.binarydecimal : BinaryDecimal;
import flint.java.text.internal.decimaldigitlist : tryFixedBinaryDecimal;

@safe:

@("Fixed-point binary64 conversion preserves Java ties and signed zeros")
unittest
{
    static void check(ulong bits, uint limit, string digits, int point, bool negative)
    {
        BinaryDecimal value;
        assert(tryFixedBinaryDecimal(bits, limit, value));
        assert(value.digits[0 .. value.count] == digits);
        assert(value.decimalAt == point && value.negative == negative);
    }

    check(0x4005_6666_6666_6666, 2, "267", 1, false);
    check(0x3f40_624d_d2f1_a9fc, 3, "", -3, false);
    check(0xbf40_624d_d2f1_a9fc, 3, "", -3, true);
    check(0x8000_0000_0000_0000, 2, "", 0, true);
    check(0x44b5_2d02_c7e1_4af6, 0, "9999999999999999", 23, false);

    BinaryDecimal previous;
    assert(tryFixedBinaryDecimal(0x8000_0000_0000_0000, 0, previous));
    BinaryDecimal value = previous;
    assert(!tryFixedBinaryDecimal(0x7ff8_0000_0000_0000, 2, value));
    assert(value == previous);
}
