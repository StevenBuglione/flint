module flint.java.time.period_test;

import core.memory : GC;
import flint.java.lang : ArithmeticException, NullPointerException, NumberFormatException;
import flint.java.time : LocalDate;
import flint.java.time.format : DateTimeParseException;
import flint.java.time.period : Period;

@safe:

@("ISO period round-trips the text used by Spring's date-time binding") unittest
{
    const period = Period.parse("P6Y3M1D");
    assert(period.getYears() == 6 && period.getMonths() == 3 && period.getDays() == 1);
    assert(period.toString() == "P6Y3M1D");
}

@("period parse handles signed components and folds weeks into days") unittest
{
    assert(Period.parse("-p-1y+2m-3w4d") == Period.of(1, -2, 17));
    assert(Period.parse("P3W-21D") == Period.ZERO);
    assert(Period.parse("P-2147483648Y").toString() == "P-2147483648Y");
    assert(Period.ZERO.toString() == "P0D");
    assert(Period.of(int.min, int.min, int.min).toString() == "P-2147483648Y-2147483648M-2147483648D");
    char[4] input = ['P', '1', '0', 'D'];
    assert(Period.parse(input[]) == Period.ofDays(10));
}

@("period parse preserves the rejected input and reports Java exception types") unittest
{
    foreach (text; ["", "P", "PT1D", "P1D2M", "P1Y2Y", "P+D", "P1.5D", " P1D", "P2147483648D"])
    {
        try
        {
            Period.parse(text);
            assert(false, text);
        }
        catch (DateTimeParseException exception)
        {
            assert(exception.getParsedString() == text && exception.getErrorIndex() == 0);
        }
    }
    try
    {
        Period.parse(null);
        assert(false);
    }
    catch (NullPointerException)
    {
    }

    char[12] input = ['P', '2', '1', '4', '7', '4', '8', '3', '6', '4', '8', 'D'];
    try
    {
        Period.parse(input[]);
        assert(false);
    }
    catch (DateTimeParseException exception)
    {
        input[0] = 'X';
        assert(exception.getParsedString() == "P2147483648D");
        assert(cast(NumberFormatException) exception.getCause() !is null);
    }
    try
    {
        Period.parse("P306783379W");
        assert(false);
    }
    catch (ArithmeticException)
    {
    }
}

@("period numeric overflow identifies the first overflowing digit within its component") unittest
{
    foreach (example; [
            ["P2147483648D", "Error at index 9 in: \"2147483648\""],
            ["P2Y-2147483649M3D", "Error at index 10 in: \"-2147483649\""],
            ["P+21474836480Y", "Error at index 10 in: \"+21474836480\""],
            ["P000000002147483648D", "Error at index 17 in: \"000000002147483648\""]
        ])
    {
        try
        {
            Period.parse(example[0]);
            assert(false, example[0]);
        }
        catch (DateTimeParseException exception)
        {
            const cause = cast(NumberFormatException) exception.getCause();
            assert(cause !is null);
            assert(cause.getMessage() == example[1], cause.getMessage());
            assert(exception.getErrorIndex() == 0);
        }
    }
    assert(Period.parse("P+2147483647D") == Period.ofDays(int.max));
}

@("period arithmetic preserves components until normalization and rejects overflow") unittest
{
    const period = Period.of(1, -14, 3);
    assert(period.isNegative() && !period.isZero());
    assert(period.normalized() == Period.of(0, -2, 3));
    assert(period.toTotalMonths() == -2);
    assert(period.plus(Period.ofWeeks(2)) == Period.of(1, -14, 17));
    assert(period.minus(Period.of(1, 2, 3)) == Period.ofMonths(-16));
    assert(period.withDays(0).withMonths(0).withYears(0) == Period.ZERO);
    assert(period.negated() == Period.of(-1, 14, -3));
    assert(Period.ofDays(-1).plusDays(cast(long) int.max + 1) == Period.ofDays(int.max));
    assert(Period.ofMonths(-1).minusMonths(int.min) == Period.ofMonths(int.max));
    assert(Period.ofDays(int.min).minus(Period.ofDays(int.min)).isZero());
    assert(period.hashCode() == 193_280);

    void rejectsOverflow(scope Period delegate() @safe operation)
    {
        try
        {
            operation();
            assert(false);
        }
        catch (ArithmeticException)
        {
        }
    }

    rejectsOverflow(() => Period.ofWeeks(int.max));
    rejectsOverflow(() => Period.ofDays(int.min).negated());
    rejectsOverflow(() => Period.ofDays(int.max).plusDays(long.max));
    rejectsOverflow(() => Period.ofMonths(int.min).minusMonths(long.min));
    rejectsOverflow(() => Period.of(int.max, 12, 0).normalized());
}

@("period parsing leaves the GC untouched and formatting allocates only the returned text") unittest
{
    char[8] input = ['P', '1', 'Y', '-', '2', 'M', '3', 'D'];
    Period.parse(input[]);
    const before = GC.stats().allocatedInCurrentThread;
    const period = Period.parse(input[]);
    assert(GC.stats().allocatedInCurrentThread == before);

    const rendered = period.toString();
    const bytes = GC.stats().allocatedInCurrentThread - before;
    assert(rendered == input[] && bytes > 0 && bytes <= 16);
}

@("period keeps calendar components private and updates a const value by copy") unittest
{
    static assert(is(Period == struct));
    static assert(!is(typeof(Period(4, 5, 6))));
    static assert(!is(typeof(Period.init.years_)));
    static assert(!is(typeof(Period.init.months_)));
    static assert(!is(typeof(Period.init.days_)));

    const period = Period.of(4, -8, 13);
    const adjusted = period.withMonths(2).plusDays(1);
    assert(period.equals(Period.of(4, -8, 13)));
    assert(adjusted.equals(Period.of(4, 2, 14)));
}

@("period factories use the zero value and hashes retain the Java calendar components") unittest
{
    const zeroPeriods = [
        Period.of(0, 0, 0), Period.ofYears(0), Period.ofMonths(0), Period.ofDays(0), Period.ofWeeks(0)
    ];
    foreach (value; zeroPeriods)
    {
        assert(value.equals(Period.ZERO) && value.isZero() && value.hashCode() == 0);
    }
    assert(Period.ofYears(31).hashCode() == 31);
    assert(Period.ofMonths(31).hashCode() == 7_936);
    assert(Period.ofDays(31).hashCode() == 2_031_616);
    assert(Period.ofDays(32).hashCode() == 2_097_152);
    assert(Period.of(-17, 67_108_864, -268_435_456).hashCode() == 61_427);
    assert(Period.of(int.min, int.max, 1_024).hashCode() == -2_080_374_913);
}

@("period between preserves directed month-end and leap-day differences") unittest
{
    Period between(LocalDate start, LocalDate end) pure nothrow @nogc
    {
        return Period.between(start, end);
    }

    const januaryEnd = LocalDate.of(2020, 1, 31);
    const leapDay = LocalDate.of(2020, 2, 29);
    const marchStart = LocalDate.of(2020, 3, 1);
    const marchEnd = LocalDate.of(2020, 3, 31);
    assert(between(januaryEnd, leapDay) == Period.ofDays(29));
    assert(between(januaryEnd, marchStart) == Period.of(0, 1, 1));
    assert(between(marchStart, januaryEnd) == Period.of(0, -1, -1));
    assert(between(marchEnd, leapDay) == Period.of(0, -1, -2));
    assert(between(leapDay, LocalDate.of(2021, 2, 28)) == Period.of(0, 11, 30));
    assert(between(LocalDate.of(2020, 12, 31), LocalDate.of(2021, 1, 1)) == Period.ofDays(1));
    assert(between(leapDay, leapDay) == Period.ZERO);
    assert(between(LocalDate.MIN, LocalDate.MAX) == Period.of(1_999_999_998, 11, 30));
    assert(between(LocalDate.MAX, LocalDate.MIN) == Period.of(-1_999_999_998, -11, -30));
}
