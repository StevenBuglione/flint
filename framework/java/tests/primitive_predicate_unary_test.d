module flint.java.primitive_predicate_unary_test;

import flint.java.util.function_ : FacadeDoublePredicate = DoublePredicate,
    FacadeDoubleUnaryOperator = DoubleUnaryOperator, FacadeIntPredicate = IntPredicate,
    FacadeIntUnaryOperator = IntUnaryOperator,
    FacadeLongPredicate = LongPredicate, FacadeLongUnaryOperator = LongUnaryOperator;
import flint.java.util.function_.doublepredicate : DoublePredicate;
import flint.java.util.function_.doubleunaryoperator : DoubleUnaryOperator;
import flint.java.util.function_.intpredicate : IntPredicate;
import flint.java.util.function_.intunaryoperator : IntUnaryOperator;
import flint.java.util.function_.longpredicate : LongPredicate;
import flint.java.util.function_.longunaryoperator : LongUnaryOperator;

@safe:

unittest
{
    static assert(is(FacadeIntPredicate == IntPredicate));
    static assert(is(FacadeLongPredicate == LongPredicate));
    static assert(is(FacadeDoublePredicate == DoublePredicate));

    int offset = 1;
    auto aboveOffset = IntPredicate.of((int candidate) => candidate > offset);
    auto testInt = aboveOffset.asDelegate();
    assert(aboveOffset.test(2));
    assert(!testInt(1));
    offset = -1;
    assert(testInt(0));

    long bound = 1L << 40;
    auto aboveBound = LongPredicate.of((long candidate) => candidate > bound);
    auto testLong = aboveBound.asDelegate();
    assert(aboveBound.test((1L << 40) + 1));
    assert(!testLong(1L << 40));
    bound = long.min;
    assert(testLong(long.min + 1));
    assert(!testLong(long.min));

    double threshold = 0.5;
    auto aboveThreshold = DoublePredicate.of((double candidate) => candidate > threshold);
    auto testDouble = aboveThreshold.asDelegate();
    assert(aboveThreshold.test(0.75));
    assert(!testDouble(0.5));
    threshold = -0.25;
    assert(testDouble(0.0));
}

unittest
{
    static assert(is(FacadeIntUnaryOperator == IntUnaryOperator));
    static assert(is(FacadeLongUnaryOperator == LongUnaryOperator));
    static assert(is(FacadeDoubleUnaryOperator == DoubleUnaryOperator));

    int offset = 3;
    auto shiftInt = IntUnaryOperator.of((int candidate) => candidate + offset);
    auto applyInt = shiftInt.asDelegate();
    assert(shiftInt.applyAsInt(4) == 7);
    offset = -5;
    assert(applyInt(2) == -3);

    long wide = 1L << 40;
    auto shiftLong = LongUnaryOperator.of((long candidate) => candidate * wide);
    auto applyLong = shiftLong.asDelegate();
    assert(shiftLong.applyAsLong(2) == (1L << 41));
    wide = -1;
    assert(applyLong(7) == -7);

    double factor = 0.5;
    auto scaleDouble = DoubleUnaryOperator.of((double candidate) => candidate * factor);
    auto applyDouble = scaleDouble.asDelegate();
    assert(scaleDouble.applyAsDouble(6.0) == 3.0);
    factor = 2.0;
    assert(applyDouble(1.5) == 3.0);
}
