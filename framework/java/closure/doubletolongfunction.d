module app;

import flint.java.util.function_.doubletolongfunction : DoubleToLongFunction;

@safe:

int main(string[] args)
{
    const value = cast(double) args.length;
    auto widen = DoubleToLongFunction.of((double input) => cast(long) input + 2);
    auto apply = widen.asDelegate();
    return cast(int)(apply(value) & 127);
}
