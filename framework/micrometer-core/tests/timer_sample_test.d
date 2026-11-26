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
// The 10 ns recording case follows Micrometer 1.18.0's recordWithSample in
// micrometer-test/src/main/java/io/micrometer/core/tck/MeterRegistryCompatibilityKit.java.
// Modified by the Flint authors.
module micrometer_timer_sample_test;

import core.memory : GC;
import flint.java.lang : ClassCastException, NullPointerException;
import flint.java.util.concurrent : TimeUnit;
import flint.micrometer.core.instrument : Clock, Counter, Meter, MeterRegistry, MockClock, Timer;
import flint.micrometer.core.instrument.simple : SimpleMeterRegistry;
import std.exception : assertThrown;

@safe:

private class ClockedRegistry : MeterRegistry
{
    this(Clock clock)
    {
        super(clock);
    }

    protected override Counter newCounter(Meter.Id id)
    {
        assert(0, "clock tests do not register counters here");
    }
}

private final class RegistryWithoutConfig : ClockedRegistry
{
    this()
    {
        super(Clock.SYSTEM);
    }

    override Config config()
    {
        return null;
    }
}

@("an explicit clock records elapsed nanoseconds on the timer selected at stop")
unittest
{
    auto clock = new MockClock;
    auto sample = Timer.start(clock);
    clock.add(10, TimeUnit.NANOSECONDS);
    auto registry = new SimpleMeterRegistry;
    auto timer = registry.timer("myTimer");

    const allocatedBefore = GC.stats().allocatedInCurrentThread;
    assert(sample.stop(timer) == 10);
    assert(GC.stats().allocatedInCurrentThread == allocatedBefore);
    assert(timer.count() == 1);
    assert(timer.totalTime(TimeUnit.NANOSECONDS) == 10);

    clock.add(5, TimeUnit.NANOSECONDS);
    auto other = registry.timer("otherTimer");
    assert(sample.stop(other) == 15);
    assert(other.count() == 1 && other.totalTime(TimeUnit.NANOSECONDS) == 15);
}

@("a default timer sample reads the system monotonic clock")
unittest
{
    auto timer = (new SimpleMeterRegistry).timer("systemTimer");
    Clock clock = Clock.SYSTEM;
    const earliestStart = clock.monotonicTime();
    auto sample = Timer.start();
    const latestStart = clock.monotonicTime();

    const earliestStop = clock.monotonicTime();
    const elapsed = sample.stop(timer);
    const latestStop = clock.monotonicTime();
    assert(earliestStop - latestStart <= elapsed && elapsed <= latestStop - earliestStart);
    assert(timer.count() == 1 && timer.totalTime(TimeUnit.NANOSECONDS) == elapsed);
}

@("timer sampling rejects a null clock or destination timer")
unittest
{
    assertThrown!NullPointerException(Timer.start(cast(Clock) null));
    auto sample = Timer.start(new MockClock);
    assertThrown!NullPointerException(sample.stop(null));
}

@("a registry retains its configuration and samples its injected clock")
unittest
{
    auto clock = new MockClock;
    auto registry = new ClockedRegistry(clock);
    const allocatedBefore = GC.stats().allocatedInCurrentThread;
    auto configuration = registry.config();
    assert(configuration is registry.config() && configuration.clock() is clock);
    assert(GC.stats().allocatedInCurrentThread == allocatedBefore);
    assert((registry.new Config).clock() is clock);
    assert(MockClock.clock(registry) is clock);

    auto timer = (new SimpleMeterRegistry).timer("myTimer");
    auto sample = Timer.start(registry);
    clock.add(10, TimeUnit.NANOSECONDS);
    assert(sample.stop(timer) == 10);
    assert(timer.count() == 1 && timer.totalTime(TimeUnit.NANOSECONDS) == 10);
}

@("simple registry defaults to the system clock and enforces clock types")
unittest
{
    auto registry = new SimpleMeterRegistry;
    assert(registry.config().clock() is Clock.SYSTEM);
    assertThrown!ClassCastException(MockClock.clock(registry));
    assertThrown!NullPointerException(new ClockedRegistry(null));
    assertThrown!NullPointerException(Timer.start(cast(MeterRegistry) null));
    assertThrown!NullPointerException(MockClock.clock(null));
}

@("registry clock helpers reject a null configuration returned by an override")
unittest
{
    auto registry = new RegistryWithoutConfig;
    assertThrown!NullPointerException(Timer.start(registry));
    assertThrown!NullPointerException(MockClock.clock(registry));
}
