module flint.java.primitive_binary_operator_test;

import flint.java.util.function_ : FacadeDoubleBinaryOperator = DoubleBinaryOperator,
    FacadeLongBinaryOperator = LongBinaryOperator;
import flint.java.util.function_.doublebinaryoperator : DoubleBinaryOperator;
import flint.java.util.function_.longbinaryoperator : LongBinaryOperator;

@safe:

unittest
{
    static assert(is(FacadeLongBinaryOperator == LongBinaryOperator));

    long offset = 3;
    auto subtract = LongBinaryOperator.of((long left, long right) => left - right + offset);
    auto apply = subtract.asDelegate();
    assert(subtract.applyAsLong(8, 2) == 9);
    assert(subtract.applyAsLong(long.min, long.min) == 3);
    assert(subtract.applyAsLong(long.max, -1) == long.min + 3);
    offset = -5;
    assert(apply(2, 8) == -11);
}

unittest
{
    static assert(is(FacadeDoubleBinaryOperator == DoubleBinaryOperator));

    static union Bits
    {
        double value;
        ulong raw;
    }

    double factor = 0.5;
    auto average = DoubleBinaryOperator.of((double left, double right) => (left + right) * factor);
    auto apply = average.asDelegate();
    assert(Bits(average.applyAsDouble(-0.0, -0.0)).raw == Bits(-0.0).raw);
    assert(Bits(average.applyAsDouble(double.infinity, 1.0)).raw == Bits(double.infinity).raw);
    factor = 2.0;
    const nan = apply(double.nan, 0.0);
    assert(nan != nan);
}
