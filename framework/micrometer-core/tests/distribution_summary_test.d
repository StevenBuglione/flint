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
import flint.java.lang : ArithmeticException, IllegalArgumentException, Iterable, NullPointerException;
import flint.java.time : Duration;
import flint.micrometer.core.instrument : Counter, DistributionSummary, Measurement, Meter, Statistic, Tag, Tags;
import flint.micrometer.core.instrument.config : InvalidConfigurationException;
import flint.micrometer.core.instrument.distribution : HistogramSnapshot;
import flint.micrometer.core.instrument.simple : SimpleMeterRegistry;
import std.exception : assertThrown;
import std.typecons : Nullable;

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

@("summary builder preserves the first metadata and scale for a registered identity")
unittest
{
    auto registry = new SimpleMeterRegistry;
    Iterable!Tag tags = Tags.of("region", "east", "response", "ok");
    auto builder = DistributionSummary.builder("response.size");
    assertThrown!NullPointerException(builder.register(null));
    auto summary = builder.tags("region", "west").tags(tags).tag("region", "north")
        .description(Nullable!string("Response size")).baseUnit(Nullable!string("bytes")).scale(2).register(registry);

    const duplicate = DistributionSummary.builder("response.size").tags("region", "north",
            "response", "ok").description(Nullable!string("Discard this")).scale(10).register(registry);
    assert(duplicate is summary);
    assert(registry.summary("response.size", "region", "north", "response", "ok") is summary);
    assert(summary.getId().getDescription().get() == "Response size");
    assert(summary.getId().getBaseUnit().get() == "bytes");

    auto direct = registry.summary("direct");
    assert(DistributionSummary.builder("direct").scale(10).register(registry) is direct);
    direct.record(2);
    assert(direct.totalAmount() == 2);

    summary.record(1.5);
    assert(summary.count() == 1 && summary.totalAmount() == 3 && summary.max() == 3);
    registry.close();
    assert(builder.register(registry) is summary);

    auto fresh = builder.tag("region", "south").description(Nullable!string.init)
        .baseUnit(Nullable!string.init).register(registry);
    fresh.record(1.5);
    assert(fresh.getId().getDescription().isNull && fresh.getId().getBaseUnit().isNull);
    assert(fresh.count() == 0 && fresh.totalAmount() == 0 && fresh.max() == 0);
}

// The scaling case follows MeterRegistryCompatibilityKit.DistributionSummaryTck.scale from micrometer-test 1.18.0.
@("the summary scale applies after rejecting negative and NaN amounts without allocating")
@system unittest
{
    auto registry = new SimpleMeterRegistry;
    auto scaled = DistributionSummary.builder("scaled").scale(0.5).register(registry);
    auto negative = DistributionSummary.builder("negative.scale").scale(-2).register(registry);
    auto nan = DistributionSummary.builder("nan.scale").scale(double.nan).register(registry);

    const before = GC.stats().allocatedInCurrentThread;
    scaled.record(5.5);
    scaled.record(-1);
    scaled.record(double.nan);
    negative.record(2.5);
    negative.record(-1);
    nan.record(1);
    nan.record(2);
    assert(GC.stats().allocatedInCurrentThread == before);
    assert(scaled.count() == 1 && scaled.totalAmount() == 2.75 && scaled.max() == 2.75);
    assert(negative.count() == 1 && negative.totalAmount() == -5 && negative.max() == 0);
    const nanTotal = nan.totalAmount();
    const nanMax = nan.max();
    assert(nan.count() == 2 && nanTotal != nanTotal && nanMax != nanMax);
}

@("summary builder validates configured expiration and buffer length on the registry path")
unittest
{
    auto registry = new SimpleMeterRegistry;
    auto builder = DistributionSummary.builder("response.size").distributionStatisticBufferLength(0);
    assertThrown!InvalidConfigurationException(builder.register(registry));
    builder.distributionStatisticBufferLength(2).distributionStatisticExpiry(Duration.ofNanos(1));
    assertThrown!IllegalArgumentException(builder.register(registry));

    auto summary = builder.distributionStatisticExpiry(Duration.ofHours(1)).register(registry);
    summary.record(2);
    assert(summary.max() == 2 && summary.totalAmount() == 2 && summary.count() == 1);
    assert(builder.distributionStatisticExpiry(Duration.ofNanos(1)).register(registry) is summary);
    assertThrown!InvalidConfigurationException(builder.distributionStatisticBufferLength(0).register(registry));

    auto reset = DistributionSummary.builder("response.reset").distributionStatisticExpiry(Duration.ofNanos(1))
        .distributionStatisticExpiry(Nullable!Duration.init)
        .distributionStatisticBufferLength(0).distributionStatisticBufferLength(Nullable!int.init).register(registry);
    reset.record(3);
    assert(reset.max() == 3);

    registry.close();
    auto closed = DistributionSummary.builder("closed").distributionStatisticExpiry(Duration.ofNanos(1));
    assert(closed.register(registry).count() == 0);
    assertThrown!InvalidConfigurationException(closed.distributionStatisticBufferLength(0).register(registry));
}

@("summary registration distinguishes invalid windows from signed expiry overflow")
unittest
{
    auto registry = new SimpleMeterRegistry;
    auto builder = DistributionSummary.builder("response.expiry");
    assertThrown!IllegalArgumentException(builder.distributionStatisticExpiry(
            Duration.ofSeconds(-9_223_372_036_854_776L, 191_000_001)).register(registry));
    assertThrown!ArithmeticException(builder.distributionStatisticExpiry(
            Duration.ofSeconds(-9_223_372_036_854_776L, 191_000_000)).register(registry));
    assertThrown!ArithmeticException(builder.distributionStatisticExpiry(
            Duration.ofSeconds(9_223_372_036_854_775L, 808_000_000)).register(registry));

    auto summary = builder.distributionStatisticExpiry(Duration.ofMillis(long.max)).register(registry);
    summary.record(2.0);
    assert(summary.count() == 1 && summary.max() == 2.0);
}
