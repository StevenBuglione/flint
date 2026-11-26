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
// Ported from micrometer-core 1.18.0: micrometer-core/src/main/java/io/micrometer/core/instrument/simple/SimpleMeterRegistry.java
// Ported from micrometer-core 1.18.0: micrometer-core/src/main/java/io/micrometer/core/instrument/cumulative/CumulativeCounter.java
// Modified by the Flint authors.
module flint.micrometer.core.instrument.simple;

import core.atomic : atomicLoad, cas;
import flint.micrometer.core.instrument : Counter, Meter, MeterRegistry;

@safe:

/// An in-memory registry for meters whose values are read directly.
class SimpleMeterRegistry : MeterRegistry
{
    /// Create an empty registry in cumulative mode.
    this()
    {
        super();
    }

    protected override Counter newCounter(Meter.Id id)
    {
        return new CumulativeCounter(id);
    }
}

private final class CumulativeCounter : Counter
{
    private Meter.Id id;
    private shared double sum = 0.0;

    this(Meter.Id id) nothrow @nogc
    {
        this.id = id;
    }

    override Meter.Id getId() nothrow @nogc
    {
        return id;
    }

    override void increment(double amount) nothrow @nogc
    {
        auto previous = atomicLoad(sum);
        while (!cas(&sum, previous, previous + amount))
            previous = atomicLoad(sum);
    }

    override double count() nothrow @nogc
    {
        return atomicLoad(sum);
    }

    mixin Counter.Defaults;
}
