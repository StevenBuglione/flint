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
// Modified by the Flint authors.
module flint.micrometer.core.instrument.simple;

import core.atomic : atomicLoad, atomicOp, cas;
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
    private TimeWindowMax window;
    private shared long events;
    private shared long totalNanos;

    this(Meter.Id id, Clock clock)
    {
        this.id = id;
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
