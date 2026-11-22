module probe;

import core.atomic : atomicLoad, atomicOp, atomicStore;
import core.thread.osthread : Thread;
import core.time : MonoTime, dur;
import core.stdc.stdio : printf;
import core.stdc.stdlib : qsort;
import flint.arena : Error, RequestArena, Status;

@safe:

private enum operations = 1_024;
private enum capacity = 64;
private enum payloadBytes = 4_096;

alias Echo = Error function(scope const(ubyte)[], scope ubyte[], out size_t) @safe nothrow @nogc;

/// Validate a fixture in both debug and release builds.
void check(bool passes) nothrow @nogc
{
    if (!passes)
        assert(0, "conc benchmark invariant failed");
}

private struct Trial
{
    ulong checksum;
    long elapsed;
    ulong accepted;
    ulong rejected;
    long[] waits;
}

private struct Traffic(Adapter)
{
    Adapter queue;
    bool measure;
    MonoTime expires;
    shared bool running;
    shared uint producerNumber;
    shared ulong rejected;
    shared ulong checksum;
    shared uint[32 * operations] seen;
    long[] waits;
}

/// Park briefly between unsuccessful attempts.
void pauseWorker() nothrow @nogc
{
    Thread.sleep(dur!"usecs"(1));
}

// SAFETY: All threads capture only GC-owned, stable benchmark state. Every
// caller joins these threads before disposing of the queues they borrow.
private Thread launch(void delegate() @safe run) @trusted
{
    return new Thread(run).start();
}

// SAFETY: Each thread has a unique join owner that never runs on that thread.
private void finish(Thread thread) @trusted
{
    thread.join();
}

private void readTraffic(Adapter)(Traffic!Adapter* traffic, uint count) nothrow @nogc
{
    while (!atomicLoad(traffic.running))
        pauseWorker();

    ulong checksum;
    for (;;)
    {
        const result = traffic.queue.take();
        if (result.ok())
        {
            check(result.value < count);
            check(atomicOp!"+="(traffic.seen[result.value], 1U) == 1);
            checksum += result.value + 1;
            continue;
        }
        if (result.error.code == Status.cancelled)
            break;

        check(result.error.code == Status.unavailable);
        check(MonoTime.currTime < traffic.expires);
        pauseWorker();
    }
    atomicOp!"+="(traffic.checksum, checksum);
}

private void writeTraffic(Adapter)(Traffic!Adapter* traffic) nothrow @nogc
{
    while (!atomicLoad(traffic.running))
        pauseWorker();

    const start = (atomicOp!"+="(traffic.producerNumber, 1U) - 1) * operations;
    ulong rejected;
    foreach (key; start .. start + operations)
    {
        MonoTime began;
        if (traffic.measure)
            began = MonoTime.currTime;
        for (;;)
        {
            const status = traffic.queue.offer(key);
            if (status == Status.ok)
                break;
            check(status == Status.resourceExhausted);
            check(MonoTime.currTime < traffic.expires);
            ++rejected;
            pauseWorker();
        }
        if (traffic.measure)
            traffic.waits[key] = (MonoTime.currTime - began).total!"nsecs";
    }
    atomicOp!"+="(traffic.rejected, rejected);
}

private Trial queueTrial(Adapter)(uint producers, uint consumers, bool measure)
{
    auto traffic = new Traffic!Adapter;
    traffic.queue.prepare(capacity);
    scope (exit)
        destroy(traffic.queue);
    traffic.measure = measure;
    immutable count = producers * operations;
    if (measure)
        traffic.waits = new long[count];

    auto writers = new Thread[producers];
    auto readers = new Thread[consumers];
    foreach (ref thread; readers)
        thread = launch(() { readTraffic(traffic, count); });
    foreach (ref thread; writers)
        thread = launch(() { writeTraffic(traffic); });

    const began = MonoTime.currTime;
    traffic.expires = began + dur!"seconds"(10);
    atomicStore(traffic.running, true);
    foreach (thread; writers)
        finish(thread);
    traffic.queue.close();
    foreach (thread; readers)
        finish(thread);
    const elapsed = (MonoTime.currTime - began).total!"nsecs";

    const checksum = atomicLoad(traffic.checksum);
    check(checksum == cast(ulong) count * (count + 1) / 2);
    return Trial(checksum, elapsed, count, atomicLoad(traffic.rejected), traffic.waits);
}

private ulong sampleQueue(Adapter)(string name, uint producers, uint consumers, bool measure)
{
    auto first = queueTrial!Adapter(producers, consumers, measure);
    if (!measure)
        return first.checksum;

    auto elapsed = first.elapsed;
    auto accepted = first.accepted;
    auto rejected = first.rejected;
    auto waits = first.waits;
    while (elapsed < 100_000_000)
    {
        const repeat = queueTrial!Adapter(producers, consumers, true);
        check(repeat.checksum == first.checksum);
        elapsed += repeat.elapsed;
        accepted += repeat.accepted;
        rejected += repeat.rejected;
        waits ~= repeat.waits;
    }
    sortWaits(waits);
    immutable p99 = waits[(waits.length * 99 + 99) / 100 - 1];
    printQueue(name, producers, accepted, rejected, cast(double) accepted * 1_000_000_000 / elapsed, p99);
    return first.checksum;
}

private ulong queueEdges(Adapter)()
{
    Adapter queue;
    queue.prepare(capacity);
    foreach (_; 0 .. capacity)
        check(queue.take().error.code == Status.unavailable);
    foreach (value; 0U .. capacity)
        check(queue.offer(value) == Status.ok);
    foreach (_; 0 .. capacity)
        check(queue.offer(0) == Status.resourceExhausted);
    queue.close();
    ulong checksum;
    foreach (value; 0U .. capacity)
    {
        const result = queue.take();
        check(result.ok() && result.value == value);
        checksum += result.value;
    }
    check(queue.take().error.code == Status.cancelled);
    return checksum;
}

private void samplePoll(Adapter)(string name, bool full)
{
    Adapter queue;
    queue.prepare(capacity);
    if (full)
    {
        foreach (value; 0U .. capacity)
            check(queue.offer(value) == Status.ok);
    }

    ulong count;
    long elapsed;
    const began = MonoTime.currTime;
    do
    {
        foreach (_; 0 .. 2_048)
        {
            const status = full ? queue.offer(0) : queue.take().error.code;
            check(status == (full ? Status.resourceExhausted : Status.unavailable));
        }
        count += 2_048;
        elapsed = (MonoTime.currTime - began).total!"nsecs";
    }
    while (elapsed < 100_000_000);
    printPoll(name, full ? "full" : "empty", count, elapsed);
}

// SAFETY: qsort passes this comparator two element addresses inside the slice given to sortWaits.
private extern (C) int compareWaits(const void* left, const void* right) @trusted nothrow @nogc
{
    const first = *cast(const(long)*) left;
    const second = *cast(const(long)*) right;
    return (first > second) - (first < second);
}

// SAFETY: The base pointer, element count and element size describe exactly the live slice.
private void sortWaits(scope long[] waits) @trusted nothrow @nogc
{
    qsort(waits.ptr, waits.length, long.sizeof, &compareWaits);
}

// SAFETY: Fixed NUL-terminated literal format; the name is printed with its explicit length and
// every scalar matches its conversion.
private void printQueue(string name, uint producers, ulong accepted, ulong rejected, double rate, long p99) @trusted
{
    printf("%.*s producers=%u accepted=%llu rejected=%llu accepted-ops/s=%g p99-enqueue-ns=%lld\n",
            cast(int) name.length, name.ptr, producers, accepted, rejected, rate, p99);
}

// SAFETY: Fixed NUL-terminated literal format; both strings are printed with their explicit
// lengths and every scalar matches its conversion.
private void printPoll(string name, string state, ulong count, long elapsed) @trusted nothrow @nogc
{
    printf("%.*s %.*s rejected=%llu ns=%lld\n", cast(int) name.length, name.ptr,
            cast(int) state.length, state.ptr, count, elapsed);
}

// SAFETY: Fixed NUL-terminated literal format with matching scalar arguments.
private void printOffload(uint rounds, long elapsed) @trusted nothrow @nogc
{
    printf("offload-round-trips %u %lld ns\n", rounds, elapsed);
}

/// Report the measured cancellation checks.
// SAFETY: Fixed NUL-terminated literal format with matching scalar arguments.
void printCancellation(ulong checked, long elapsed) @trusted nothrow @nogc
{
    printf("cancellation checked=%llu ns=%lld\n", checked, elapsed);
}

/// Emit the consumed checksum in both binaries.
// SAFETY: Fixed NUL-terminated literal format with a matching scalar argument.
void printChecksum(ulong checksum) @trusted nothrow @nogc
{
    printf("conc checksum %llu\n", checksum);
}

private ulong offloadRoundTrip(Echo echo, uint round)
{
    ubyte[payloadBytes + 8] backing;
    scope arena = RequestArena(backing[]);
    auto block = arena.allocate(payloadBytes);
    check(block.ok());
    check(arena.write(block.value, (scope ubyte[] bytes) @safe nothrow @nogc {
            foreach (index, ref byteValue; bytes)
                byteValue = cast(ubyte)(index + round * 13);
        }) == Status.ok);

    ubyte[payloadBytes] output;
    size_t written;
    check(arena.read(block.value, (scope const(ubyte)[] input) @safe nothrow @nogc {
            check(echo(input, output[], written).code == Status.ok);
            check(written == input.length);
        }) == Status.ok);
    check(arena.reset() == Status.ok);

    ulong checksum;
    foreach (index, value; output)
    {
        check(value == cast(ubyte)(index + round * 13));
        checksum += value;
    }
    return checksum;
}

/// Run identical workloads for a package fixture and its provider-free control.
ulong runProbe(Mpsc, Mpmc)(Echo echo, ulong function() @safe cancellation, bool measure)
{
    ulong checksum = queueEdges!Mpsc() + queueEdges!Mpmc();
    if (measure)
    {
        samplePoll!Mpsc("mpsc", false);
        samplePoll!Mpsc("mpsc", true);
        samplePoll!Mpmc("mpmc", false);
        samplePoll!Mpmc("mpmc", true);
    }
    foreach (producers; [1U, 2U, 8U, 32U])
    {
        checksum += sampleQueue!Mpsc("mpsc", producers, 1, measure);
        const consumers = producers;
        checksum += sampleQueue!Mpmc("mpmc", producers, consumers, measure);
    }

    const began = MonoTime.currTime;
    uint round;
    do
    {
        const sample = offloadRoundTrip(echo, round);
        check(sample == 522_240);
        if (round < 64)
            checksum += sample;
        ++round;
    }
    while (round < 64 || (measure && (MonoTime.currTime - began).total!"nsecs" < 100_000_000));
    if (measure)
        printOffload(round, (MonoTime.currTime - began).total!"nsecs");

    return checksum + cancellation();
}
