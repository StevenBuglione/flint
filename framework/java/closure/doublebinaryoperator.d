module app;

import flint.java.util.function_.doublebinaryoperator : DoubleBinaryOperator;

@safe:

int main(string[] args)
{
    const value = cast(double) args.length;
    auto subtract = DoubleBinaryOperator.of((double left, double right) => left - right + value);
    auto operation = subtract.asDelegate();
    const result = operation(value, 1);
    return cast(int) result & 127;
}
