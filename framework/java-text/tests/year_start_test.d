/// Original SimpleDateFormat year-start tests against pinned Temurin behavior.
module flint.java.text.year_start_test;

import flint.java.lang : NullPointerException;
import flint.java.text : SimpleDateFormat;
import flint.java.util : Locale;
import flint.java.util.calendar : GregorianCalendar;
import flint.java.util.date : Date;
import flint.java.util.timezone : TimeZone;
import std.exception : assertThrown;

@safe:

@("set2DigitYearStart updates the caller's calendar and snapshots the date") unittest
{
    static class ObservedCalendar : GregorianCalendar
    {
        int updates;

        this()
        {
            super(TimeZone.getTimeZone("GMT+05:30"));
        }

        override void setTimeInMillis(long millis)
        {
            ++updates;
            super.setTimeInMillis(millis);
        }
    }

    auto format = new SimpleDateFormat("yy-MM-dd", Locale.US);
    auto calendar = new ObservedCalendar();
    calendar.setTimeInMillis(951_782_400_000);
    format.setCalendar(calendar);
    const updatesBefore = calendar.updates;
    auto start = new Date(123_456_789);

    format.set2DigitYearStart(start);
    assert(format.getCalendar() is calendar);
    assert(calendar.getTimeInMillis() == 123_456_789);
    assert(calendar.updates == updatesBefore + 1);

    start.setTime(-99);
    auto result = format.get2DigitYearStart();
    assert(result.getTime() == 123_456_789);
    result.setTime(88);
    assert(format.get2DigitYearStart().getTime() == 123_456_789);
}

@("A null year-start date leaves the installed state intact") unittest
{
    auto format = new SimpleDateFormat("yy-MM-dd", Locale.US);
    format.set2DigitYearStart(new Date(17));

    assertThrown!NullPointerException(format.set2DigitYearStart(null));
    assert(format.get2DigitYearStart().getTime() == 17);
    assert(format.getCalendar().getTimeInMillis() == 17);
}

@("A missing calendar fails after a valid year-start date is stored") unittest
{
    auto format = new SimpleDateFormat("yy-MM-dd", Locale.US);
    format.setCalendar(null);

    assertThrown!NullPointerException(format.set2DigitYearStart(new Date(466)));
    assert(format.get2DigitYearStart().getTime() == 466);
}
