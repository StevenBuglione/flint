/*
 * Copyright 2022 VMware, Inc.
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
// Ported from micrometer-core 1.18.0: micrometer-core/src/test/java/io/micrometer/core/instrument/MissingHdrHistogramTest.java
// Modified by the Flint authors.
module micrometer_timer_builder_test;

import flint.java.lang : Iterable;
import flint.java.util.concurrent : TimeUnit;
import flint.micrometer.core.instrument : Tag, Tags, Timer;
import flint.micrometer.core.instrument.simple : SimpleMeterRegistry;
import std.typecons : Nullable;

@safe:

@("doesNotThrowAnyExceptionWhenPercentilesAreNotUsed")
unittest
{
    auto registry = new SimpleMeterRegistry;
    auto timer = Timer.builder("my.timer").register(registry);
    assert(timer is registry.timer("my.timer"));
    timer.record(10, TimeUnit.MILLISECONDS);
    assert(timer.count() == 1);
    assert(timer.totalTime(TimeUnit.MILLISECONDS) == 10);
}

@("timer builders retain the first metadata for an identity and can be reused with new tags")
unittest
{
    auto registry = new SimpleMeterRegistry;
    auto builder = Timer.builder("request.duration").tags("method", "POST", "region", "west");
    builder.tags(cast(string[]) null);
    builder.tags(cast(Iterable!Tag) null);
    auto original = builder.tags(Tags.of("method", "GET"))
        .description(Nullable!string("Request duration")).register(registry);
    const duplicate = Timer.builder("request.duration").tags("region", "west").tag("method", "GET")
        .description(Nullable!string("Other description")).register(registry);
    auto updated = builder.tag("region", "east").description(Nullable!string.init).register(registry);

    assert(original is duplicate);
    assert(original is registry.timer("request.duration", "region", "west", "method", "GET"));
    assert(original.getId().getDescription().get() == "Request duration");
    assert(original.getId().getBaseUnit().get() == "seconds");
    assert(original !is updated);
    assert(original.getId().getTag("region").get() == "west");
    assert(updated.getId().getTag("region").get() == "east");
    assert(updated.getId().getTag("method").get() == "GET");
    assert(updated.getId().getDescription().isNull);
}
