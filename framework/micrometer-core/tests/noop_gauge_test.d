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
// Ported from micrometer-core 1.18.0: micrometer-core/src/test/java/io/micrometer/core/instrument/noop/NoopGaugeTest.java
// Modified by the Flint authors.
module micrometer_noop_gauge_test;

import flint.micrometer.core.instrument : Gauge, Meter, Tags;
import flint.micrometer.core.instrument.noop : NoopGauge, NoopMeter;
import std.typecons : Nullable;

@safe:

private Meter.Id testId()
{
    return new Meter.Id("test", Tags.of("name", "value"), Nullable!string("entries"),
            Nullable!string(""), Meter.Type.GAUGE);
}

@("returnsId")
unittest
{
    auto id = testId();
    NoopMeter meter = new NoopGauge(id);
    assert(meter.getId() is id);
}

@("returnsValueAsZero")
unittest
{
    auto gauge = new NoopGauge(testId());
    Gauge asGauge = gauge;
    assert(asGauge.value() == 0.0);
    assert(asGauge.measure() is gauge.measure());
}
