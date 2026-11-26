module app;

import flint.java.time.temporal.chronofield : ChronoField, getBaseUnit, getRangeUnit;

@safe:

int main(string[] args)
{
    const field = cast(ChronoField)(args.length % (cast(size_t) ChronoField.max + 1));
    return 31 * cast(int) field.getBaseUnit() + cast(int) field.getRangeUnit();
}
