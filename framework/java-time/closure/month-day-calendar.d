module app;

import flint.java.time.monthday : MonthDay;

@safe:

int main(string[] args)
{
    const value = MonthDay.of(1, 31).withMonth(1 + cast(int)(args.length % 12));
    const year = 2000 + cast(int)(args.length % 100);
    const date = value.atYear(year);
    return value.hashCode() + date.getDayOfMonth();
}
