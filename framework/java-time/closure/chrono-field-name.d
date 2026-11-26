module app;

import flint.java.time.temporal.chronofield : ChronoField, toString;

@safe:

int main(string[] args)
{
    const field = cast(ChronoField)(args.length % (cast(size_t) ChronoField.max + 1));
    const name = field.toString();
    return name[0] + name[$ - 1];
}
