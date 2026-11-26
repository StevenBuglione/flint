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
// Ported from micrometer-core 1.18.0: micrometer-core/src/test/java/io/micrometer/core/instrument/noop/NoopTimeGaugeTest.java
// Modified by the Flint authors.
module micrometer_noop_time_gauge_test;

import core.memory : GC;
import flint.java.util : List;
import flint.java.util.concurrent : TimeUnit;
import flint.micrometer.core.instrument : Measurement, Meter, Tags, TimeGauge;
import flint.micrometer.core.instrument.noop : NoopMeter, NoopTimeGauge;
import std.typecons : Nullable;

@safe:

private Meter.Id testId()
{
    return new Meter.Id("test", Tags.of("name", "value"), Nullable!string(""),
            Nullable!string(""), Meter.Type.GAUGE);
}

@("returnsId")
unittest
{
    auto id = testId();
    NoopMeter gauge = new NoopTimeGauge(id);
    assert(gauge.getId() is id);
}

@("returnsValueAsZero")
unittest
{
    auto gauge = new NoopTimeGauge(testId());
    assert(gauge.value() == 0.0);
}

@("returnsBaseTimeUnit")
unittest
{
    auto gauge = new NoopTimeGauge(testId());
    assert(gauge.baseTimeUnit() == TimeUnit.NANOSECONDS);
}

@("a public no-op time gauge shares empty measurements and allocates nothing on read")
unittest
{
    auto gauge = new NoopTimeGauge(testId());
    TimeGauge meter = gauge;
    List!Measurement empty = gauge.measure();
    assert(empty.isEmpty());
    assert(gauge.value(TimeUnit.SECONDS) == 0.0);
    const before = GC.stats().allocatedInCurrentThread;
    foreach (iteration; 0 .. 256)
    {
        assert(meter.value() == 0.0);
        assert(meter.value(TimeUnit.MILLISECONDS) == 0.0);
        assert(meter.measure() is empty);
    }
    assert(GC.stats().allocatedInCurrentThread == before);
}
