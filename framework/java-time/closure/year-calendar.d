module app;

import flint.java.time.year : MonthDay, Year;

@safe:

int main(string[] args)
{
    const year = Year.of(1900 + cast(int)(args.length % 500));
    const earlier = year.minusYears(1);
    const later = year.plusYears(1);
    const date = args.length > 1 ? year.atMonthDay(MonthDay.of(2, 29)) : year.atDay(60);
    return earlier.hashCode() + later.hashCode() + year.atMonth(2).lengthOfMonth() + date.getDayOfMonth();
}
