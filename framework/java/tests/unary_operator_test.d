module unary_operator_test;

import flint.java.util.function_ : LegacyFunction = Function, LegacyUnary = UnaryOperator;
import flint.java.util.function_.function_ : Function;
import flint.java.util.function_.unaryoperator : UnaryOperator;

@safe:

static assert(is(LegacyFunction!(int, int) == Function!(int, int)));
static assert(is(LegacyUnary!int == UnaryOperator!int));

unittest
{
    auto sentinel = new Object;
    UnaryOperator!Object identity = UnaryOperator!Object.identity();
    Function!(Object, Object) base = identity;
    assert(identity.apply(sentinel) is sentinel);
    assert(identity.apply(null) is null);
    assert(base.apply(sentinel) is sentinel);
    assert(UnaryOperator!int.identity().apply(int.min) == int.min);
    assert(Function!(int, int).identity().apply(int.max) == int.max);
}
