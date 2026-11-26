module app;

import flint.java.time.yearmonth : YearMonth;

@safe:

int main(string[] args)
{
    const input = args.length > 1 ? args[1] : "2024-02";
    const rendered = YearMonth.parse(input).toString();
    return rendered[0] + rendered[$ - 1];
}
