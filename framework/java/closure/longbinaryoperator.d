module app;

import flint.java.util.function_.longbinaryoperator : LongBinaryOperator;

@safe:

int main(string[] args)
{
    const value = cast(long) args.length;
    auto subtract = LongBinaryOperator.of((long left, long right) => left - right + value);
    auto operation = subtract.asDelegate();
    return cast(int) operation(value, 1) & 127;
}
