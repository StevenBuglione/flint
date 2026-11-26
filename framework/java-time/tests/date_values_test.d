module flint.java.time.date_values_test;

import core.memory : GC;
import flint.java.time : DateTimeException, Month;
import flint.java.time.format : DateTimeParseException;
import flint.java.time.monthday : MonthDay;
import flint.java.time.year : Year;
import flint.java.time.yearmonth : YearMonth;
import std.typecons : Nullable;

@safe:

@("partial dates resolve and clip leap days without GC allocation") unittest
{
    const before = GC.stats().allocatedInCurrentThread;
    const leapDay = MonthDay.of(Month.FEBRUARY, 29);
    const leap = Year.of(2000);
    const common = Year.of(1900);
    assert(leap.isLeap() && Year.isLeap(0) && !common.isLeap());
    assert(leap.length() == 366 && common.length() == 365);
    assert(leap.isValidMonthDay(leapDay) && !common.isValidMonthDay(leapDay));
    assert(!leap.isValidMonthDay(Nullable!MonthDay.init));
    assert(leapDay.isValidYear(1_000_000_000));
    assert(leap.atMonthDay(leapDay).getDayOfMonth() == 29 && common.atMonthDay(leapDay).getDayOfMonth() == 28);
    assert(leap.atDay(60).getMonthValue() == 2 && leap.atDay(60).getDayOfMonth() == 29);
    assert(leap.atMonth(Month.FEBRUARY).equals(YearMonth.of(2000, 2)));
    assert(MonthDay.of(1, 31).with_(Month.FEBRUARY).equals(leapDay));
    assert(MonthDay.of(1, 31).withMonth(4).getDayOfMonth() == 30);
    assert(leapDay.withDayOfMonth(28).isBefore(leapDay));
    assert(leapDay.hashCode() == 157 && leap.hashCode() == 2000);
    assert(leap.plusYears(1).isAfter(leap) && common.minusYears(1).compareTo(leap) == -101);
    assert(GC.stats().allocatedInCurrentThread == before);
}

@("partial date parsers match the Java field widths and retain invalid text") unittest
{
    char[7] dayText = ['-', '-', '0', '2', '-', '2', '9'];
    const before = GC.stats().allocatedInCurrentThread;
    assert(Year.parse("+1").getValue() == 1 && Year.parse("-0").getValue() == 0);
    assert(MonthDay.parse(dayText[]).getDayOfMonth() == 29);
    assert(GC.stats().allocatedInCurrentThread == before);
    assert(Year.parse("-1").toString() == "-1");
    assert(MonthDay.parse("--12-31").toString() == "--12-31");

    try
    {
        Year.parse("-1000000000");
        assert(false);
    }
    catch (DateTimeParseException error)
    {
        assert(error.getErrorIndex() == 10);
    }
    try
    {
        dayText[5] = '?';
        MonthDay.parse(dayText[]);
        assert(false);
    }
    catch (DateTimeParseException error)
    {
        dayText[5] = '2';
        assert(error.getErrorIndex() == 5 && error.getParsedString() == "--02-?9");
    }
}

@("year arithmetic and leap-day factories reject invalid dates") unittest
{
    void rejects(scope void delegate() @safe use)
    {
        try
        {
            use();
            assert(false, "invalid partial date operation succeeded");
        }
        catch (DateTimeException)
        {
        }
    }

    assert(Year.of(Year.MIN_VALUE).plusYears(1).getValue() == Year.MIN_VALUE + 1);
    assert(Year.of(Year.MAX_VALUE).minusYears(1).getValue() == Year.MAX_VALUE - 1);
    rejects(() { Year.of(Year.MAX_VALUE).plusYears(1); });
    rejects(() { Year.of(Year.MIN_VALUE).minusYears(1); });
    rejects(() { Year.of(2024).minusYears(long.min); });
    rejects(() { MonthDay.of(2, 30); });
    rejects(() { MonthDay.of(2, 29).withDayOfMonth(30); });
}
