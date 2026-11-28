module predicate_defaults_test;

import flint.java.lang : NullPointerException;
import flint.java.util.function_ : Predicate;

@safe:

private final class Positive : Predicate!int
{
    mixin Predicate!int.Defaults;

    int calls;

    override bool test(int value)
    {
        ++calls;
        return value > 0;
    }
}

private final class AlwaysTrue : Predicate!int
{
    mixin Predicate!int.Defaults;

    override bool test(int)
    {
        return true;
    }

    override Predicate!int negate()
    {
        return this;
    }
}

unittest
{
    auto positive = new Positive;
    int secondCalls;
    auto second = Predicate!int.of((int) { ++secondCalls; return true; });
    Predicate!int predicate = positive;
    assert(!predicate.and(second).test(0));
    assert(predicate.or(second).test(1));
    assert(secondCalls == 0, "and/or must short-circuit in encounter order");
    assert(predicate.negate().test(0));
}

unittest
{
    auto always = new AlwaysTrue;
    assert(Predicate!int.not(always).test(5), "not dispatches to the target's negate override");
}

unittest
{
    auto predicate = Predicate!int.of((int value) => value > 0);
    bool andRejected;
    try
        predicate.and(null);
    catch (NullPointerException)
        andRejected = true;
    bool orRejected;
    try
        predicate.or(null);
    catch (NullPointerException)
        orRejected = true;
    bool notRejected;
    try
        Predicate!int.not(null);
    catch (NullPointerException)
        notRejected = true;
    assert(andRejected && orRejected && notRejected, "Java requires Objects.requireNonNull");
}
