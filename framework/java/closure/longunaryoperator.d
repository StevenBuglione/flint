module app;

import flint.java.util.function_.longunaryoperator : LongUnaryOperator;

@safe:

int main(string[] args)
{
    const value = cast(long) args.length;
    auto increment = LongUnaryOperator.of((long candidate) => candidate + value);
    auto apply = increment.asDelegate();
    return cast(int)(apply(value) & 127);
}
