module app;

import flint.java.time : LocalDate;

@safe:

int main(string[] args)
{
    const arg = args.length > 1 ? args[1] : "2000-01-01";
    return cast(int)(LocalDate.parse(arg).getYear()) & 127;
}
