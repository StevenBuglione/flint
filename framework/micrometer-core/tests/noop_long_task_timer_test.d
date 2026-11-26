/*
 * Copyright 2019 VMware, Inc.
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
// Ported from micrometer-core 1.18.0: micrometer-core/src/test/java/io/micrometer/core/instrument/noop/NoopLongTaskTimerTest.java
// Modified by the Flint authors.
module micrometer_noop_long_task_timer_test;

import core.memory : GC;
import flint.java.util : List;
import flint.java.util.concurrent : TimeUnit;
import flint.micrometer.core.instrument : LongTaskTimer, Measurement, Meter, Tags;
import flint.micrometer.core.instrument.noop : NoopLongTaskTimer, NoopMeter;
import std.typecons : Nullable;

@safe:

private Meter.Id testId()
{
    return new Meter.Id("test", Tags.of("name", "value"), Nullable!string("ms"),
            Nullable!string(""), Meter.Type.LONG_TASK_TIMER);
}

@("returnsId")
unittest
{
    auto id = testId();
    NoopMeter timer = new NoopLongTaskTimer(id);
    assert(timer.getId() is id);
}

@("returnsStart")
unittest
{
    auto timer = new NoopLongTaskTimer(testId());
    static assert(!__traits(compiles, new LongTaskTimer.Sample));
    assert(timer.start() !is null);
}

@("returnsDuration")
unittest
{
    auto timer = new NoopLongTaskTimer(testId());
    assert(timer.duration(TimeUnit.MINUTES) == 0.0);
}

@("returnsActiveTasks")
unittest
{
    auto timer = new NoopLongTaskTimer(testId());
    assert(timer.activeTasks() == 0);
}

@("no-op long task samples are distinct and always return zero")
unittest
{
    auto timer = new NoopLongTaskTimer(testId());
    auto sample = timer.start();
    assert(sample !is timer.start());
    assert(timer.baseTimeUnit() == TimeUnit.SECONDS);
    assert(sample.duration(TimeUnit.MICROSECONDS) == 0.0);
    assert(sample.stop() == 0);
    assert(sample.duration(TimeUnit.NANOSECONDS) == 0.0);
    assert(sample.stop() == 0);
    assert(timer.activeTasks() == 0);
}

@("no-op long task timers share empty measurements and allocate nothing when reading them")
unittest
{
    auto timer = new NoopLongTaskTimer(testId());
    LongTaskTimer meter = timer;
    List!Measurement empty = timer.measure();
    assert(empty.isEmpty());
    const before = GC.stats().allocatedInCurrentThread;
    foreach (iteration; 0 .. 256)
    {
        assert(meter.duration(TimeUnit.SECONDS) == 0.0);
        assert(meter.max(TimeUnit.SECONDS) == 0.0);
        assert(meter.mean(TimeUnit.SECONDS) == 0.0);
        assert(meter.measure() is empty);
    }
    assert(GC.stats().allocatedInCurrentThread == before);
}

@("long task timer defaults keep snapshot dispatch and legacy task IDs")
unittest
{
    static final class SampledTimer : NoopLongTaskTimer
    {
        alias duration = NoopLongTaskTimer.duration;

        bool active;
        uint durationReads;

        this(Meter.Id id) @safe
        {
            super(id);
        }

        override int activeTasks() @safe
        {
            return active ? 2 : 0;
        }

        override double duration(TimeUnit unit) @safe
        {
            ++durationReads;
            assert(unit == TimeUnit.MILLISECONDS);
            return 5.0;
        }
    }

    auto timer = new SampledTimer(testId());
    assert(timer.mean(TimeUnit.MILLISECONDS) == 0.0 && timer.durationReads == 0);
    timer.active = true;
    assert(timer.mean(TimeUnit.MILLISECONDS) == 2.5 && timer.durationReads == 1);
    assert(timer.duration(42, TimeUnit.MILLISECONDS) == -1.0 && timer.durationReads == 1);
    assert(timer.stop(42) == -1);
    auto snapshot = timer.takeSnapshot(true);
    assert(snapshot.count() == 0 && snapshot.total() == 0.0 && snapshot.max() == 0.0);
    assert(snapshot.histogramCounts().length == 0 && snapshot.percentileValues().length == 0);
}
