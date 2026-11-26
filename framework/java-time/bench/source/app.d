module app;

import core.stdc.stdio : fputc, stdout;
import flint.java.time : LocalDate;
import flint.java.time.monthday : MonthDay;
import flint.java.time.period : Period;
import flint.java.time.temporal.chronofield : ChronoField, getBaseUnit, range;
import flint.java.time.temporal.chronounit : getDuration;
import flint.java.time.temporal.valuerange : ValueRange;
import flint.java.time.year : Year;
import flint.java.time.yearmonth : YearMonth;

@safe:

int main(string[] args)
{
    if (args.length == 8)
    {
        const result = metadataProbe(args[7], (args[1].length & 1) != 0);
        if (result >= 0)
            return result;
    }

    if (args.length > 5)
    {
        const minimum = cast(long) args[1].length;
        const largestMinimum = minimum + cast(long) args[2].length;
        const smallestMaximum = largestMinimum + cast(long) args[3].length;
        const maximum = smallestMaximum + cast(long) args[4].length;
        const range = ValueRange.of(minimum, largestMinimum, smallestMaximum, maximum);
        if (args.length > 6)
        {
            foreach (c; range.toString())
                fputc(c, stdout);
            fputc('\n', stdout);
        }
        return range.isValidIntValue(cast(long) args[5].length) ? 0 : 1;
    }

    const offset = args.length > 1 ? "P2M3D" : "P6Y3M1D";
    Period period;
    if (args.length > 2)
    {
        static immutable LocalDate[2] january = [
            LocalDate.of(2020, 1, 1), LocalDate.of(2020, 1, 31)
        ];
        static immutable LocalDate[2] march = [LocalDate.of(2020, 3, 1), LocalDate.of(2020, 3, 31)];
        const start = january[args[1].length & 1];
        const end = march[args[2].length & 1];
        period = (args.length & 1) != 0 ? Period.between(start, end) : Period.between(end, start);
    }
    else
        period = Period.parse(offset).plusMonths(10).normalized();
    foreach (c; period.toString())
        fputc(c, stdout);
    fputc('\n', stdout);
    return 0;
}

private int metadataProbe(string name, bool odd)
{
    const field = odd ? ChronoField.DAY_OF_MONTH : ChronoField.NANO_OF_DAY;
    switch (name)
    {
    case "partial-date":
        return Year.of(odd ? 2000 : 1900).atMonthDay(MonthDay.of(2, 29)).getDayOfMonth();
    case "year-month":
        return YearMonth.of(odd ? 2000 : 1900, 2).atEndOfMonth().getDayOfMonth();
    case "chrono-unit":
        return cast(int)(field.getBaseUnit().getDuration().getSeconds() % 127);
    case "chrono-field":
        return cast(int)(field.range().getMaximum() % 127);
    default:
        return -1;
    }
}
