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
// Ported from micrometer-core 1.18.0: micrometer-core/src/test/java/io/micrometer/core/instrument/noop/NoopFunctionTimerTest.java
// Modified by the Flint authors.
module micrometer_function_timer_test;

import core.memory : GC;
import flint.java.util.concurrent : TimeUnit, toNanos;
import flint.micrometer.core.instrument : AbstractMeter, FunctionTimer, Meter, Statistic, Tags;
import flint.micrometer.core.instrument.noop : NoopFunctionTimer, NoopMeter;
import std.typecons : Nullable;

@safe:

private Meter.Id testId()
{
    return new Meter.Id("test", Tags.of("name", "value"), Nullable!string("ms"),
            Nullable!string(""), Meter.Type.TIMER);
}

@("returnsId")
unittest
{
    auto id = testId();
    NoopMeter meter = new NoopFunctionTimer(id);
    assert(meter.getId() is id);
}

@("returnsCountAsZero")
unittest
{
    auto meter = new NoopFunctionTimer(testId());
    FunctionTimer timer = meter;
    auto measurements = meter.measure();
    assert(measurements.isEmpty() && timer.measure() is measurements);

    const before = GC.stats().allocatedInCurrentThread;
    foreach (iteration; 0 .. 256)
        assert(timer.count() == 0.0 && timer.measure() is measurements);
    assert(GC.stats().allocatedInCurrentThread == before);
}

@("returnsTotalTimeAsZero")
unittest
{
    FunctionTimer timer = new NoopFunctionTimer(testId());
    assert(timer.totalTime(TimeUnit.NANOSECONDS) == 0.0);
    assert(timer.mean(TimeUnit.SECONDS) == 0.0);
}

@("returnsNanosAsTimeUnit")
unittest
{
    FunctionTimer timer = new NoopFunctionTimer(testId());
    assert(timer.baseTimeUnit() == TimeUnit.NANOSECONDS);
}

private final class SampleTimer : AbstractMeter, FunctionTimer
{
    double events = 0.0;
    double nanos = 0.0;
    TimeUnit baseUnit = TimeUnit.SECONDS;
    uint countReads;
    uint timeReads;
    uint unitReads;
    Exception failure;

    this()
    {
        super(testId());
    }

    override double count()
    {
        countReads++;
        return events;
    }

    override double totalTime(TimeUnit unit)
    {
        timeReads++;
        if (failure !is null)
            throw failure;
        return nanos / unit.toNanos(1);
    }

    override TimeUnit baseTimeUnit()
    {
        unitReads++;
        return baseUnit;
    }

    mixin FunctionTimer.Defaults;
}

@("function timer readings sample count, time, and the current base unit on demand")
unittest
{
    auto sample = new SampleTimer;
    FunctionTimer timer = sample;
    auto measurements = timer.measure();
    auto iterator = measurements.iterator();
    auto count = iterator.next();
    auto time = iterator.next();
    assert(count.getStatistic() == Statistic.COUNT && time.getStatistic() == Statistic.TOTAL_TIME);
    assert(!iterator.hasNext());
    uint visits;
    measurements.forEach((_) { visits++; });
    assert(visits == 2 && sample.countReads == 0 && sample.timeReads == 0 && sample.unitReads == 0);

    sample.events = 2.5;
    sample.nanos = 12_500_000_000.0;
    const before = GC.stats().allocatedInCurrentThread;
    assert(count.getValue() == 2.5 && time.getValue() == 12.5);
    sample.events = 5.0;
    sample.nanos = 15_000_000_000.0;
    sample.baseUnit = TimeUnit.MILLISECONDS;
    assert(count.getValue() == 5.0 && time.getValue() == 15_000.0);
    assert(timer.mean(TimeUnit.SECONDS) == 3.0);
    assert(GC.stats().allocatedInCurrentThread == before);
    assert(sample.countReads == 3 && sample.timeReads == 3 && sample.unitReads == 2);
}

@("zero count skips the total-time callback and a sampled failure escapes unchanged")
unittest
{
    auto sample = new SampleTimer;
    FunctionTimer timer = sample;
    auto failure = new Exception("total time");
    sample.failure = failure;
    assert(timer.mean(TimeUnit.SECONDS) == 0.0);
    assert(sample.countReads == 1 && sample.timeReads == 0 && sample.unitReads == 0);

    auto readings = timer.measure().iterator();
    readings.next();
    try
    {
        readings.next().getValue();
        assert(0, "the timer's exception should escape the measurement");
    }
    catch (Exception error)
    {
        assert(error is failure);
    }
}
