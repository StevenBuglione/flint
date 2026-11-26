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
// Ported from micrometer-core 1.18.0: micrometer-core/src/main/java/io/micrometer/core/instrument/noop/NoopDistributionSummary.java
// Ported from micrometer-core 1.18.0: micrometer-core/src/main/java/io/micrometer/core/instrument/noop/NoopFunctionCounter.java
// Ported from micrometer-core 1.18.0: micrometer-core/src/main/java/io/micrometer/core/instrument/noop/NoopFunctionTimer.java
// Ported from micrometer-core 1.18.0: micrometer-core/src/main/java/io/micrometer/core/instrument/noop/NoopTimer.java
// Ported from micrometer-core 1.18.0: micrometer-core/src/main/java/io/micrometer/core/instrument/noop/NoopTimeGauge.java
// Modified by the Flint authors.
module flint.micrometer.core.instrument.noop;

import flint.java.util : Collections, List;
import flint.java.util.concurrent : TimeUnit;
import flint.micrometer.core.instrument : AbstractMeter, Counter, DistributionSummary,
    FunctionCounter, FunctionTimer, Gauge, Measurement, Meter, TimeGauge, Timer;
import flint.micrometer.core.instrument.distribution : HistogramSnapshot;

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

/// A disabled distribution summary with empty statistics.
class NoopDistributionSummary : NoopMeter, DistributionSummary
{
    /// Retain the ID of the disabled summary.
    this(Meter.Id id)
    {
        super(id);
    }

    override void record(double) nothrow @nogc
    {
    }

    override long count() nothrow @nogc
    {
        return 0;
    }

    override double totalAmount() nothrow @nogc
    {
        return 0.0;
    }

    override double max() nothrow @nogc
    {
        return 0.0;
    }

    override HistogramSnapshot takeSnapshot()
    {
        return HistogramSnapshot.empty(0, 0, 0);
    }

    mixin DistributionSummary.StatisticsDefaults;
}

/// A disabled timer that executes callbacks and keeps no timing statistics.
class NoopTimer : NoopMeter, Timer
{
    alias record = Timer.record;
    alias takeSnapshot = Timer.takeSnapshot;
    alias wrap = Timer.wrap;

    /// Retain the ID of the disabled timer.
    this(Meter.Id id)
    {
        super(id);
    }

    override void record(long, TimeUnit) nothrow @nogc
    {
    }

    // Keep the concrete Java overloads virtual and seal the D-only dispatch adapters.
    final override void record(scope void delegate() @safe action)
    {
        invoke(action);
    }

    final override bool record(scope bool delegate() @safe action)
    {
        return invoke(action);
    }

    final override double record(scope double delegate() @safe action)
    {
        return invoke(action);
    }

    private static T invoke(T)(scope T delegate() @safe action)
    {
        if (action is null)
            throw Timer.nullCallback();
        return action();
    }

    override long count() nothrow @nogc
    {
        return 0;
    }

    override double totalTime(TimeUnit) nothrow @nogc
    {
        return 0.0;
    }

    override double max(TimeUnit) nothrow @nogc
    {
        return 0.0;
    }

    override TimeUnit baseTimeUnit() nothrow @nogc
    {
        return TimeUnit.SECONDS;
    }

    override HistogramSnapshot takeSnapshot()
    {
        return HistogramSnapshot.empty(0, 0, 0);
    }

    mixin Timer.CallbackDefaults;
}

/// A disabled function counter whose count is zero.
class NoopFunctionCounter : NoopMeter, FunctionCounter
{
    /// Retain the ID of the disabled function counter.
    this(Meter.Id id)
    {
        super(id);
    }

    override double count()
    {
        return 0.0;
    }
}

/// A disabled function timer with no observations.
class NoopFunctionTimer : NoopMeter, FunctionTimer
{
    /// Retain the ID of the disabled function timer.
    this(Meter.Id id)
    {
        super(id);
    }

    override double count()
    {
        return 0.0;
    }

    override double totalTime(TimeUnit)
    {
        return 0.0;
    }

    override double mean(TimeUnit unit)
    {
        return FunctionTimer.meanOf(this, unit);
    }

    override TimeUnit baseTimeUnit()
    {
        return TimeUnit.NANOSECONDS;
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

/// A disabled time gauge that reads as zero nanoseconds.
class NoopTimeGauge : NoopMeter, TimeGauge
{
    alias value = timeGaugeDefaults.value;

    /// Retain the ID of the disabled time gauge.
    this(Meter.Id id)
    {
        super(id);
    }

    override TimeUnit baseTimeUnit()
    {
        return TimeUnit.NANOSECONDS;
    }

    override double value()
    {
        return 0.0;
    }

    mixin TimeGauge.Defaults timeGaugeDefaults;
}
