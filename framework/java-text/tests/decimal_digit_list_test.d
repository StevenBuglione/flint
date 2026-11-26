module flint.java.text.internal.decimal_digit_list_test;

import flint.java.text.internal.decimaldigitlist : roundFixedHalfEven;

@safe:

@("DigitList fixed-point half-even respects conversion direction and carries")
unittest
{
    static void check(scope const(char)[] decimal, int point, uint fraction, bool roundedUp, bool exact,
            int expectedPoint, scope const(char)[] expected)
    {
        char[17] storage;
        storage[0 .. decimal.length] = decimal;
        auto digits = storage[0 .. decimal.length];
        const count = roundFixedHalfEven(digits, point, fraction, roundedUp, exact);
        assert(point == expectedPoint && digits[0 .. count] == expected);
    }

    check("2675", 1, 2, true, false, 1, "267");
    check("2675", 1, 2, false, false, 1, "268");
    check("1245", 1, 2, false, true, 1, "124");
    check("1235", 1, 2, false, true, 1, "124");
    check("9995", 2, 1, false, true, 3, "1");
    check("8995", 2, 1, false, true, 2, "9");
    check("50", -3, 3, false, false, -3, "");
    check("5", -3, 3, false, false, -2, "1");
    check("9", -4, 3, false, true, -4, "");
    check("15000", 1, 3, false, true, 1, "15");
    check("", 0, 3, false, true, 0, "");
}
