module app;

import flint.java.util.function_.tolongbifunction : ToLongBiFunction;

@safe:

int main(string[] args)
{
    const value = cast(long) args.length;
    auto product = ToLongBiFunction!(long, long).of((long left, long right) => left * right + value);
    auto apply = product.asDelegate();
    return cast(int)(apply(value, 2) & 127);
}
