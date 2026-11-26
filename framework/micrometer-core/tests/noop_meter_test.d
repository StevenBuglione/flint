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
// Ported from micrometer-core 1.18.0: micrometer-core/src/test/java/io/micrometer/core/instrument/noop/NoopMeterTest.java
// Modified by the Flint authors.
module micrometer_noop_meter_test;

import core.memory : GC;
import flint.java.lang : UnsupportedOperationException;
import flint.java.util : Collections, List;
import flint.micrometer.core.instrument : AbstractMeter, Measurement, Meter, Tags;
import flint.micrometer.core.instrument.noop : NoopMeter;
import std.exception : assertThrown;
import std.typecons : Nullable;

@safe:

private Meter.Id testId()
{
    return new Meter.Id("test", Tags.of("name", "value"), Nullable!string(""),
            Nullable!string(""), Meter.Type.OTHER);
}

@("returnsId")
unittest
{
    auto id = testId();
    AbstractMeter meter = new NoopMeter(id);
    assert(meter.getId() is id);
}

@("returnsMeasureAsEmptyList")
unittest
{
    auto meter = new NoopMeter(testId());
    List!Measurement measurements = meter.measure();
    assert(measurements.isEmpty());
    assert(measurements is Collections.emptyList!Measurement());
    assertThrown!UnsupportedOperationException(measurements.add(cast(Measurement) null));

    Meter asMeter = meter;
    const before = GC.stats().allocatedInCurrentThread;
    assert(asMeter.measure() is measurements);
    assert(meter.measure() is measurements);
    assert(GC.stats().allocatedInCurrentThread == before);
}
