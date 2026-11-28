module app;

import flint.java.util.function_.doubletointfunction : DoubleToIntFunction;

@safe:

int main(string[] args)
{
    const value = cast(double) args.length;
    auto narrow = DoubleToIntFunction.of((double input) => cast(int) input + 1);
    auto apply = narrow.asDelegate();
    return (apply(value) & 127);
}
