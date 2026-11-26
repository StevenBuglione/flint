module app;

import flint.java.time.yearmonth : YearMonth;

@safe:

int main(string[] args)
{
    const year = 2000 - cast(int)(args.length % 800);
    const month = 1 + cast(int)(args.length % 12);
    const value = YearMonth.of(year, month);
    const amount = cast(long) args.length;
    const changed = args.length > 1 ? value.plusMonths(amount)
        .minusYears(amount) : value.plusYears(amount).minusMonths(amount);
    const end = changed.atEndOfMonth();
    return changed.compareTo(value) + changed.hashCode() + end.getDayOfMonth();
}
