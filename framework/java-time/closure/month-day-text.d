module app;

import flint.java.time.monthday : MonthDay;

@safe:

int main(string[] args)
{
    const text = args.length > 1 ? args[1] : "--02-29";
    const rendered = MonthDay.parse(text).toString();
    return rendered[2] + rendered[$ - 1];
}
