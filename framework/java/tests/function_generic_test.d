module flint.java.function_generic_test;

import flint.java.util.function_ : FacadeDoubleFunction = DoubleFunction,
    FacadeLongFunction = LongFunction, FacadeToDoubleFunction = ToDoubleFunction;
import flint.java.util.function_.doublefunction : DoubleFunction;
import flint.java.util.function_.longfunction : LongFunction;
import flint.java.util.function_.todoublefunction : ToDoubleFunction;

@safe:

unittest
{
    static assert(is(FacadeDoubleFunction!int == DoubleFunction!int));

    int offset = 3;
    auto toInt = DoubleFunction!int.of((double input) => cast(int) input + offset);
    auto apply = toInt.asDelegate();
    assert(toInt.apply(1.5) == 4);
    assert(toInt.apply(-2.9) == 1);
    offset = -1;
    assert(apply(10.0) == 9);
}

unittest
{
    static assert(is(FacadeLongFunction!string == LongFunction!string));

    string prefix = "v";
    auto label = LongFunction!string.of((long input) => prefix ~ cast(char)('0' + input));
    auto apply = label.asDelegate();
    assert(label.apply(2) == "v2");
    prefix = "x";
    assert(apply(7) == "x7");
}

unittest
{
    static assert(is(FacadeToDoubleFunction!int == ToDoubleFunction!int));

    double factor = 0.5;
    auto half = ToDoubleFunction!int.of((int input) => input * factor);
    auto apply = half.asDelegate();
    assert(half.applyAsDouble(6) == 3.0);
    assert(half.applyAsDouble(-2) == -1.0);
    factor = 2.0;
    assert(apply(4) == 8.0);
}
