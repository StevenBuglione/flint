// Original Flint conformance test for the Java SE 21 System.nanoTime contract.
module flint.java.system_nano_time_test;

import core.time : MonoTime, ticksToNSecs;
import flint.java.lang : System;
import flint.java.util.function_.longsupplier : LongSupplier;

@safe:

@("System.nanoTime is an addressable monotonic clock source")
unittest
{
    long function() @safe nothrow @nogc clock = &System.nanoTime;
    auto supplier = LongSupplier.of(() => clock());
    const before = ticksToNSecs(MonoTime.currTime.ticks);
    const first = supplier.getAsLong();
    const second = clock();
    const after = ticksToNSecs(MonoTime.currTime.ticks);
    assert(before <= first && first <= second && second <= after);
}
