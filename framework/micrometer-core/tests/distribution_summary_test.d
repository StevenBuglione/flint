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
module micrometer_distribution_summary_test;

import core.memory : GC;
import core.thread : Thread;
import flint.java.lang : IllegalArgumentException, Iterable;
import flint.micrometer.core.instrument : Counter, DistributionSummary, Measurement, Meter, Statistic, Tag, Tags;
import flint.micrometer.core.instrument.distribution : HistogramSnapshot;
import flint.micrometer.core.instrument.simple : SimpleMeterRegistry;
import std.exception : assertThrown;

@safe:

private DistributionSummary closedSummary()
{
    auto registry = new SimpleMeterRegistry;
    registry.close();
    return registry.summary("test", "name", "value");
}

@("returnsCountAsZero")
unittest
{
    auto summary = closedSummary();
    summary.record(1.25);
    assert(summary.count() == 0);
}

@("returnsTotalAmountAsZero")
unittest
{
    assert(closedSummary().totalAmount() == 0.0);
}

@("returnsMaxAsZero")
unittest
{
    assert(closedSummary().max() == 0.0);
}

@("returnsEmptySnapshot")
unittest
{
    auto summary = closedSummary();
    auto expected = HistogramSnapshot.empty(0, 0.0, 0.0);
    auto actual = summary.takeSnapshot();
    assert(actual.count() == expected.count());
    assert(actual.total() == expected.total());
    assert(actual.max() == expected.max());
    assert(actual.histogramCounts().length == 0 && actual.percentileValues().length == 0);
    assert(!summary.measure().iterator().hasNext());
}

@("summary registrations share identity and reject other meter kinds")
unittest
{
    auto registry = new SimpleMeterRegistry;
    auto summary = registry.summary("response.size", "method", "GET");
    Iterable!Tag tags = Tags.of("method", "GET");
    assert(registry.summary("response.size", tags) is summary);
    assert(summary.getId().getType() == Meter.Type.DISTRIBUTION_SUMMARY);
    assertThrown!IllegalArgumentException(registry.timer("response.size", "method", "GET"));
    assertThrown!IllegalArgumentException(registry.counter("response.size", "method", "GET"));
    registry.timer("latency");
    assertThrown!IllegalArgumentException(registry.summary("latency"));

    registry.close();
    assert(registry.summary("response.size", tags) is summary);
    summary.record(2.25);
    assert(summary.count() == 1 && summary.totalAmount() == 2.25 && summary.max() == 2.25);
    assert(registry.summary("fresh").count() == 0);
}

@("a summary records fractional values and publishes live measurements")
unittest
{
    auto registry = new SimpleMeterRegistry;
    auto summary = registry.summary("sizes");
    assert(summary.mean() == 0.0);
    auto readings = summary.measure().iterator();

    summary.record(0.25);
    summary.record(-2.0);
    summary.record(double.nan);
    summary.record(2.5);

    assert(summary.count() == 2 && summary.totalAmount() == 2.75 && summary.mean() == 1.375);
    assert(summary.max() == 2.5);
    auto snapshot = summary.takeSnapshot();
    assert(snapshot.count() == 2 && snapshot.total() == 2.75 && snapshot.max() == 2.5);
    foreach (i, statistic; [Statistic.COUNT, Statistic.TOTAL, Statistic.MAX])
    {
        Measurement reading = readings.next();
        assert(reading.getStatistic() == statistic);
        assert(reading.getValue() == [2.0, 2.75, 2.5][i]);
    }
    assert(!readings.hasNext());
}

@("recording remains live after a positive infinite sample")
unittest
{
    auto summary = (new SimpleMeterRegistry).summary("sizes");
    summary.record(-0.0);
    summary.record(-double.infinity);
    assert(summary.count() == 1 && summary.totalAmount() == 0.0);
    summary.record(double.infinity);
    summary.record(1.25);
    assert(summary.count() == 3);
    assert(summary.totalAmount() == double.infinity && summary.max() == double.infinity);
}

@("a counter accepted before a factory reenters close stays registered")
unittest
{
    static final class ClosingRegistry : SimpleMeterRegistry
    {
        protected override Counter newCounter(Meter.Id id)
        {
            close();
            return super.newCounter(id);
        }
    }

    auto registry = new ClosingRegistry;
    auto counter = registry.counter("reentrant");
    assert(registry.isClosed() && registry.counter("reentrant") is counter);
}

@("concurrent fractional recording does not allocate")
@system unittest
{
    auto registry = new SimpleMeterRegistry;
    auto summary = registry.summary("sizes");
    enum threadCount = 4, samples = 10_000;
    Thread[threadCount] threads;
    foreach (ref thread; threads)
    {
        thread = new Thread(() {
            const before = GC.stats().allocatedInCurrentThread;
            foreach (_; 0 .. samples)
                summary.record(1.25);
            assert(GC.stats().allocatedInCurrentThread == before);
        });
        thread.start();
    }
    foreach (thread; threads)
        thread.join();
    assert(summary.count() == threads.length * samples && summary.totalAmount() == threads.length * samples * 1.25);
    assert(summary.max() == 1.25);
}
