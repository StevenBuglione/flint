module consumer_leaf_test;

import flint.java.util.function_.consumer : Consumer;
import flint.java.util.function_ : PackageConsumer = Consumer;

@safe:

private final class Counter : Consumer!int
{
    private int[] calls;

    override void accept(int value)
    {
        calls ~= value;
    }
}

unittest
{
    static assert(is(Consumer!int == PackageConsumer!int));
    auto counter = new Counter;
    Consumer!int consumer = counter;
    auto append = Consumer!int.of((int value) { counter.calls ~= value * 2; });
    consumer.asDelegate()(3);
    consumer.andThen(append).accept(4);
    assert(counter.calls == [3, 4, 8]);
}

unittest
{
    auto failure = new Exception("first failed");
    auto first = Consumer!int.of((int) { throw failure; });
    bool called;
    auto second = Consumer!int.of((int) { called = true; });
    Exception received;
    try
        first.andThen(second).accept(0);
    catch (Exception error)
        received = error;
    assert(received is failure && !called);
}
