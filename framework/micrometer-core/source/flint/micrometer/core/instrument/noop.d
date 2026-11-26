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
// Ported from micrometer-core 1.18.0: micrometer-core/src/main/java/io/micrometer/core/instrument/noop/NoopMeter.java
// Ported from micrometer-core 1.18.0: micrometer-core/src/main/java/io/micrometer/core/instrument/noop/NoopGauge.java
// Ported from micrometer-core 1.18.0: micrometer-core/src/main/java/io/micrometer/core/instrument/noop/NoopCounter.java
// Modified by the Flint authors.
module flint.micrometer.core.instrument.noop;

import flint.java.util : Collections, List;
import flint.micrometer.core.instrument : AbstractMeter, Counter, Gauge, Measurement, Meter;

@safe:

/// A meter that keeps its registered ID and has no measurements.
class NoopMeter : AbstractMeter
{
    /// Retain the ID of the disabled meter.
    this(Meter.Id id)
    {
        super(id);
    }

    override List!Measurement measure()
    {
        return Collections.emptyList!Measurement();
    }
}

/// A disabled counter whose count is zero.
class NoopCounter : NoopMeter, Counter
{
    /// Retain the ID of the disabled counter.
    this(Meter.Id id)
    {
        super(id);
    }

    override void increment() nothrow @nogc
    {
        increment(1.0);
    }

    override void increment(double) nothrow @nogc
    {
    }

    override double count() nothrow @nogc
    {
        return 0.0;
    }
}

/// A disabled gauge whose value is zero.
class NoopGauge : NoopMeter, Gauge
{
    /// Retain the ID of the disabled gauge.
    this(Meter.Id id)
    {
        super(id);
    }

    override double value()
    {
        return 0.0;
    }
}
