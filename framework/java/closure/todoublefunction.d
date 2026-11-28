module app;

import flint.java.util.function_.todoublefunction : ToDoubleFunction;

@safe:

int main(string[] args)
{
    const value = cast(int) args.length;
    auto half = ToDoubleFunction!int.of((int input) => input * 0.5);
    auto apply = half.asDelegate();
    return (cast(int) apply(value)) & 127;
}
