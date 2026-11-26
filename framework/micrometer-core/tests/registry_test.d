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
import flint.micrometer.core.instrument : Meter, MeterRegistry, Tags;
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
