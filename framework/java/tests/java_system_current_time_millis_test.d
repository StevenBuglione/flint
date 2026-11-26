// Original Flint conformance test for the Java SE 21 System.currentTimeMillis contract.
module flint.java.system_current_time_millis_test;

import flint.java.lang : System;
import flint.java.util.function_.longsupplier : LongSupplier;

@safe:

@("System.currentTimeMillis is an addressable static clock source")
unittest
{
    long function() @safe nothrow @nogc clock = &System.currentTimeMillis;
    auto supplier = LongSupplier.of(() => clock());
    assert(supplier.getAsLong() > 1_767_225_600_000L);
}
