module flint.java.function_bi_test;

import flint.java.util.function_ : FacadeToDoubleBiFunction = ToDoubleBiFunction,
    FacadeToIntBiFunction = ToIntBiFunction, FacadeToLongBiFunction = ToLongBiFunction;
import flint.java.util.function_.todoublebifunction : ToDoubleBiFunction;
import flint.java.util.function_.tointbifunction : ToIntBiFunction;
import flint.java.util.function_.tolongbifunction : ToLongBiFunction;

@safe:

unittest
{
    static assert(is(FacadeToIntBiFunction!(int, int) == ToIntBiFunction!(int, int)));

    int offset = 3;
    auto sum = ToIntBiFunction!(int, int).of((int left, int right) => left + right + offset);
    auto apply = sum.asDelegate();
    assert(sum.applyAsInt(2, 4) == 9);
    assert(sum.applyAsInt(-2, 1) == 2);
    offset = -1;
    assert(apply(5, 5) == 9);
}

unittest
{
    static assert(is(FacadeToLongBiFunction!(long, long) == ToLongBiFunction!(long, long)));

    long offset = 1;
    auto product = ToLongBiFunction!(long, long).of((long left, long right) => left * right + offset);
    auto apply = product.asDelegate();
    assert(product.applyAsLong(3, 4) == 13);
    assert(product.applyAsLong(-2, 5) == -9);
    offset = 10;
    assert(apply(2, 2) == 14);
}

unittest
{
    static assert(is(FacadeToDoubleBiFunction!(int, int) == ToDoubleBiFunction!(int, int)));

    double factor = 0.5;
    auto mean = ToDoubleBiFunction!(int, int).of((int left, int right) => (left + right) * factor);
    auto apply = mean.asDelegate();
    assert(mean.applyAsDouble(2, 4) == 3.0);
    assert(mean.applyAsDouble(-2, 0) == -1.0);
    factor = 2.0;
    assert(apply(1, 3) == 8.0);
}
