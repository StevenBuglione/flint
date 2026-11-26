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
// Ported from micrometer-core 1.18.0: micrometer-core/src/test/java/io/micrometer/core/instrument/MeterRegistryTest.java
// Modified by the Flint authors.
module micrometer_registry_test;

import core.memory : GC;
import core.thread : Thread;
import flint.java.lang : ArithmeticException, IllegalArgumentException;
import flint.java.time : Duration;
import flint.java.util.concurrent : TimeUnit;
import flint.micrometer.core.instrument : Meter, MeterRegistry, Statistic, Tags;
import flint.micrometer.core.instrument.simple : SimpleMeterRegistry;

@safe:

private int meterCount(MeterRegistry registry)
{
    int count;
    registry.forEachMeter((Meter _) { ++count; });
    return count;
}

@("clear")
unittest
{
    auto registry = new SimpleMeterRegistry;
    registry.counter("my.counter");
    registry.counter("my.counter2");
    assert(meterCount(registry) == 2);
    registry.clear();
    assert(meterCount(registry) == 0);
}

@("removeMeters")
unittest
{
    auto registry = new SimpleMeterRegistry;
    auto counter = registry.counter("my.counter");
    assert(meterCount(registry) == 1);
    assert(registry.remove(counter) is counter);
    assert(meterCount(registry) == 0);
    assert(registry.remove(counter) is null);
}

@("closing the registry keeps current counters and returns no-op counters for new identities")
unittest
{
    auto registry = new SimpleMeterRegistry;
    auto before = registry.counter("my.counter.before");
    before.increment();
    before.increment();
    registry.close();

    assert(registry.isClosed());
    assert(registry.counter("my.counter.before") is before);
    auto after = registry.counter("my.counter.after");
    after.increment(2);
    assert(before.count() == 2);
    assert(after.count() == 0);
    assert(meterCount(registry) == 1);
}

@("counter registration uses normalized name and tags")
unittest
{
    auto registry = new SimpleMeterRegistry;
    auto a = registry.counter("test.counter", "region", "west", "method", "GET");
    auto same = registry.counter("test.counter", Tags.of("method", "GET", "region", "west"));
    auto different = registry.counter("test.counter", "region", "east", "method", "GET");
    assert(a is same);
    assert(a !is different);
    a.increment(0.25);
    same.increment(0.5);
    assert(a.count() == 0.75);
    assert(different.count() == 0);
}

@("no-op meters publish no measurements")
unittest
{
    auto registry = new SimpleMeterRegistry;
    registry.close();
    Meter[3] meters = [
        registry.counter("counter"), registry.timer("timer"), registry.summary("summary")
    ];
    const empty = meters[0].measure();
    foreach (meter; meters)
    {
        const before = GC.stats().allocatedInCurrentThread;
        auto reported = meter.measure();
        assert(GC.stats().allocatedInCurrentThread == before);
        assert(reported is empty && !reported.iterator().hasNext());
        reported.forEach((_) { assert(0, "a no-op meter published a measurement"); });
        foreach (_; reported)
            assert(0, "a no-op meter published a measurement");
    }
}

@("shouldNotLetRegisteringMetersTwice")
unittest
{
    auto registry = new SimpleMeterRegistry;
    registry.counter("my.dupe.meter");
    bool rejected;
    try
        registry.timer("my.dupe.meter");
    catch (IllegalArgumentException exception)
    {
        assert(exception.msg == "There is already a registered meter of a different type "
                ~ "(CumulativeCounter vs. Timer) with the same name: my.dupe.meter");
        rejected = true;
    }
    assert(rejected);

    auto timer = registry.timer("my.dupe.meter", "region", "east");
    assert(registry.timer("my.dupe.meter", Tags.of("region", "east")) is timer);
    rejected = false;
    try
        registry.counter("my.dupe.meter", "region", "east");
    catch (IllegalArgumentException exception)
    {
        assert(exception.msg == "There is already a registered meter of a different type "
                ~ "(CumulativeTimer vs. Counter) with the same name: my.dupe.meter");
        rejected = true;
    }
    assert(rejected);
    assert(meterCount(registry) == 2);
}

@("noopMetersAfterRegistryClosed")
unittest
{
    auto registry = new SimpleMeterRegistry;
    auto admitted = registry.timer("my.timer.before");
    admitted.record(1, TimeUnit.SECONDS);
    registry.close();
    assert(registry.isClosed());
    assert(registry.timer("my.timer.before") is admitted);
    auto denied = registry.timer("my.timer.after");
    denied.record(2, TimeUnit.SECONDS);
    admitted.record(3, TimeUnit.SECONDS);
    assert(denied.getId().getName() == "my.timer.after");
    assert(denied.count() == 0 && denied.totalTime(TimeUnit.SECONDS) == 0 && denied.max(TimeUnit.SECONDS) == 0);
    assert(denied.baseTimeUnit() == TimeUnit.SECONDS);
    assert(!denied.measure().iterator().hasNext());
    assert(admitted.count() == 2 && admitted.totalTime(TimeUnit.SECONDS) == 4 && admitted.max(TimeUnit.SECONDS) == 3);
    assert(meterCount(registry) == 1);
}

@("baseUnitStringShouldBeCachedAndReturnTheSameInstance")
unittest
{
    auto registry = new SimpleMeterRegistry;
    auto first = registry.timer("test.timer1");
    auto second = registry.timer("test.timer2");
    assert(first.baseTimeUnit() == TimeUnit.SECONDS);
    const firstUnit = first.getId().getBaseUnit().get();
    const secondUnit = second.getId().getBaseUnit().get();
    assert(firstUnit == "seconds" && firstUnit is secondUnit);
}

@("timer measurement values stay live and use the registry base unit")
unittest
{
    auto timer = (new SimpleMeterRegistry).timer("latency");
    assert(timer.mean(TimeUnit.SECONDS) == 0);
    auto view = timer.measure();
    auto measurements = view.iterator();
    auto count = measurements.next();
    auto total = measurements.next();
    auto maximum = measurements.next();
    assert(!measurements.hasNext());
    assert(count.getStatistic() == Statistic.COUNT);
    assert(total.getStatistic() == Statistic.TOTAL_TIME);
    assert(maximum.getStatistic() == Statistic.MAX);
    size_t index;
    view.forEach((reading) { assert(reading is [count, total, maximum][index++]); });
    assert(index == 3);
    foreach (reading; view)
    {
        assert(reading is count);
        break;
    }
    timer.record(-1, TimeUnit.SECONDS);
    timer.record(Duration.ofMillis(-1));
    assert(count.getValue() == 0);
    timer.record(Duration.ofMillis(250));
    timer.record(1, TimeUnit.SECONDS);
    timer.record(0, TimeUnit.SECONDS);
    assert(count.getValue() == 3 && total.getValue() == 1.25 && maximum.getValue() == 1);
    assert(timer.mean(TimeUnit.MILLISECONDS) == 1250.0 / 3);
    bool overflow;
    try
        timer.record(Duration.ofSeconds(long.max));
    catch (ArithmeticException)
        overflow = true;
    assert(overflow && count.getValue() == 3);
}

@("preallocated timers record concurrently without request-thread allocations")
@system unittest
{
    auto timer = (new SimpleMeterRegistry).timer("parallel.latency");
    enum threadCount = 4, updates = 10_000;
    Thread[threadCount] workers;
    foreach (ref worker; workers)
    {
        worker = new Thread(() {
            const allocatedBefore = GC.stats().allocatedInCurrentThread;
            foreach (_; 0 .. updates)
                timer.record(500, TimeUnit.MICROSECONDS);
            assert(GC.stats().allocatedInCurrentThread == allocatedBefore);
        });
        worker.start();
    }
    foreach (worker; workers)
        worker.join();
    assert(timer.count() == threadCount * updates);
    assert(timer.totalTime(TimeUnit.SECONDS) == 20);
    assert(timer.max(TimeUnit.MILLISECONDS) == 0.5);
}

@("preallocated counters update concurrently with no request-thread allocations")
@system unittest
{
    auto registry = new SimpleMeterRegistry;
    auto counter = registry.counter("test.parallel");
    enum threadCount = 4, updates = 10_000;
    Thread[threadCount] workers;
    foreach (ref worker; workers)
    {
        worker = new Thread(() {
            const allocatedBefore = GC.stats().allocatedInCurrentThread;
            foreach (_; 0 .. updates)
                counter.increment(0.5);
            assert(GC.stats().allocatedInCurrentThread == allocatedBefore);
        });
        worker.start();
    }
    foreach (worker; workers)
        worker.join();
    assert(counter.count() == threadCount * updates * 0.5);
}

@("meter iteration sees a stable snapshot when callbacks remove entries")
unittest
{
    auto registry = new SimpleMeterRegistry;
    registry.counter("first");
    registry.counter("second");
    int visited;
    registry.forEachMeter((Meter meter) { assert(registry.remove(meter) is meter); ++visited; });
    assert(visited == 2);
    assert(meterCount(registry) == 0);
}
