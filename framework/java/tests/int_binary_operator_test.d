module flint.java.int_binary_operator_test;

import flint.java.util.function_ : FacadeIntBinaryOperator = IntBinaryOperator;
import flint.java.util.function_.intbinaryoperator : IntBinaryOperator;

@safe:

unittest
{
    static assert(is(FacadeIntBinaryOperator == IntBinaryOperator));

    int offset = 3;
    auto subtract = IntBinaryOperator.of((int left, int right) => left - right + offset);
    auto apply = subtract.asDelegate();
    assert(subtract.applyAsInt(8, 2) == 9);
    offset = -5;
    assert(apply(2, 8) == -11);
}
