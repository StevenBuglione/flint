module micrometer_long_task_record_test;

import core.memory : GC;
import flint.java.lang : NullPointerException, Runnable;
import flint.java.util.concurrent : TimeUnit;
import flint.java.util.function_ : Consumer;
import flint.micrometer.core.instrument : LongTaskTimer, Meter, Tags;
import flint.micrometer.core.instrument.noop : NoopLongTaskTimer;
import std.exception : assertThrown;
import std.typecons : Nullable;

@safe:

private alias Sample = LongTaskTimer.Sample;

private final class RecordingSample : Sample
{
    uint stops;
    Exception failure;

    override long stop()
    {
        ++stops;
        if (failure !is null)
            throw failure;
        return 7;
    }

    override double duration(TimeUnit)
    {
        return 7.0;
    }
}

private final class RecordingTimer : NoopLongTaskTimer
{
    RecordingSample sample;
    uint starts;
    Exception failure;

    this()
    {
        auto id = new Meter.Id("tasks", Tags.empty(), Nullable!string.init, Nullable!string.init,
                Meter.Type.LONG_TASK_TIMER);
        super(id);
        sample = new RecordingSample;
    }

    override Sample start()
    {
        ++starts;
        if (failure !is null)
            throw failure;
        return sample;
    }
}

private final class RunAction : Runnable
{
    private RecordingTimer timer;
    uint calls;

    this(RecordingTimer timer)
    {
        this.timer = timer;
    }

    override void run()
    {
        assert(timer.starts == timer.sample.stops + 1);
        ++calls;
    }
}

private Exception failureOf(scope void delegate() @safe action)
{
    try
        action();
    catch (Exception error)
        return error;
    assert(0, "recording should fail");
}

@("runnable and consumer recordings stop the started sample without allocating adapters")
unittest
{
    auto timer = new RecordingTimer;
    LongTaskTimer meter = timer;
    auto runnable = new RunAction(timer);
    uint consumed;
    auto consumer = Consumer!Sample.of((Sample sample) {
        assert(sample is timer.sample && timer.starts == timer.sample.stops + 1);
        ++consumed;
    });

    const before = GC.stats().allocatedInCurrentThread;
    timer.record(runnable);
    timer.record(consumer);
    meter.record(() { runnable.run(); });
    meter.record((Sample sample) { consumer.accept(sample); });
    assert(GC.stats().allocatedInCurrentThread == before);
    assert(timer.starts == 4 && timer.sample.stops == 4);
    assert(runnable.calls == 2 && consumed == 2);
}

@("long task cleanup preserves or replaces a callback failure as Java finally does")
unittest
{
    auto timer = new RecordingTimer;
    auto callbackFailure = new Exception("callback");
    auto stopFailure = new Exception("stop");

    void fail(Sample sample)
    {
        assert(sample is timer.sample);
        throw callbackFailure;
    }

    assert(failureOf(() { timer.record(&fail); }) is callbackFailure);
    assert(timer.starts == 1 && timer.sample.stops == 1);

    timer.sample.failure = stopFailure;
    assert(failureOf(() { timer.record(&fail); }) is stopFailure);
    assert(timer.starts == 2 && timer.sample.stops == 2);
    assert(callbackFailure.next is null && stopFailure.next is null);

    auto startFailure = new Exception("start");
    timer.failure = startFailure;
    assert(failureOf(() { timer.record(() { assert(0, "action ran after start failed"); }); }) is startFailure);
    assert(timer.starts == 3 && timer.sample.stops == 2);
}

@("null long task actions still stop the sample")
unittest
{
    auto timer = new RecordingTimer;
    assertThrown!NullPointerException(timer.record(cast(Runnable) null));
    assertThrown!NullPointerException(timer.record(cast(Consumer!Sample) null));
    assertThrown!NullPointerException(timer.record(cast(void delegate() @safe) null));
    assertThrown!NullPointerException(timer.record(cast(void delegate(Sample) @safe) null));
    assert(timer.starts == 4 && timer.sample.stops == 4);

    timer.sample = null;
    bool called;
    assertThrown!NullPointerException(timer.record((Sample sample) {
            assert(sample is null);
            called = true;
        }));
    assert(called && timer.starts == 5);
}
