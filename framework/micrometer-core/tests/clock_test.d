module micrometer_clock_test;

import core.memory : GC;
import flint.java.lang : ArithmeticException;
import flint.java.time : Duration;
import flint.java.util.concurrent : TimeUnit;
import flint.micrometer.core.instrument : Clock, MockClock;
import std.exception : assertThrown;

@safe:

@("the system clock is shared and samples wall time and monotonic time without allocation")
unittest
{
    const before = GC.stats().allocatedInCurrentThread;
    Clock clock = Clock.SYSTEM;
    assert(clock !is null && clock is Clock.SYSTEM);
    const first = clock.monotonicTime();
    const wall = clock.wallTime();
    const second = clock.monotonicTime();
    assert(GC.stats().allocatedInCurrentThread == before);
    assert(wall > 1_767_225_600_000);
    assert(second >= first);
}

@("a mock clock preserves submillisecond elapsed time and reports wall time in milliseconds")
unittest
{
    auto clock = new MockClock;
    assert(clock.monotonicTime() == 1_000_000);
    assert(clock.wallTime() == 1);
    assert(clock.add(1_500, TimeUnit.MICROSECONDS) == 2_500_000);
    assert(clock.add(Duration.ofNanos(2)) == 2_500_002);
    assert(clock.wallTime() == 2);
    assert(clock.addSeconds(2) == 2_002_500_002);
    assert(clock.wallTime() == 2_002);
    assert(clock.add(-1, TimeUnit.MILLISECONDS) == 2_001_500_002);
    assertThrown!ArithmeticException(clock.add(Duration.ofSeconds(long.max)));
    assert(clock.monotonicTime() == 2_001_500_002);
}
