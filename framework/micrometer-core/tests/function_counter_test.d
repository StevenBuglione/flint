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
// Ported from micrometer-core 1.18.0: micrometer-core/src/test/java/io/micrometer/core/instrument/noop/NoopFunctionCounterTest.java
// Modified by the Flint authors.
module micrometer_function_counter_test;

import core.memory : GC;
import flint.micrometer.core.instrument : AbstractMeter, FunctionCounter, Measurement, Meter, Statistic, Tags;
import flint.micrometer.core.instrument.noop : NoopFunctionCounter, NoopMeter;
import std.typecons : Nullable;

@safe:

private Meter.Id testId()
{
    return new Meter.Id("test", Tags.of("name", "value"), Nullable!string("entries"),
            Nullable!string(""), Meter.Type.COUNTER);
}

@("returnsId")
unittest
{
    auto id = testId();
    NoopMeter meter = new NoopFunctionCounter(id);
    assert(meter.getId() is id);
}

@("returnsCountAsZero")
unittest
{
    auto meter = new NoopFunctionCounter(testId());
    FunctionCounter counter = meter;
    auto measurements = meter.measure();
    assert(measurements.isEmpty());
    assert(counter.measure() is measurements);

    const before = GC.stats().allocatedInCurrentThread;
    foreach (iteration; 0 .. 256)
        assert(counter.count() == 0.0 && counter.measure() is measurements);
    assert(GC.stats().allocatedInCurrentThread == before);
}

private final class SampleCounter : AbstractMeter, FunctionCounter
{
    double amount = 0.0;
    uint reads;
    Exception failure;

    this()
    {
        super(testId());
    }

    override double count()
    {
        reads++;
        if (failure !is null)
            throw failure;
        return amount;
    }

    mixin FunctionCounter.Defaults;
}

@("a function counter samples its single count reading only when requested")
unittest
{
    auto sample = new SampleCounter;
    FunctionCounter counter = sample;
    auto measurements = counter.measure();
    auto iterator = measurements.iterator();
    assert(iterator.hasNext());
    auto reading = iterator.next();
    assert(!iterator.hasNext());
    assert(reading.getStatistic() == Statistic.COUNT);

    uint visits;
    measurements.forEach((Measurement entry) { assert(entry is reading); visits++; });
    assert(visits == 1 && sample.reads == 0);

    sample.amount = 2.5;
    const before = GC.stats().allocatedInCurrentThread;
    assert(reading.getValue() == 2.5);
    sample.amount = 7.0;
    assert(reading.getValue() == 7.0);
    assert(GC.stats().allocatedInCurrentThread == before && sample.reads == 2);

    auto failure = new Exception("count");
    sample.failure = failure;
    try
    {
        reading.getValue();
        assert(0, "the counter's exception should escape the measurement");
    }
    catch (Exception error)
    {
        assert(error is failure);
    }
}
