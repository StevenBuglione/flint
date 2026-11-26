module app;

import flint.java.util.function_.intbinaryoperator : IntBinaryOperator;

@safe:

int main(string[] args)
{
    const value = cast(int) args.length;
    auto subtract = IntBinaryOperator.of((int left, int right) => left - right + value);
    auto operation = subtract.asDelegate();
    return operation(value, 1) & 127;
}
