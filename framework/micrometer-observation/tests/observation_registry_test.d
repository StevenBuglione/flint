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
// Ported from micrometer-observation 1.18.0: micrometer-observation/src/test/java/io/micrometer/observation/ObservationRegistryTest.java
// Modified by the Flint authors.
module flint.micrometer.observation_registry_test;

import flint.micrometer.observation : Observation, ObservationHandler, ObservationRegistry;

@safe:

private alias Handler = ObservationHandler!(Observation.Context);

private final class TestHandler : Handler
{
    override bool supportsContext(Observation.Context context)
    {
        return true;
    }

    mixin Handler.Defaults;
}

@("observationHandlersShouldBeAddedToTheRegistry")
unittest
{
    auto registry = ObservationRegistry.create();
    auto first = new TestHandler;
    auto second = new TestHandler;

    registry.observationConfig().observationHandler(first);
    auto handlers = registry.observationConfig().getObservationHandlers();
    assert(!handlers.empty && handlers.front.source() is first);
    handlers.popFront();
    assert(handlers.empty);

    registry.observationConfig().observationHandler(second);
    handlers = registry.observationConfig().getObservationHandlers();
    assert(!handlers.empty && handlers.front.source() is first);
    handlers.popFront();
    assert(!handlers.empty && handlers.front.source() is second);
    handlers.popFront();
    assert(handlers.empty);
}

private final class CustomRegistry : ObservationRegistry
{
    private ObservationConfig config;

    this(ObservationConfig config)
    {
        this.config = config;
    }

    override ObservationConfig observationConfig()
    {
        return config;
    }

    mixin ObservationRegistry.Defaults;
}

@("each simple registry owns its configuration and reports whether handlers exist")
unittest
{
    auto first = ObservationRegistry.create();
    auto second = ObservationRegistry.create();
    auto config = first.observationConfig();
    assert(first !is second && config !is second.observationConfig());
    assert(first.isNoop() && second.isNoop());
    ObservationRegistry custom = new CustomRegistry(second.observationConfig());
    assert(!custom.isNoop());

    config.observationPredicate((name, context) => true);
    config.observationFilter(context => context);
    config.observationConvention(context => true);
    assert(first.isNoop() && config is first.observationConfig());

    config.observationHandler(null);
    assert(!first.isNoop() && second.isNoop());
}
