module flint.java.primitive_conversion_test;

import flint.java.util.function_ : FacadeDoubleToIntFunction = DoubleToIntFunction,
    FacadeDoubleToLongFunction = DoubleToLongFunction,
    FacadeIntToDoubleFunction = IntToDoubleFunction,
    FacadeIntToLongFunction = IntToLongFunction,
    FacadeLongToDoubleFunction = LongToDoubleFunction, FacadeLongToIntFunction = LongToIntFunction;
import flint.java.util.function_.doubletointfunction : DoubleToIntFunction;
import flint.java.util.function_.doubletolongfunction : DoubleToLongFunction;
import flint.java.util.function_.inttodoublefunction : IntToDoubleFunction;
import flint.java.util.function_.inttolongfunction : IntToLongFunction;
import flint.java.util.function_.longtodoublefunction : LongToDoubleFunction;
import flint.java.util.function_.longtointfunction : LongToIntFunction;

@safe:

unittest
{
    static assert(is(FacadeIntToLongFunction == IntToLongFunction));

    long offset = 5;
    auto widen = IntToLongFunction.of((int input) => cast(long) input + offset);
    auto apply = widen.asDelegate();
    assert(widen.applyAsLong(0) == 5);
    assert(widen.applyAsLong(int.max) == cast(long) int.max + 5);
    assert(widen.applyAsLong(int.min) == cast(long) int.min + 5);
    offset = -2;
    assert(apply(10) == 8);
}

unittest
{
    static assert(is(FacadeIntToDoubleFunction == IntToDoubleFunction));

    double factor = 0.5;
    auto scale = IntToDoubleFunction.of((int input) => input * factor);
    auto apply = scale.asDelegate();
    assert(scale.applyAsDouble(4) == 2.0);
    assert(scale.applyAsDouble(-6) == -3.0);
    factor = 2.0;
    assert(apply(3) == 6.0);
}

unittest
{
    static assert(is(FacadeLongToIntFunction == LongToIntFunction));

    int offset = 1;
    auto narrow = LongToIntFunction.of((long input) => cast(int) input + offset);
    auto apply = narrow.asDelegate();
    assert(narrow.applyAsInt(0) == 1);
    assert(narrow.applyAsInt(41) == 42);
    assert(narrow.applyAsInt(-1) == 0);
    offset = -3;
    assert(apply(10) == 7);
}

unittest
{
    static assert(is(FacadeLongToDoubleFunction == LongToDoubleFunction));

    auto scale = LongToDoubleFunction.of((long input) => input / 4.0);
    auto apply = scale.asDelegate();
    assert(scale.applyAsDouble(8) == 2.0);
    assert(scale.applyAsDouble(-2) == -0.5);
    assert(apply(1) == 0.25);
}

unittest
{
    static assert(is(FacadeDoubleToIntFunction == DoubleToIntFunction));

    int offset = 2;
    auto narrow = DoubleToIntFunction.of((double input) => cast(int) input + offset);
    auto apply = narrow.asDelegate();
    assert(narrow.applyAsInt(0.0) == 2);
    assert(narrow.applyAsInt(3.9) == 5);
    assert(narrow.applyAsInt(-4.5) == -2);
    offset = -1;
    assert(apply(7.0) == 6);
}

unittest
{
    static assert(is(FacadeDoubleToLongFunction == DoubleToLongFunction));

    long offset = 1;
    auto widen = DoubleToLongFunction.of((double input) => cast(long) input + offset);
    auto apply = widen.asDelegate();
    assert(widen.applyAsLong(0.0) == 1);
    assert(widen.applyAsLong(-2.5) == -1);
    assert(widen.applyAsLong(1_000_000.0) == 1_000_001);
    offset = 4;
    assert(apply(6.0) == 10);
}
