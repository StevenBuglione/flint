/*
 * Copyright 2017 VMware, Inc.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * https://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
// Ported from micrometer-core 1.18.0: micrometer-core/src/main/java/io/micrometer/core/instrument/simple/SimpleMeterRegistry.java
// Ported from micrometer-core 1.18.0: micrometer-core/src/main/java/io/micrometer/core/instrument/cumulative/CumulativeCounter.java
// Ported from micrometer-core 1.18.0: micrometer-core/src/main/java/io/micrometer/core/instrument/cumulative/CumulativeTimer.java
// Ported from micrometer-core 1.18.0: micrometer-core/src/main/java/io/micrometer/core/instrument/AbstractTimer.java
// Modified by the Flint authors.
module flint.micrometer.core.instrument.simple;

import core.atomic : atomicLoad, atomicOp, cas;
import flint.java.lang : NullPointerException;
import flint.java.util.concurrent : TimeUnit, toNanos;
import flint.micrometer.core.instrument : Clock, Counter, Meter, MeterRegistry, Timer;
import flint.micrometer.core.instrument.distribution : TimeWindowMax;
import std.typecons : Nullable;

@safe:

/// An in-memory registry for meters whose values are read directly.
class SimpleMeterRegistry : MeterRegistry
{
    /// Create an empty registry in cumulative mode.
    this()
    {
        super(&createTimer);
    }

    protected override Counter newCounter(Meter.Id id)
    {
        return new CumulativeCounter(id);
    }

    private static Timer createTimer(Meter.Id id)
    {
        return new CumulativeTimer(id.withBaseUnit(Nullable!string("seconds")), Clock.SYSTEM);
    }
}

private final class CumulativeTimer : Timer
{
    private Meter.Id id;
    private Clock clock;
    private TimeWindowMax window;
    private shared long events;
    private shared long totalNanos;

    this(Meter.Id id, Clock clock)
    {
        this.id = id;
        this.clock = clock;
        // SimpleConfig's one-minute step overrides the default expiry. The default ring has three buckets.
        window = new TimeWindowMax(clock, 60_000, 3);
    }

    override Meter.Id getId() nothrow @nogc
    {
        return id;
    }

    override void record(long amount, TimeUnit unit) nothrow @nogc
    {
        if (amount < 0)
            return;
        const nanos = unit.toNanos(amount);
        atomicOp!"+="(events, 1L);
        atomicOp!"+="(totalNanos, nanos);
        window.record(cast(double) nanos, TimeUnit.NANOSECONDS);
    }

    override void record(scope void delegate() @safe action)
    {
        const start = clock.monotonicTime();
        scope (exit)
            record(clock.monotonicTime() - start, TimeUnit.NANOSECONDS);
        if (action is null)
            throw new NullPointerException("action");
        action();
    }

    override long count() nothrow @nogc
    {
        return atomicLoad(events);
    }

    override double totalTime(TimeUnit unit) nothrow @nogc
    {
        return cast(double) atomicLoad(totalNanos) / unit.toNanos(1);
    }

    override double max(TimeUnit unit) nothrow @nogc
    {
        return window.poll(unit);
    }

    override TimeUnit baseTimeUnit() nothrow @nogc
    {
        return TimeUnit.SECONDS;
    }

    mixin Timer.Defaults;
}

@("the timer maximum expires after three one-minute steps while cumulative totals remain")
unittest
{
    import flint.micrometer.core.instrument : MockClock, Tags;

    auto clock = new MockClock;
    auto id = new Meter.Id("latency", Tags.empty(), Nullable!string.init, Nullable!string.init, Meter.Type.TIMER);
    auto timer = new CumulativeTimer(id, clock);
    timer.record(2, TimeUnit.SECONDS);
    clock.addSeconds(179);
    assert(timer.max(TimeUnit.SECONDS) == 2);
    clock.addSeconds(1);
    assert(timer.max(TimeUnit.SECONDS) == 0);
    assert(timer.count() == 1 && timer.totalTime(TimeUnit.SECONDS) == 2);
}

@("runnable timing records success and exceptions from the timer's monotonic clock")
unittest
{
    import core.memory : GC;
    import flint.java.lang : IllegalStateException, Runnable;
    import flint.micrometer.core.instrument : MockClock, Tags;
    import std.exception : assertThrown;

    // The successful 10 ns recording follows recordWithRunnable in the pinned Micrometer registry TCK.
    auto clock = new MockClock;
    auto id = new Meter.Id("myTimer", Tags.empty(), Nullable!string.init, Nullable!string.init, Meter.Type.TIMER);
    Timer timer = new CumulativeTimer(id, clock);
    auto action = new AdvanceClock(clock);
    const allocatedBefore = GC.stats().allocatedInCurrentThread;
    timer.record(action);
    assert(GC.stats().allocatedInCurrentThread == allocatedBefore);
    assert(timer.count() == 1 && timer.totalTime(TimeUnit.NANOSECONDS) == 10);

    timer.record(() { clock.add(5, TimeUnit.NANOSECONDS); });
    assert(GC.stats().allocatedInCurrentThread == allocatedBefore);
    assert(timer.count() == 2 && timer.totalTime(TimeUnit.NANOSECONDS) == 15);

    auto failure = new IllegalStateException("task failed");
    void failAfterAdvancingClock()
    {
        clock.add(15, TimeUnit.NANOSECONDS);
        throw failure;
    }

    bool caught;
    try
        timer.record(&failAfterAdvancingClock);
    catch (IllegalStateException error)
        caught = error is failure;
    assert(caught);
    assert(timer.count() == 3 && timer.totalTime(TimeUnit.NANOSECONDS) == 30);

    assertThrown!NullPointerException(timer.record(cast(Runnable) null));
    assert(timer.count() == 4 && timer.totalTime(TimeUnit.NANOSECONDS) == 30);
}

version (unittest)
{
    import flint.java.lang : Runnable;
    import flint.micrometer.core.instrument : MockClock;

    private final class AdvanceClock : Runnable
    {
        private MockClock clock;

        this(MockClock clock)
        {
            this.clock = clock;
        }

        override void run()
        {
            clock.add(10, TimeUnit.NANOSECONDS);
        }
    }
}

@("double supplier timing preserves the primitive result and the original failure")
unittest
{
    import core.memory : GC;
    import flint.java.lang : IllegalStateException;
    import flint.java.util.function_ : DoubleSupplier;
    import flint.micrometer.core.instrument : Tags;
    import std.exception : assertThrown;

    auto clock = new MockClock;
    auto id = new Meter.Id("supplier", Tags.empty(), Nullable!string.init, Nullable!string.init, Meter.Type.TIMER);
    Timer timer = new CumulativeTimer(id, clock);
    auto registry = new SimpleMeterRegistry;
    registry.close();
    auto noop = registry.timer("supplier");
    auto failure = new IllegalStateException("supplier failed");

    double supply()
    {
        clock.add(7, TimeUnit.NANOSECONDS);
        return -0.25;
    }

    double fail()
    {
        clock.add(11, TimeUnit.NANOSECONDS);
        throw failure;
    }

    auto supplier = DoubleSupplier.of(&supply);
    auto failingSupplier = DoubleSupplier.of(&fail);
    const allocatedBefore = GC.stats().allocatedInCurrentThread;
    assert(timer.record(supplier) == -0.25);
    assert(timer.record(() => supply()) == -0.25);
    assert(noop.record(supplier) == -0.25);
    assert(noop.record(&supply) == -0.25);
    assert(GC.stats().allocatedInCurrentThread == allocatedBefore);
    assert(timer.count() == 2 && timer.totalTime(TimeUnit.NANOSECONDS) == 14);
    assert(noop.count() == 0 && noop.totalTime(TimeUnit.NANOSECONDS) == 0);

    bool caught;
    try
        timer.record(failingSupplier);
    catch (IllegalStateException error)
        caught = error is failure;
    assert(caught);
    assert(timer.count() == 3 && timer.totalTime(TimeUnit.NANOSECONDS) == 25);

    assertThrown!NullPointerException(timer.record(cast(DoubleSupplier) null));
    assertThrown!NullPointerException(noop.record(cast(double delegate() @safe) null));
    assert(timer.count() == 4 && timer.totalTime(TimeUnit.NANOSECONDS) == 25);
    assert(noop.count() == 0);
}

@("boolean supplier timing preserves both results for cumulative and closed registries")
unittest
{
    import core.memory : GC;
    import flint.java.util.function_ : BooleanSupplier;
    import flint.micrometer.core.instrument : Tags;
    import std.exception : assertThrown;

    static final class TimedFlag : BooleanSupplier
    {
        private MockClock clock;
        private bool enabled;

        this(MockClock clock)
        {
            this.clock = clock;
        }

        override bool getAsBoolean()
        {
            clock.add(3, TimeUnit.NANOSECONDS);
            enabled = !enabled;
            return enabled;
        }
    }

    auto clock = new MockClock;
    auto id = new Meter.Id("flag", Tags.empty(), Nullable!string.init, Nullable!string.init, Meter.Type.TIMER);
    Timer timer = new CumulativeTimer(id, clock);
    auto registry = new SimpleMeterRegistry;
    registry.close();
    auto noop = registry.timer("flag");
    BooleanSupplier supplier = new TimedFlag(clock);
    const allocatedBefore = GC.stats().allocatedInCurrentThread;
    assert(timer.record(supplier));
    assert(!timer.record(() => supplier.getAsBoolean()));
    assert(noop.record(supplier));
    assert(!noop.record(&supplier.getAsBoolean));
    assert(GC.stats().allocatedInCurrentThread == allocatedBefore);
    assert(timer.count() == 2 && timer.totalTime(TimeUnit.NANOSECONDS) == 6);
    assert(noop.count() == 0 && noop.totalTime(TimeUnit.NANOSECONDS) == 0);

    assertThrown!NullPointerException(timer.record(cast(BooleanSupplier) null));
    assertThrown!NullPointerException(noop.record(cast(bool delegate() @safe) null));
    assert(timer.count() == 3 && timer.totalTime(TimeUnit.NANOSECONDS) == 6);
    assert(noop.count() == 0);
}

@("callable timing preserves nullable values and exceptions without allocating")
unittest
{
    import core.memory : GC;
    import flint.java.lang : IllegalStateException;
    import flint.java.util.concurrent.callable : Callable;
    import flint.micrometer.core.instrument : Tags;
    import std.exception : assertThrown;

    auto clock = new MockClock;
    auto id = new Meter.Id("callable", Tags.empty(), Nullable!string.init, Nullable!string.init, Meter.Type.TIMER);
    Timer timer = new CumulativeTimer(id, clock);
    auto failure = new IllegalStateException("callable failed");

    Nullable!string supply()
    {
        clock.add(8, TimeUnit.NANOSECONDS);
        return Nullable!string("");
    }

    Nullable!string fail()
    {
        clock.add(9, TimeUnit.NANOSECONDS);
        throw failure;
    }

    const allocatedBefore = GC.stats().allocatedInCurrentThread;
    const result = timer.recordCallable(&supply);
    assert(!result.isNull() && result.get() == "");
    assert(GC.stats().allocatedInCurrentThread == allocatedBefore);
    assert(timer.count() == 1 && timer.totalTime(TimeUnit.NANOSECONDS) == 8);

    bool caught;
    try
        timer.recordCallable(&fail);
    catch (IllegalStateException error)
        caught = error is failure;
    assert(caught);
    assert(timer.count() == 2 && timer.totalTime(TimeUnit.NANOSECONDS) == 17);
    assertThrown!NullPointerException(timer.recordCallable(cast(Callable!(Nullable!string)) null));
    assert(timer.count() == 3 && timer.totalTime(TimeUnit.NANOSECONDS) == 17);
}

@("generic supplier timing preserves nullable results and exception identity")
unittest
{
    import core.memory : GC;
    import flint.java.lang : IllegalStateException;
    import flint.java.util.function_ : Supplier;
    import flint.micrometer.core.instrument : Tags;
    import std.exception : assertThrown;

    auto clock = new MockClock;
    auto id = new Meter.Id("generic supplier", Tags.empty(), Nullable!string.init,
            Nullable!string.init, Meter.Type.TIMER);
    Timer timer = new CumulativeTimer(id, clock);
    auto failure = new IllegalStateException("supplier failed");

    Nullable!string supply()
    {
        clock.add(6, TimeUnit.NANOSECONDS);
        return Nullable!string("");
    }

    Nullable!string fail()
    {
        clock.add(11, TimeUnit.NANOSECONDS);
        throw failure;
    }

    auto supplier = Supplier!(Nullable!string).of(&supply);
    const allocatedBefore = GC.stats().allocatedInCurrentThread;
    const result = timer.record(supplier);
    assert(!result.isNull() && result.get() == "");
    assert(GC.stats().allocatedInCurrentThread == allocatedBefore);
    assert(timer.count() == 1 && timer.totalTime(TimeUnit.NANOSECONDS) == 6);

    bool caught;
    try
        timer.record(&fail);
    catch (IllegalStateException error)
        caught = error is failure;
    assert(caught);
    assert(timer.count() == 2 && timer.totalTime(TimeUnit.NANOSECONDS) == 17);
    assertThrown!NullPointerException(timer.record(cast(Supplier!(Nullable!string)) null));
    assert(timer.count() == 3 && timer.totalTime(TimeUnit.NANOSECONDS) == 17);
}

@("a wrapped task records each invocation and propagates the original exception")
unittest
{
    import core.memory : GC;
    import flint.java.lang : IllegalStateException;
    import flint.micrometer.core.instrument : Tags;

    static void delegate() @safe wrapAdvance(Timer timer, MockClock clock)
    {
        long nextAmount = 3;
        return timer.wrap(() { clock.add(nextAmount++, TimeUnit.NANOSECONDS); });
    }

    auto clock = new MockClock;
    auto id = new Meter.Id("wrapped", Tags.empty(), Nullable!string.init, Nullable!string.init, Meter.Type.TIMER);
    Timer timer = new CumulativeTimer(id, clock);
    auto original = new AdvanceClock(clock);
    auto wrapped = timer.wrap(original);
    auto wrappedDelegate = wrapAdvance(timer, clock);
    auto failure = new IllegalStateException("task failed");
    void failAfterAdvancingClock()
    {
        clock.add(5, TimeUnit.NANOSECONDS);
        throw failure;
    }

    auto wrappedFailure = timer.wrap(&failAfterAdvancingClock);
    assert(timer.count() == 0 && clock.monotonicTime() == 1_000_000);

    const allocatedBefore = GC.stats().allocatedInCurrentThread;
    clock.add(100, TimeUnit.NANOSECONDS);
    wrapped.run();
    clock.add(100, TimeUnit.NANOSECONDS);
    wrapped.run();
    wrappedDelegate();
    wrappedDelegate();
    assert(GC.stats().allocatedInCurrentThread == allocatedBefore);
    assert(timer.count() == 4 && timer.totalTime(TimeUnit.NANOSECONDS) == 27);

    bool caught;
    try
        wrappedFailure();
    catch (IllegalStateException error)
        caught = error is failure;
    assert(caught);
    assert(timer.count() == 5 && timer.totalTime(TimeUnit.NANOSECONDS) == 32);
}

private final class CumulativeCounter : Counter
{
    private Meter.Id id;
    private shared double sum = 0.0;

    this(Meter.Id id) nothrow @nogc
    {
        this.id = id;
    }

    override Meter.Id getId() nothrow @nogc
    {
        return id;
    }

    override void increment(double amount) nothrow @nogc
    {
        auto previous = atomicLoad(sum);
        while (!cas(&sum, previous, previous + amount))
            previous = atomicLoad(sum);
    }

    override double count() nothrow @nogc
    {
        return atomicLoad(sum);
    }

    mixin Counter.Defaults;
}
