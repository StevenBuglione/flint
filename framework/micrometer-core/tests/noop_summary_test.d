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
// Ported from micrometer-core 1.18.0: micrometer-core/src/test/java/io/micrometer/core/instrument/noop/NoopDistributionSummaryTest.java
// Modified by the Flint authors.
module micrometer_noop_summary_test;

import core.memory : GC;
import flint.micrometer.core.instrument : DistributionSummary, Meter, Tags;
import flint.micrometer.core.instrument.distribution : HistogramSnapshot, HistogramSupport;
import flint.micrometer.core.instrument.noop : NoopDistributionSummary, NoopMeter;
import std.typecons : Nullable;

@safe:

private Meter.Id testId()
{
    return new Meter.Id("test", Tags.of("name", "value"), Nullable!string("ms"),
            Nullable!string(""), Meter.Type.DISTRIBUTION_SUMMARY);
}

@("returnsId")
unittest
{
    auto id = testId();
    NoopMeter meter = new NoopDistributionSummary(id);
    assert(meter.getId() is id);
}

@("returnsCountAsZero")
unittest
{
    auto meter = new NoopDistributionSummary(testId());
    assert(meter.count() == 0);
}

@("returnsTotalAmountAsZero")
unittest
{
    auto meter = new NoopDistributionSummary(testId());
    assert(meter.totalAmount() == 0.0);
}

@("returnsMaxAsZero")
unittest
{
    auto meter = new NoopDistributionSummary(testId());
    assert(meter.max() == 0.0);
}

@("returnsEmptySnapshot")
unittest
{
    auto meter = new NoopDistributionSummary(testId());
    auto snapshot = meter.takeSnapshot();
    auto expected = HistogramSnapshot.empty(0, 0, 0);
    assert(snapshot.count() == expected.count());
    assert(snapshot.total() == expected.total());
    assert(snapshot.max() == expected.max());
    assert(snapshot.percentileValues().length == 0 && snapshot.histogramCounts().length == 0);
}

@("the disabled summary shares empty measurements and discards records without allocating")
unittest
{
    auto meter = new NoopDistributionSummary(testId());
    DistributionSummary summary = meter;
    auto measurements = meter.measure();
    assert(measurements.isEmpty());

    const before = GC.stats().allocatedInCurrentThread;
    foreach (iteration; 0 .. 256)
    {
        summary.record(2.5);
        assert(summary.count() == 0 && summary.totalAmount() == 0.0 && summary.max() == 0.0);
        assert(summary.mean() == 0.0 && summary.measure() is measurements);
    }
    assert(GC.stats().allocatedInCurrentThread == before);
}

private final class SummaryOverride : NoopDistributionSummary
{
    this()
    {
        super(testId());
    }

    override long count() nothrow @nogc
    {
        return 2;
    }

    override double totalAmount() nothrow @nogc
    {
        return 7.0;
    }

    override HistogramSnapshot takeSnapshot()
    {
        return HistogramSnapshot.empty(count(), totalAmount(), 3.5);
    }
}

@("summary and legacy snapshot defaults dispatch through subclass overrides")
unittest
{
    DistributionSummary summary = new SummaryOverride;
    assert(summary.mean() == 3.5);
    HistogramSupport histogram = summary;
    auto snapshot = histogram.takeSnapshot(true);
    assert(snapshot.count() == 2 && snapshot.total() == 7.0 && snapshot.max() == 3.5);
}
