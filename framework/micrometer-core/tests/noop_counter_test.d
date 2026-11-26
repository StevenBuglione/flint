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
// Ported from micrometer-core 1.18.0: micrometer-core/src/test/java/io/micrometer/core/instrument/noop/NoopCounterTest.java
// Modified by the Flint authors.
module micrometer_noop_counter_test;

import core.memory : GC;
import flint.micrometer.core.instrument : Counter, Meter, Tags;
import flint.micrometer.core.instrument.noop : NoopCounter, NoopMeter;
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
    NoopMeter meter = new NoopCounter(id);
    assert(meter.getId() is id);
}

@("returnsCountAsZero")
unittest
{
    auto counter = new NoopCounter(testId());
    Counter meter = counter;
    assert(meter.count() == 0.0);
    assert(counter.measure().isEmpty());
    assert(meter.measure() is counter.measure());

    const before = GC.stats().allocatedInCurrentThread;
    foreach (iteration; 0 .. 256)
    {
        meter.increment();
        meter.increment(2.5);
        assert(meter.count() == 0.0);
    }
    assert(GC.stats().allocatedInCurrentThread == before);
}

private final class RecordingCounter : NoopCounter
{
    private double lastAmount;

    this()
    {
        super(testId());
    }

    override void increment(double amount) nothrow @nogc
    {
        lastAmount = amount;
    }
}

@("the default increment calls the virtual amount overload")
unittest
{
    auto counter = new RecordingCounter;
    Counter meter = counter;
    meter.increment();
    assert(counter.lastAmount == 1.0);
}
