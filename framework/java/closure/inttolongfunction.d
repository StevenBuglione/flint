module app;

import flint.java.util.function_.inttolongfunction : IntToLongFunction;

@safe:

int main(string[] args)
{
    const value = cast(int) args.length;
    auto widen = IntToLongFunction.of((int input) => cast(long) input + value);
    auto apply = widen.asDelegate();
    return cast(int)(apply(value) & 127);
}
