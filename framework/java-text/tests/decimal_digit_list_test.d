module flint.java.text.internal.decimal_digit_list_test;

import flint.java.text.internal.decimaldigitlist : FixedRoundingMode, FixedRoundingStatus, roundFixed;

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
        const count = roundFixed(digits, point, fraction, roundedUp, exact);
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

@("Directed rounding selects by sign and UNNECESSARY reports discarded digits")
unittest
{
    void check(string decimal, bool negative, FixedRoundingMode mode, string expected,
            FixedRoundingStatus expectedStatus = FixedRoundingStatus.complete)
    {
        int point = 1;
        char[8] storage;
        storage[0 .. decimal.length] = decimal;
        FixedRoundingStatus status;
        const count = roundFixed(storage[0 .. decimal.length], point, 0, false, true, negative, mode, status);
        assert(point == 1);
        assert(status == expectedStatus);
        assert(storage[0 .. count] == expected);
    }

    check("25", false, FixedRoundingMode.up, "3");
    check("25", true, FixedRoundingMode.up, "3");
    check("25", false, FixedRoundingMode.down, "2");
    check("25", true, FixedRoundingMode.down, "2");
    check("25", false, FixedRoundingMode.ceiling, "3");
    check("25", true, FixedRoundingMode.ceiling, "2");
    check("25", false, FixedRoundingMode.floor, "2");
    check("25", true, FixedRoundingMode.floor, "3");
    check("25", false, FixedRoundingMode.unnecessary, "2", FixedRoundingStatus.inexact);
}

@("UNNECESSARY retains the pre-mode underflow short circuit")
unittest
{
    int point = -2;
    char[2] digits = "50";
    FixedRoundingStatus status;
    const count = roundFixed(digits[], point, 0, false, true, false, FixedRoundingMode.unnecessary, status);
    assert(count == 0);
    assert(point == -2);
    assert(status == FixedRoundingStatus.complete);
}

@("DigitList half-up and half-down distinguish exact and converted decimal ties")
unittest
{
    static void check(scope const(char)[] decimal, int point, uint fraction, bool roundedUp, bool exact,
            FixedRoundingMode mode, int expectedPoint, scope const(char)[] expected)
    {
        char[17] storage;
        storage[0 .. decimal.length] = decimal;
        auto digits = storage[0 .. decimal.length];
        const count = roundFixed(digits, point, fraction, roundedUp, exact, mode);
        assert(point == expectedPoint && digits[0 .. count] == expected);
    }

    const up = FixedRoundingMode.halfUp;
    const down = FixedRoundingMode.halfDown;
    check("125", 1, 1, false, true, up, 1, "13");
    check("125", 1, 1, false, true, down, 1, "12");
    check("2675", 1, 2, true, false, up, 1, "267");
    check("2675", 1, 2, false, false, down, 1, "268");
    check("9995", 2, 1, false, true, up, 3, "1");
    check("5", -3, 3, false, true, down, -3, "");
    check("50", -3, 3, false, true, down, -2, "1");
    check("9", -4, 3, false, true, up, -4, "");
}
