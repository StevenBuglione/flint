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
// Ported from micrometer-core 1.18.0: micrometer-core/src/test/java/io/micrometer/core/instrument/noop/NoopTimerTest.java
// Modified by the Flint authors.
module micrometer_timer_runnable_test;

import core.memory : GC;
import flint.java.lang : NullPointerException, Runnable;
import flint.java.util.concurrent.callable : Callable;
import flint.java.util.function_ : Supplier;
import flint.micrometer.core.instrument : Timer;
import flint.micrometer.core.instrument.distribution : CountAtBucket, HistogramSnapshot,
    HistogramSupport, ValueAtPercentile;
import flint.micrometer.core.instrument.simple : SimpleMeterRegistry;
import std.exception : assertThrown;
import std.typecons : Nullable;

@safe:

@("recordSupplier")
unittest
{
    static final class Value : Supplier!(Nullable!string)
    {
        this() scope
        {
        }

        override Nullable!string get()
        {
            return Nullable!string("value");
        }
    }

    static assert(!__traits(compiles, (Timer timer) @safe {
            scope stackValue = new Value;
            timer.record(stackValue);
        }));
    static assert(!__traits(compiles, (Timer timer) @safe {
            scope stackValue = new Value;
            timer.wrap(stackValue);
        }));

    auto registry = new SimpleMeterRegistry;
    registry.close();
    auto timer = registry.timer("test");
    auto supplier = new Value;
    const allocatedBefore = GC.stats().allocatedInCurrentThread;
    assert(timer.record(supplier).get() == "value");
    assert(timer.record(() => Nullable!string.init).isNull());
    assert(GC.stats().allocatedInCurrentThread == allocatedBefore);
    assert(timer.count() == 0);
    assertThrown!NullPointerException(timer.record(cast(Supplier!(Nullable!string)) null));
}

@("recordCallable")
unittest
{
    static final class Value : Callable!(Nullable!string)
    {
        this() scope
        {
        }

        override Nullable!string call()
        {
            return Nullable!string("value");
        }
    }

    static assert(!__traits(compiles, (Timer timer) @safe {
            scope stackValue = new Value;
            timer.recordCallable(stackValue);
        }));
    static assert(!__traits(compiles, (Timer timer) @safe {
            scope stackValue = new Value;
            timer.wrap(stackValue);
        }));

    auto registry = new SimpleMeterRegistry;
    registry.close();
    auto timer = registry.timer("test");
    Callable!(Nullable!string) callable = new Value;
    const allocatedBefore = GC.stats().allocatedInCurrentThread;
    assert(timer.recordCallable(callable).get() == "value");
    assert(timer.recordCallable(() => Nullable!string.init).isNull());
    assert(GC.stats().allocatedInCurrentThread == allocatedBefore);
    assert(timer.count() == 0);
    assertThrown!NullPointerException(timer.recordCallable(cast(Callable!(Nullable!string)) null));
}

@("recordRunnable")
unittest
{
    static final class Action : Runnable
    {
        int runs;

        override void run()
        {
            ++runs;
        }
    }

    auto registry = new SimpleMeterRegistry;
    registry.close();
    auto timer = registry.timer("test");
    auto action = new Action;
    timer.record(action);
    assert(action.runs == 1 && timer.count() == 0);
    assertThrown!NullPointerException(timer.record(cast(Runnable) null));
    assertThrown!NullPointerException(timer.record(cast(void delegate() @safe) null));
}

@("wrapping null defers the error until invocation")
unittest
{
    auto registry = new SimpleMeterRegistry;
    registry.close();
    auto timer = registry.timer("test");
    auto wrapped = timer.wrap(cast(Runnable) null);
    auto wrappedDelegate = timer.wrap(cast(void delegate() @safe) null);
    assertThrown!NullPointerException(wrapped.run());
    assertThrown!NullPointerException(wrappedDelegate());
    assert(timer.count() == 0);
}

@("returnsEmptySnapshot")
unittest
{
    auto registry = new SimpleMeterRegistry;
    registry.close();
    Timer timer = registry.timer("test");
    HistogramSupport histogram = timer;
    HistogramSnapshot snapshot = histogram.takeSnapshot();
    auto expected = HistogramSnapshot.empty(0, 0, 0);
    assert(snapshot.count() == expected.count());
    assert(snapshot.total() == expected.total());
    assert(snapshot.max() == expected.max());
    const CountAtBucket[] buckets = snapshot.histogramCounts();
    const ValueAtPercentile[] percentiles = snapshot.percentileValues();
    assert(buckets.length == 0 && percentiles.length == 0);
}

@("snapshot descriptors agree with type names from the public import")
unittest
{
    import flint.engine.aot.descriptor : DescriptorTable, descriptorOf;
    import flint.engine.aot.name : typeNameOf;

    auto descriptor = descriptorOf!HistogramSnapshot;
    assert(descriptor.name == typeNameOf!HistogramSnapshot);
    auto table = new DescriptorTable;
    table.add(descriptor);
    assert(table.find(typeNameOf!HistogramSnapshot) is descriptor);
}

@("generic wrapping defers null errors even after registry close")
unittest
{
    alias Result = Nullable!string;
    static assert(!__traits(compiles, (Timer timer, scope Result delegate() @safe action) @safe {
            timer.wrap(action);
        }));
    auto registry = new SimpleMeterRegistry;
    registry.close();
    auto timer = registry.timer("test");
    auto callable = timer.wrap(cast(Callable!Result) null);
    auto voidCallable = timer.wrap(cast(Callable!void) null);
    auto supplier = timer.wrap(cast(Supplier!Result) null);
    auto dg = timer.wrap(cast(Result delegate() @safe) null);
    assertThrown!NullPointerException(callable.call());
    assertThrown!NullPointerException(voidCallable.call());
    assertThrown!NullPointerException(supplier.get());
    assertThrown!NullPointerException(dg());
    assert(timer.count() == 0);
}
