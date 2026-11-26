module micrometer_timer_primitive_supplier_test;

import core.memory : GC;
import flint.java.lang : NullPointerException;
import flint.java.util.function_.intsupplier : IntSupplier;
import flint.java.util.function_.longsupplier : LongSupplier;
import flint.micrometer.core.instrument : Timer;
import flint.micrometer.core.instrument.simple : SimpleMeterRegistry;
import std.exception : assertThrown;

@safe:

private void verifyPrimitiveReads(Timer timer, long expectedCount)
{
    auto intSupplier = IntSupplier.of(() => int.min);
    auto longSupplier = LongSupplier.of(() => long.max);
    static assert(is(typeof(timer.record(intSupplier)) == int));
    static assert(is(typeof(timer.record(longSupplier)) == long));
    int delegate() @safe readInt = () => int.max;
    long delegate() @safe readLong = () => long.min;
    static assert(is(typeof(timer.record(readInt)) == int));
    static assert(is(typeof(timer.record(readLong)) == long));

    const before = GC.stats().allocatedInCurrentThread;
    assert(timer.record(intSupplier) == int.min);
    assert(timer.record(longSupplier) == long.max);
    assert(timer.record(readInt) == int.max);
    assert(timer.record(readLong) == long.min);
    assert(GC.stats().allocatedInCurrentThread == before);
    assert(timer.count() == expectedCount);
}

@("timer primitive suppliers and scoped delegates keep signed results without allocating")
unittest
{
    auto registry = new SimpleMeterRegistry;
    verifyPrimitiveReads(registry.timer("live"), 4);
    registry.close();
    verifyPrimitiveReads(registry.timer("closed"), 0);
}

@("null and throwing primitive supplier calls contribute to a live timer")
unittest
{
    auto registry = new SimpleMeterRegistry;
    auto timer = registry.timer("failures");
    IntSupplier missingInt;
    LongSupplier missingLong;
    assertThrown!NullPointerException(timer.record(missingInt));
    assertThrown!NullPointerException(timer.record(missingLong));
    assert(timer.count() == 2);

    auto failure = new Exception("primitive supplier");
    auto action = LongSupplier.of(delegate long() @safe { throw failure; });
    try
    {
        timer.record(action);
        assert(0, "the supplier exception should escape the timer");
    }
    catch (Exception error)
    {
        assert(error is failure);
    }
    assert(timer.count() == 3);
}
