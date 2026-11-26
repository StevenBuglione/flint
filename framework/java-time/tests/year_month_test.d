module flint.java.time.year_month_test;

import core.memory : GC;
import flint.java.time : DateTimeException, Month;
import flint.java.time.format : DateTimeParseException;
import flint.java.time.yearmonth : YearMonth;

@safe:

@("YearMonth uses ISO months and leap days across the era boundary") unittest
{
    const before = GC.stats().allocatedInCurrentThread;
    const february = YearMonth.of(2000, Month.FEBRUARY);
    assert(february.getYear() == 2000 && february.getMonthValue() == 2 && february.getMonth() == Month.FEBRUARY);
    assert(february.isLeapYear() && february.lengthOfYear() == 366 && february.lengthOfMonth() == 29);
    assert(february.isValidDay(29) && !february.isValidDay(30) && !february.isValidDay(0));
    assert(YearMonth.of(1900, 2).lengthOfMonth() == 28 && YearMonth.of(1900, 2).lengthOfYear() == 365);
    const december = YearMonth.of(0, 1).minusMonths(1);
    assert(december.equals(YearMonth.of(-1, 12)) && december.plusMonths(1).equals(YearMonth.of(0, 1)));
    assert(december.plusYears(2).equals(YearMonth.of(1, 12)));
    assert(december.minusYears(2).equals(YearMonth.of(-3, 12)));
    assert(february.withMonth(3).withYear(-1).isBefore(february));
    assert(february.isAfter(december) && february.compareTo(december) == 2001);
    assert(YearMonth.of(-1, 2).hashCode() == -268_435_457);
    assert(february.atDay(28).getDayOfMonth() == 28 && february.atEndOfMonth().getDayOfMonth() == 29);
    assert(GC.stats().allocatedInCurrentThread == before);
}

@("YearMonth rejects dates and arithmetic outside its supported range") unittest
{
    void rejects(scope void delegate() @safe use)
    {
        try
        {
            use();
            assert(false, "invalid YearMonth operation succeeded");
        }
        catch (DateTimeException)
        {
        }
    }

    rejects(() { YearMonth.of(1, 0); });
    rejects(() { YearMonth.of(1_000_000_000, 1); });
    rejects(() { YearMonth.of(1900, 2).atDay(29); });
    rejects(() { YearMonth.of(999_999_999, 12).plusMonths(1); });
    rejects(() { YearMonth.of(-999_999_999, 1).minusMonths(1); });
    rejects(() { YearMonth.of(0, 1).minusYears(long.min); });
    rejects(() { YearMonth.of(0, 1).minusMonths(long.min); });
}

@("YearMonth keeps its calendar fields private and updates a const value by copy") unittest
{
    static assert(is(YearMonth == struct));
    static assert(!is(typeof(YearMonth(2020, 2))));
    static assert(!is(typeof(YearMonth.init.year_)));
    static assert(!is(typeof(YearMonth.init.month_)));

    const original = YearMonth.of(2020, 2);
    const updated = original.withYear(2021).plusMonths(3);
    assert(original.equals(YearMonth.of(2020, 2)) && original.lengthOfMonth() == 29);
    assert(updated.equals(YearMonth.of(2021, 5)) && updated.lengthOfMonth() == 31);
}

@("YearMonth parses signed ISO years and keeps rejected input") unittest
{
    char[7] input = ['2', '0', '2', '4', '-', '0', '2'];
    const before = GC.stats().allocatedInCurrentThread;
    assert(YearMonth.parse(input[]).equals(YearMonth.of(2024, 2)));
    assert(GC.stats().allocatedInCurrentThread == before);
    assert(YearMonth.parse("+20240-02").toString() == "20240-02");
    assert(YearMonth.parse("-0001-02").toString() == "-0001-02");
    assert(YearMonth.parse("+0000000000-02").toString() == "0000-02");
    assert(YearMonth.parse("+999999999-12").toString() == "999999999-12");
    const leapMonth = YearMonth.of(2000, 2);
    const beforeRender = GC.stats().allocatedInCurrentThread;
    const rendered = leapMonth.toString();
    const renderBytes = GC.stats().allocatedInCurrentThread - beforeRender;
    assert(rendered == "2000-02" && renderBytes > 0 && renderBytes <= 16);

    foreach (testCase; [
        ParseCase("+2024-02", 0), ParseCase("-001-02", 1), ParseCase("2024-2", 5),
        ParseCase("2024-13", 0), ParseCase("2024-02x", 7), ParseCase("+00000000000-02", 11)
    ])
    {
        try
        {
            YearMonth.parse(testCase.text);
            assert(false, "invalid YearMonth text succeeded");
        }
        catch (DateTimeParseException error)
        {
            assert(error.getParsedString() == testCase.text && error.getErrorIndex() == testCase.index);
        }
    }
    try
    {
        input[5] = '?';
        YearMonth.parse(input[]);
        assert(false);
    }
    catch (DateTimeParseException error)
    {
        input[5] = '0';
        assert(error.getParsedString() == "2024-?2" && error.getErrorIndex() == 5);
    }
}

@("YearMonth diagnostics distinguish malformed input from trailing text and preview 64 UTF-16 units") unittest
{
    enum zeros = "00000000000000000000000000000000000000000000000000000000";
    enum exact = "2024-02" ~ zeros ~ "é";
    enum clipped = "2024-02" ~ zeros ~ "🙂x";
    immutable string[2][] cases = [
        ["2024-2", "Text '2024-2' could not be parsed at index 5"],
        ["+00000000000-02", "Text '+00000000000-02' could not be parsed at index 11"],
        ["2024-02x", "Text '2024-02x' could not be parsed, unparsed text found at index 7"],
        ["2024-0😊", "Text '2024-0😊' could not be parsed at index 5"],
        [exact, "Text '" ~ exact ~ "' could not be parsed, unparsed text found at index 7"],
        [
            clipped,
            "Text '2024-02" ~ zeros ~ "�...' could not be parsed, unparsed text found at index 7"
        ]
    ];
    foreach (example; cases)
    {
        try
        {
            YearMonth.parse(example[0]);
            assert(false, example[0]);
        }
        catch (DateTimeParseException error)
        {
            assert(error.getParsedString() == example[0]);
            assert(error.getMessage() == example[1], error.getMessage());
        }
    }
}

private struct ParseCase
{
    string text;
    int index;
}
