module app;

import flint.java.util.function_.tointbifunction : ToIntBiFunction;

@safe:

int main(string[] args)
{
    const value = cast(int) args.length;
    auto sum = ToIntBiFunction!(int, int).of((int left, int right) => left + right + value);
    auto apply = sum.asDelegate();
    return apply(value, 1) & 127;
}
