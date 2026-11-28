module app;

import flint.java.util.function_.doublefunction : DoubleFunction;

@safe:

int main(string[] args)
{
    const value = cast(double) args.length;
    auto toInt = DoubleFunction!int.of((double input) => cast(int) input + 1);
    auto apply = toInt.asDelegate();
    return apply(value) & 127;
}
