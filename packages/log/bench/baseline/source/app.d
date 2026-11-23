module app;

import core.atomic : atomicLoad, atomicStore;
import core.stdc.stdio : snprintf;
import core.stdc.time : time_t, tm;

version (OSX)
{
    import core.sys.posix.time : gmtime_r, timespec;

    // <time.h>: druntime declares neither for Darwin; CLOCK_REALTIME is 0, as flint.log uses (ADR-024).
    private enum int CLOCK_REALTIME = 0;
    private extern (C) int clock_gettime(int clock, timespec* value) @system nothrow @nogc;
}
else
    import core.sys.posix.time : CLOCK_REALTIME, clock_gettime, gmtime_r, timespec;
import core.thread.osthread : Thread;
import core.time : MonoTime, msecs;
import flint.arena : Status;
import log_workload : Capture, batchSize, longMessage, runProbe;
import std.exception : enforce;

private struct Entry
{
    char[longMessage] message;
    uint length;
    timespec stamp;
}

private struct Reference
{
    private Entry[batchSize] slots;
    private shared ulong published;
    private shared ulong retired;
    private shared bool stopping;
    private shared Status failure;
    Capture* capture;

    Status submit(bool enabled, scope const(char)[] message) @safe nothrow @nogc
    {
        if (!enabled)
            return Status.ok;
        const head = atomicLoad(retired);
        const tail = atomicLoad(published);
        if (tail - head == batchSize)
            return Status.resourceExhausted;
        auto slot = &slots[tail % batchSize];
        if (!clockFor(slot.stamp))
            return Status.ioError;
        slot.message[0 .. message.length] = message;
        slot.length = cast(uint) message.length;
        atomicStore(published, tail + 1);
        return Status.ok;
    }

    Status drain() @safe nothrow @nogc
    {
        const until = MonoTime.currTime + 5000.msecs;
        const goal = atomicLoad(published);
        while (atomicLoad(retired) < goal)
        {
            const error = atomicLoad(failure);
            if (error != Status.ok)
                return error;
            if (MonoTime.currTime >= until)
                return Status.timedOut;
            pause();
        }
        return Status.ok;
    }

    void stop()
    {
        atomicStore(stopping, true);
    }

    void consume() nothrow @nogc
    {
        char[8192] buffer;
        while (!atomicLoad(stopping))
        {
            const head = atomicLoad(retired);
            if (head == atomicLoad(published))
            {
                pause();
                continue;
            }
            const length = render(slots[head % batchSize], buffer[], head + 1);
            if (length <= 0 || length >= buffer.length)
            {
                atomicStore(failure, Status.ioError);
                return;
            }
            const status = capture.take(buffer[0 .. length]);
            if (status == Status.ok)
                atomicStore(retired, head + 1);
            else if (status == Status.unavailable)
                pause();
            else
            {
                atomicStore(failure, status);
                return;
            }
        }
    }
}

// SAFETY: The only local output is one timespec; the clock call never retains it.
private bool clockFor(ref timespec stamp) @trusted nothrow @nogc
{
    return clock_gettime(CLOCK_REALTIME, &stamp) == 0;
}

// SAFETY: Sleeping suspends only the current benchmark thread.
private void pause() @trusted nothrow @nogc
{
    Thread.sleep(1.msecs);
}

private int render(ref const Entry record, char[] output, ulong sequence) nothrow @nogc
{
    tm utc;
    const time_t stamp = record.stamp.tv_sec;
    if (gmtime_r(&stamp, &utc) is null)
        return -1;
    enum prefix = "{\"timestamp\":\"%04d-%02d-%02dT%02d:%02d:%02d.%03dZ\",\"seq\":\"%020llu\","
        ~ "\"level\":\"info\",\"requestId\":0,\"traceId\":\"00000000000000000000000000000000\","
        ~ "\"spanId\":\"0000000000000000\",\"message\":\"%.*s\",\"fields\":{}}\n";
    return snprintf(output.ptr, output.length, prefix, utc.tm_year + 1900, utc.tm_mon + 1,
            utc.tm_mday, utc.tm_hour, utc.tm_min, utc.tm_sec,
            cast(int)(record.stamp.tv_nsec / 1_000_000), sequence, cast(int) record.length, record.message.ptr);
}

/// Exercise the same fixture through a minimal direct SPSC queue and native formatter.
int main()
{
    auto reference = new Reference;
    reference.capture = new Capture;
    auto consumer = new Thread(&reference.consume).start();
    scope (exit)
    {
        reference.stop();
        consumer.join();
    }
    return runProbe(&reference.submit, &reference.drain, reference.capture);
}
