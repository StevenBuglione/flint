module app;

import flint.java.time.temporal.chronounit : ChronoUnit, toString;

@safe:

int main(string[] args)
{
    const unit = cast(ChronoUnit)(args.length % (cast(size_t) ChronoUnit.max + 1));
    const name = unit.toString();
    return name[0] + name[$ - 1];
}
