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
import flint.java.util : List;
import flint.java.util.concurrent : TimeUnit;
import flint.java.util.concurrent.callable : Callable;
import flint.java.util.function_ : BooleanSupplier, DoubleSupplier, Supplier;
import flint.java.util.function_.intsupplier : IntSupplier;
import flint.java.util.function_.longsupplier : LongSupplier;
import flint.micrometer.core.instrument : Measurement, Meter, Tags, Timer;
import flint.micrometer.core.instrument.distribution : CountAtBucket, HistogramSnapshot, ValueAtPercentile;
import flint.micrometer.core.instrument.noop : NoopMeter, NoopTimer;
import flint.micrometer.core.instrument.simple : SimpleMeterRegistry;
import std.exception : assertThrown;
import std.typecons : Nullable;

@safe:

private Meter.Id testId()
{
    return new Meter.Id("test", Tags.of("name", "value"), Nullable!string(""),
            Nullable!string(""), Meter.Type.TIMER);
}

@("returnsId")
unittest
{
    auto id = testId();
    NoopMeter meter = new NoopTimer(id);
    assert(meter.getId() is id);
}

@("returnsCountAsZero")
unittest
{
    auto timer = new NoopTimer(testId());
    assert(timer.count() == 0);
}

@("returnsTotalTimeAsZero")
unittest
{
    auto timer = new NoopTimer(testId());
    assert(timer.totalTime(TimeUnit.SECONDS) == 0.0);
}

@("returnsMaxAsZero")
unittest
{
    auto timer = new NoopTimer(testId());
    assert(timer.max(TimeUnit.SECONDS) == 0.0);
}

@("returnsBaseTimeUnit")
unittest
{
    auto timer = new NoopTimer(testId());
    assert(timer.baseTimeUnit() == TimeUnit.SECONDS);
}

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

    auto timer = new NoopTimer(testId());
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

    auto timer = new NoopTimer(testId());
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

    auto timer = new NoopTimer(testId());
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
    auto timer = new NoopTimer(testId());
    HistogramSnapshot snapshot = timer.takeSnapshot();
    auto expected = HistogramSnapshot.empty(0, 0, 0);
    assert(snapshot.count() == expected.count());
    assert(snapshot.total() == expected.total());
    assert(snapshot.max() == expected.max());
    const CountAtBucket[] buckets = snapshot.histogramCounts();
    const ValueAtPercentile[] percentiles = snapshot.percentileValues();
    assert(buckets.length == 0 && percentiles.length == 0);
}

@("a public no-op timer shares empty measurements and executes callbacks without allocating")
unittest
{
    static final class True : BooleanSupplier
    {
        override bool getAsBoolean()
        {
            return true;
        }
    }

    auto timer = new NoopTimer(testId());
    Timer meter = timer;
    List!Measurement measurements = timer.measure();
    assert(measurements.isEmpty());
    auto intSupplier = IntSupplier.of(() => int.min);
    auto longSupplier = LongSupplier.of(() => long.max);
    auto booleanSupplier = new True;
    auto doubleSupplier = DoubleSupplier.of(() => -1.25);
    const allocatedBefore = GC.stats().allocatedInCurrentThread;
    foreach (iteration; 0 .. 256)
    {
        meter.record(1L, TimeUnit.SECONDS);
        assert(timer.record(intSupplier) == int.min);
        assert(timer.record(longSupplier) == long.max);
        assert(timer.record(booleanSupplier));
        assert(timer.record(doubleSupplier) == -1.25);
        assert(meter.count() == 0 && meter.mean(TimeUnit.NANOSECONDS) == 0.0);
        assert(meter.measure() is measurements);
    }
    assert(GC.stats().allocatedInCurrentThread == allocatedBefore);
}

@("a public no-op timer propagates the original callback exception")
unittest
{
    auto timer = new NoopTimer(testId());
    auto failure = new Exception("no-op timer callback");
    auto action = IntSupplier.of(delegate int() @safe { throw failure; });
    bool caught;
    try
        timer.record(action);
    catch (Exception error)
        caught = error is failure;
    assert(caught && timer.count() == 0);
}

@("the Java runnable overload stays overridable")
unittest
{
    static final class RunnableOverride : NoopTimer
    {
        bool called;

        this(Meter.Id id) @safe
        {
            super(id);
        }

        override void record(Runnable) @safe
        {
            called = true;
        }
    }

    auto timer = new RunnableOverride(testId());
    Timer meter = timer;
    meter.record(cast(Runnable) null);
    assert(timer.called);
}

@("a public no-op timer exposes inherited wrap and legacy snapshot overloads")
unittest
{
    auto timer = new NoopTimer(testId());
    int delegate() @safe action = () => 42;
    auto wrapped = timer.wrap(action);
    assert(wrapped() == 42 && timer.count() == 0);
    assert(timer.takeSnapshot(true).count() == 0);
}

@("a final no-op timer subclass calls the concrete overloads")
unittest
{
    static final class FinalTimer : NoopTimer
    {
        this(Meter.Id id) @safe
        {
            super(id);
        }
    }

    static final class Action : Runnable
    {
        int calls;

        override void run() @safe
        {
            ++calls;
        }
    }

    auto timer = new FinalTimer(testId());
    auto action = new Action;
    auto supplier = IntSupplier.of(() => 12);
    int delegate() @safe read = () => -5;
    bool delegate() @safe readFlag = () => true;
    double delegate() @safe readDouble = () => -1.25;
    timer.record(1L, TimeUnit.SECONDS);
    assert(timer.record(supplier) == 12);
    assert(timer.record(read) == -5);
    assert(timer.record(readFlag));
    assert(timer.record(readDouble) == -1.25);
    timer.wrap(action).run();
    assert(timer.wrap(read)() == -5);
    assert(action.calls == 1 && timer.count() == 0);
    assert(timer.takeSnapshot(true).count() == 0);
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
