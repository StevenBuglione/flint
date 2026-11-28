module app;

import flint.java.util.function_.intunaryoperator : IntUnaryOperator;

@safe:

int main(string[] args)
{
    const value = cast(int) args.length;
    auto increment = IntUnaryOperator.of((int candidate) => candidate + value);
    auto apply = increment.asDelegate();
    return apply(value) & 127;
}
