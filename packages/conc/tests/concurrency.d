module flint.conc.concurrency_test;

import core.atomic : atomicLoad, atomicOp, atomicStore;
import core.thread.osthread : Thread;
import std.algorithm.mutation : move;
import flint.arena : Error, RequestArena, Status;
import flint.conc : CancelSource, Channel, Context, Deadline, QueueKind, WorkTicket, WorkerOptions, WorkerPool;
import flint.conc : fillSecureRandom;
import flint.conc.sys.atomics : yieldThread;
import flint.conc.sys.workers : WorkerThreads;

@safe:

version (linux) unittest
{
    ubyte[32] first, second;
    assert(fillSecureRandom(first[0 .. 0]).code == Status.ok);
    assert(fillSecureRandom(first[]).code == Status.ok);
    assert(fillSecureRandom(second[]).code == Status.ok);
    assert(first != second);
}

private struct Flat
{
    uint id;
    int[2] coordinate;
}

private struct WithDestructor
{
    ~this()
    {
    }
}

private struct WithPostblit
{
    int number;

    this(this)
    {
    }
}

private class Reference
{
    int number;
}

private union Overlay
{
    int number;
}

private enum TextEnum : string
{
    value = "value"
}

private struct NestedArenaPair
{
    import flint.arena : Buffer;

    Buffer value;
}

private enum Accepts(T) = is(Channel!T);

static assert(Accepts!Flat);
static assert(Accepts!uint);
static assert(Accepts!(Flat[3]));
static assert(!Accepts!string);
static assert(!Accepts!(void*));
static assert(!Accepts!Reference);
static assert(!Accepts!(void delegate()));
static assert(!Accepts!(void function()));
static assert(!Accepts!WithDestructor);
static assert(!Accepts!WithPostblit);
static assert(!Accepts!Overlay);
static assert(!Accepts!TextEnum);
static assert(!Accepts!NestedArenaPair);
static assert(!Accepts!(NestedArenaPair[2]));

@("compile-fail channels of string, pointer, class, delegate, destructor struct and arena Buffer")
unittest
{
    import flint.arena : Buffer;
    import std.traits : hasIndirections;

    static assert(!__traits(compiles, Channel!string.create(2)));
    static assert(!__traits(compiles, Channel!(int*).create(2)));
    static assert(!__traits(compiles, Channel!Reference.create(2)));
    static assert(!__traits(compiles, Channel!(void delegate() @safe nothrow @nogc).create(2)));
    static assert(!__traits(compiles, Channel!WithDestructor.create(2)));
    static assert(!__traits(compiles, Channel!Buffer.create(2)));
    static assert(!__traits(compiles, Channel!(const Buffer).create(2)));
    static assert(!__traits(compiles, Channel!(Buffer, QueueKind.mpmc).create(2)));
    static assert(!__traits(compiles, Channel!(Buffer[1]).create(2)));
    // A Buffer is scalar, so only the explicit channel policy keeps it on its owner thread.
    static assert(!hasIndirections!Buffer);
    static assert(__traits(compiles, Channel!Flat.create(2)));
    static assert(__traits(compiles, Channel!(Flat, QueueKind.mpmc).create(2)));
}

@("channel capacity outside 2 through 1,048,576 or not a power of two is rejected, not rounded")
unittest
{
    const size_t[8] rejected = [0, 1, 3, 6, 1_048_575, 1_048_577, 2_097_152, size_t.max];
    foreach (capacity; rejected)
    {
        assert(Channel!ubyte.create(capacity).error.code == Status.invalidArgument);
        assert(Channel!(ubyte, QueueKind.mpmc).create(capacity).error.code == Status.invalidArgument);
    }

    auto smallest = Channel!ubyte.create(2);
    assert(smallest.ok());
    assert(smallest.value.trySend(1) == Status.ok && smallest.value.trySend(2) == Status.ok);
    assert(smallest.value.trySend(3) == Status.resourceExhausted);

    enum largestCapacity = 1_048_576;
    auto largest = Channel!(ubyte, QueueKind.mpmc).create(largestCapacity);
    assert(largest.ok());
    foreach (index; 0 .. largestCapacity)
        assert(largest.value.trySend(cast(ubyte) index) == Status.ok);
    assert(largest.value.trySend(0) == Status.resourceExhausted);
    assert(largest.value.tryReceive().value == 0);
    assert(largest.value.trySend(0) == Status.ok);
    assert(largest.value.trySend(0) == Status.resourceExhausted);
    largest.value.close();
    assert(largest.value.trySend(0) == Status.cancelled);
    size_t drained;
    for (auto received = largest.value.tryReceive(); received.ok(); received = largest.value.tryReceive())
        assert(received.value == cast(ubyte)(++drained));
    assert(drained == largestCapacity);
    // Exhaustion after close is permanent.
    assert(largest.value.tryReceive().error.code == Status.cancelled);
    assert(largest.value.tryReceive().error.code == Status.cancelled);
}

@("earlier deadlines and cancellation precedence")
unittest
{
    // Overflow saturates at the latest finite deadline. A zero-duration
    // timeout cannot be replaced by cancellation observed later.
    assert(Context.init.check().code == Status.ok);
    assert(Context.init.deadline().monotonicNanoseconds == Deadline.none().monotonicNanoseconds);
    assert(Deadline.afterMillis(ulong.max).monotonicNanoseconds == long.max - 1);

    auto parent = CancelSource.create(Context.init, Deadline.afterMillis(60_000));
    assert(parent.ok());
    auto early = CancelSource.create(parent.value.context(), Deadline.afterMillis(0));
    auto late = CancelSource.create(parent.value.context(), Deadline.afterMillis(120_000));
    assert(early.ok() && late.ok());
    assert(late.value.context().deadline().monotonicNanoseconds == parent.value.context().deadline()
            .monotonicNanoseconds);
    early.value.cancel();
    assert(early.value.context().check().code == Status.timedOut);
    parent.value.cancel();
    parent.value.cancel();
    assert(late.value.context().check().code == Status.cancelled);
    assert(early.value.context().check().code == Status.timedOut);
}

@("deadline views retain the original cancellation and only narrow inherited time")
unittest
{
    const inherited = Deadline.afterMillis(60_000);
    auto source = CancelSource.create(Context.init, inherited);
    assert(source.ok());
    auto original = source.value.context();
    auto unchanged = original.withDeadline(Deadline.none());
    assert(unchanged.deadline().monotonicNanoseconds == inherited.monotonicNanoseconds);

    const earlier = Deadline.afterMillis(1_000);
    auto narrowed = unchanged.withDeadline(earlier);
    assert(narrowed.deadline().monotonicNanoseconds == earlier.monotonicNanoseconds);
    auto expired = narrowed.withDeadline(Deadline(0));
    assert(expired.check().code == Status.timedOut);
    assert(Context.init.withDeadline(Deadline(0)).check().code == Status.timedOut);

    source.value.cancel();
    source.value.close();
    assert(narrowed.check().code == Status.cancelled);
    assert(unchanged.check().code == Status.cancelled);
    assert(original.check().code == Status.cancelled);
    assert(expired.check().code == Status.timedOut);
}

@("retained contexts survive source close and slab reuse")
unittest
{
    // No garbage, stale generation aliasing or reference loss on slab reuse.
    auto root = CancelSource.create(Context.init, Deadline.none());
    auto child = CancelSource.create(root.value.context(), Deadline.none());
    Context retained = child.value.context();
    auto copy = retained;
    retained = Context.init;
    root.value.close();
    root.value.close();
    child.value.close();
    assert(child.value.context().cancelled());
    foreach (_; 0 .. 32_768)
    {
        auto other = CancelSource.create(Context.init, Deadline.none());
        assert(other.ok());
        other.value.cancel();
        assert(other.value.context().cancelled());
    }
    assert(!copy.cancelled());
    copy = Context.init;
}

private size_t availableSources()
{
    // Hold every free slab node at once, then release them all.
    auto held = new CancelSource[16_384 + 1];
    size_t count;
    for (; count < held.length; ++count)
    {
        auto created = CancelSource.create(Context.init, Deadline.none());
        if (!created.ok())
            break;
        move(created.value, held[count]);
    }
    foreach (ref source; held[0 .. count])
        source.close();
    return count;
}

private struct SharedContexts
{
    Context[8] contexts;
    shared uint ready;
    shared bool stop;
    shared ulong observedCancelled;
}

private void churnContexts(SharedContexts* state) nothrow @nogc
{
    atomicOp!"+="(state.ready, 1U);
    ulong cancelled;
    while (!atomicLoad(state.stop))
    {
        foreach (ref context; state.contexts)
        {
            auto copy = context;
            auto narrowed = copy.withDeadline(Deadline.afterMillis(60_000));
            if (narrowed.check().code == Status.cancelled)
                ++cancelled;
            auto child = CancelSource.create(narrowed, Deadline.none());
            if (child.ok() && child.value.context().check().code == Status.cancelled)
                ++cancelled;
        }
    }
    atomicOp!"+="(state.observedCancelled, cancelled);
}

@("concurrent context copies, child sources, cancellation and close return every slab node")
unittest
{
    const before = availableSources();
    assert(before > 0);
    auto state = new SharedContexts;
    CancelSource[8] sources;
    foreach (index, ref source; sources)
    {
        auto created = CancelSource.create(Context.init, Deadline.none());
        assert(created.ok());
        move(created.value, source);
        state.contexts[index] = source.context();
    }

    WorkerThreads threads;
    assert(threads.start(4, () @safe nothrow{ churnContexts(state); }));
    while (atomicLoad(state.ready) != 4)
        yieldThread();
    foreach (index, ref source; sources)
    {
        if (index % 2 == 0)
            source.cancel();
        source.close();
        foreach (_; 0 .. 2_000)
            yieldThread();
    }
    atomicStore(state.stop, true);
    threads.join();
    assert(atomicLoad(state.observedCancelled) != 0);
    foreach (index, ref context; state.contexts)
    {
        assert(context.check().code == (index % 2 == 0 ? Status.cancelled : Status.ok));
        context = Context.init;
    }
    assert(availableSources() == before, "a concurrent release leaked or double-freed a slab node");
}

private struct History(QueueKind kind)
{
    Channel!(uint, kind) channel;
    shared uint producerIndex;
    shared uint ready;
    shared uint done;
    shared uint[8 * 128] accepted;
    shared uint[8 * 128] received;
}

private void publish(QueueKind kind)(History!kind* state) nothrow @nogc
{
    const start = (atomicOp!"+="(state.producerIndex, 1U) - 1) * 128;
    atomicOp!"+="(state.ready, 1U);
    foreach (key; start .. start + 128)
    {
        for (;;)
        {
            const status = state.channel.trySend(key);
            if (status == Status.ok)
            {
                atomicStore(state.accepted[key], 1U);
                break;
            }
            if (status == Status.cancelled)
                return;
            assert(status == Status.resourceExhausted);
            yieldThread();
        }
    }
    atomicOp!"+="(state.done, 1U);
}

private void consume(QueueKind kind)(History!kind* state) nothrow @nogc
{
    uint[8] latest;
    for (;;)
    {
        const result = state.channel.tryReceive();
        if (result.ok())
        {
            assert(result.value < state.received.length);
            static if (kind == QueueKind.mpsc)
            {
                const producer = result.value / 128;
                const offset = result.value % 128;
                assert(latest[producer]++ == offset);
            }
            assert(atomicOp!"+="(state.received[result.value], 1U) == 1);
            continue;
        }
        if (result.error.code == Status.cancelled)
            return;
        assert(result.error.code == Status.unavailable);
        yieldThread();
    }
}

private void exerciseHistory(QueueKind kind)(uint producers, uint consumers, bool raceClose)
{
    auto state = new History!kind;
    auto created = Channel!(uint, kind).create(16);
    assert(created.ok());
    move(created.value, state.channel);
    scope (exit)
        destroy(state.channel);

    WorkerThreads senders;
    WorkerThreads readers;
    assert(senders.start(producers, () @safe nothrow @nogc { publish(state); }));
    assert(readers.start(consumers, () @safe nothrow @nogc { consume(state); }));

    const timeout = Deadline.afterMillis(5_000).monotonicNanoseconds;
    while (atomicLoad(state.ready) < producers || (!raceClose && atomicLoad(state.done) < producers))
    {
        import flint.conc.sys.cancellation : monotonicNanoseconds;

        if (monotonicNanoseconds() >= timeout)
            break;
        yieldThread();
    }
    state.channel.close();
    state.channel.close();
    senders.join();
    readers.join();

    assert(atomicLoad(state.ready) == producers);
    foreach (key; 0 .. state.accepted.length)
    {
        const accepted = atomicLoad(state.accepted[key]);
        assert(accepted == atomicLoad(state.received[key]));
        if (!raceClose && key < producers * 128)
            assert(accepted == 1);
    }
    assert(state.channel.trySend(0) == Status.cancelled);
    assert(state.channel.tryReceive().error.code == Status.cancelled);
}

@("bounded FIFO and concurrent close histories")
unittest
{
    const invalid = Channel!uint.create(3);
    assert(invalid.error.code == Status.invalidArgument);
    auto queue = Channel!Flat.create(2);
    assert(queue.ok());
    assert(queue.value.tryReceive().error.code == Status.unavailable);
    assert(queue.value.trySend(Flat(7, [1, 2])) == Status.ok);
    assert(queue.value.trySend(Flat(8, [3, 4])) == Status.ok);
    assert(queue.value.trySend(Flat(9, [5, 6])) == Status.resourceExhausted);
    queue.value.close();
    assert(queue.value.tryReceive().value.id == 7);
    assert(queue.value.tryReceive().value.id == 8);
    assert(queue.value.tryReceive().error.code == Status.cancelled);

    foreach (count; [1U, 2U, 8U])
    {
        exerciseHistory!(QueueKind.mpsc)(count, 1, false);
        exerciseHistory!(QueueKind.mpsc)(count, 1, true);
        exerciseHistory!(QueueKind.mpmc)(count, count, false);
        exerciseHistory!(QueueKind.mpmc)(count, count, true);
    }
}

private shared bool workerEntered;
private shared bool workerReleased;
private shared uint workerCopies;
private shared uint shutdownStarted;
private shared uint shutdownFinished;

private bool waitForFlag(ref shared bool flag) nothrow @nogc
{
    import flint.conc.sys.cancellation : monotonicNanoseconds;

    immutable deadline = Deadline.afterMillis(5_000).monotonicNanoseconds;
    while (!atomicLoad(flag))
    {
        if (monotonicNanoseconds() >= deadline)
            return false;
        yieldThread();
    }
    return true;
}

private Error copyWork(scope const(ubyte)[] input, scope ubyte[] output, out size_t written) nothrow @nogc
{
    assert(Thread.getThis() !is null);
    atomicOp!"+="(workerCopies, 1U);
    output[0 .. input.length] = input[];
    written = input.length;
    return Error.init;
}

private Error blockedWork(scope const(ubyte)[] input, scope ubyte[] output, out size_t written) nothrow @nogc
{
    atomicStore(workerEntered, true);
    if (!waitForFlag(workerReleased))
        return Error(Status.timedOut);
    return copyWork(input, output, written);
}

private Error collect(ref WorkerPool pool, WorkTicket ticket, scope ubyte[] output, out size_t written) nothrow @nogc
{
    import flint.conc.sys.cancellation : monotonicNanoseconds;

    immutable deadline = Deadline.afterMillis(5_000).monotonicNanoseconds;
    for (;;)
    {
        const result = pool.join(ticket, output, written);
        if (result.code != Status.unavailable)
            return result;
        if (monotonicNanoseconds() >= deadline)
            return Error(Status.timedOut);
        yieldThread();
    }
}

@("copy arena input and consume completion once")
unittest
{
    auto result = WorkerPool.create(WorkerOptions(1, 2));
    assert(result.ok());
    scope (exit)
        atomicStore(workerReleased, true);
    atomicStore(workerEntered, false);
    atomicStore(workerReleased, false);
    atomicStore(workerCopies, 0U);

    auto queuedCancel = CancelSource.create(Context.init, Deadline.none());
    queuedCancel.value.cancel();
    assert(result.value.submit(queuedCancel.value.context(), [], &copyWork).error.code == Status.cancelled);

    ubyte[32] backing;
    scope arena = RequestArena(backing[]);
    ubyte[4] data = [5, 7, 8, 9];
    auto block = arena.copyIn(data[]);
    WorkTicket first;
    assert(arena.read(block.value, (scope const(ubyte)[] bytes) @safe nothrow @nogc {
            const submission = result.value.submit(Context.init, bytes, &blockedWork);
            assert(submission.ok());
            first = submission.value;
        }) == Status.ok);
    assert(waitForFlag(workerEntered));
    assert(arena.reset() == Status.ok);
    auto replacement = arena.allocate(4);
    assert(arena.write(replacement.value, (scope ubyte[] bytes) @safe nothrow @nogc { bytes[] = 99; }) == Status.ok);

    auto next = CancelSource.create(Context.init, Deadline.none());
    auto second = result.value.submit(next.value.context(), data[], &copyWork);
    assert(second.ok());
    assert(result.value.submit(Context.init, [], &copyWork).error.code == Status.resourceExhausted);
    next.value.cancel();

    atomicStore(workerReleased, true);
    ubyte[4] actual;
    size_t written;
    assert(collect(result.value, first, actual[0 .. 1], written).code == Status.resourceExhausted);
    assert(written == 0);
    assert(collect(result.value, first, actual[], written).code == Status.ok);
    assert(written == data.length && actual == data);
    assert(result.value.join(first, actual[], written).code == Status.notFound);
    assert(collect(result.value, second.value, actual[], written).code == Status.cancelled);
    assert(written == 0 && atomicLoad(workerCopies) == 1U);

    auto completed = CancelSource.create(Context.init, Deadline.none());
    const last = result.value.submit(completed.value.context(), data[], &copyWork);
    assert(last.ok());
    assert(collect(result.value, last.value, actual[0 .. 1], written).code == Status.resourceExhausted);
    completed.value.cancel();
    assert(result.value.join(last.value, actual[], written).code == Status.ok);
    assert(actual == data);

    result.value.shutdown();
    result.value.shutdown();
    assert(result.value.join(last.value, actual[], written).code == Status.cancelled);
}

@("retain cancelled running jobs until completion")
unittest
{
    auto result = WorkerPool.create(WorkerOptions(1, 1));
    assert(result.ok());
    scope (exit)
        atomicStore(workerReleased, true);
    atomicStore(workerEntered, false);
    atomicStore(workerReleased, false);
    auto running = CancelSource.create(Context.init, Deadline.none());
    const ticket = result.value.submit(running.value.context(), [], &blockedWork);
    assert(ticket.ok() && waitForFlag(workerEntered));
    running.value.cancel();
    size_t written;
    assert(result.value.join(ticket.value, [], written).code == Status.unavailable);
    assert(result.value.submit(Context.init, [], &copyWork).error.code == Status.resourceExhausted);
    atomicStore(workerReleased, true);
    assert(collect(result.value, ticket.value, [], written).code == Status.cancelled);
    assert(result.value.join(ticket.value, [], written).code == Status.notFound);
}

@("a queued job whose deadline elapses before a worker starts reports timedOut and never runs")
unittest
{
    auto pool = WorkerPool.create(WorkerOptions(1, 2));
    assert(pool.ok());
    scope (exit)
        atomicStore(workerReleased, true);
    atomicStore(workerEntered, false);
    atomicStore(workerReleased, false);
    atomicStore(workerCopies, 0U);
    const running = pool.value.submit(Context.init, [], &blockedWork);
    assert(running.ok() && waitForFlag(workerEntered));

    auto source = CancelSource.create(Context.init, Deadline.afterMillis(50));
    assert(source.ok());
    ubyte[3] data = [1, 2, 3];
    const queued = pool.value.submit(source.value.context(), data[], &copyWork);
    assert(queued.ok());
    while (source.value.context().check().code == Status.ok)
        yieldThread();

    atomicStore(workerReleased, true);
    ubyte[3] actual;
    size_t written;
    assert(collect(pool.value, running.value, actual[], written).code == Status.ok);
    assert(collect(pool.value, queued.value, actual[], written).code == Status.timedOut);
    assert(written == 0 && actual == [0, 0, 0]);
    assert(atomicLoad(workerCopies) == 1U, "the expired job ran on a worker");
}

private struct ShutdownFixture
{
    WorkerPool pool;
}

@("join concurrent shutdown callers before reclaiming jobs")
unittest
{
    auto fixture = new ShutdownFixture;
    auto created = WorkerPool.create(WorkerOptions(1, 2));
    assert(created.ok());
    move(created.value, fixture.pool);
    scope (exit)
        destroy(fixture.pool);
    atomicStore(workerEntered, false);
    atomicStore(workerReleased, false);
    atomicStore(workerCopies, 0U);
    atomicStore(shutdownStarted, 0U);
    atomicStore(shutdownFinished, 0U);
    const live = fixture.pool.submit(Context.init, [], &blockedWork);
    assert(live.ok() && waitForFlag(workerEntered));
    const queued = fixture.pool.submit(Context.init, [], &copyWork);
    assert(queued.ok());

    WorkerThreads callers;
    assert(callers.start(2, () @safe nothrow{
            atomicOp!"+="(shutdownStarted, 1U);
            fixture.pool.shutdown();
            atomicOp!"+="(shutdownFinished, 1U);
        }));
    scope (exit)
    {
        atomicStore(workerReleased, true);
        callers.join();
    }

    import flint.conc.sys.cancellation : monotonicNanoseconds;

    const limit = Deadline.afterMillis(5_000).monotonicNanoseconds;
    while (atomicLoad(shutdownStarted) != 2 || fixture.pool.submit(Context.init, [], &copyWork)
            .error.code != Status.cancelled)
    {
        assert(monotonicNanoseconds() < limit);
        yieldThread();
    }
    assert(atomicLoad(shutdownFinished) == 0U);
    atomicStore(workerReleased, true);
    callers.join();
    assert(atomicLoad(shutdownFinished) == 2U);
    assert(atomicLoad(workerCopies) == 1U);
    size_t written;
    assert(fixture.pool.join(live.value, [], written).code == Status.cancelled);
    assert(fixture.pool.join(queued.value, [], written).code == Status.cancelled);
}

private Error invalidLength(scope const(ubyte)[] input, scope ubyte[] output, out size_t written) nothrow @nogc
{
    assert(input.length == 0);
    written = output.length + 1;
    return Error.init;
}

@("bound worker resources and validate ticket and output boundaries")
unittest
{
    const invalidWorkers = WorkerPool.create(WorkerOptions(0, 1));
    const invalidCapacity = WorkerPool.create(WorkerOptions(1, 4097));
    assert(invalidWorkers.error.code == Status.invalidArgument);
    assert(invalidCapacity.error.code == Status.invalidArgument);

    auto first = WorkerPool.create(WorkerOptions(1, 1));
    auto second = WorkerPool.create(WorkerOptions(1, 1));
    assert(first.ok() && second.ok());
    ubyte[4097] limit;
    assert(first.value.submit(Context.init, limit[], &copyWork).error.code == Status.resourceExhausted);
    assert(first.value.submit(Context.init, [], null).error.code == Status.invalidArgument);
    auto expired = CancelSource.create(Context.init, Deadline.afterMillis(0));
    assert(first.value.submit(expired.value.context(), [], &copyWork).error.code == Status.timedOut);

    const submitted = first.value.submit(Context.init, [], &invalidLength);
    assert(submitted.ok());
    size_t written;
    assert(second.value.join(submitted.value, [], written).code == Status.notFound);
    assert(collect(first.value, submitted.value, [], written).code == Status.invalidArgument);
    assert(written == 0);
    assert(first.value.join(submitted.value, [], written).code == Status.notFound);
}

@("a shared clock sample reports the same status check would at that instant")
unittest
{
    const now = Deadline.afterMillis(0).monotonicNanoseconds;
    auto source = CancelSource.create(Context.init, Deadline(now + 1_000));
    assert(source.ok());
    auto context = source.value.context();
    assert(context.statusAt(now) == Status.ok);
    assert(context.statusAt(now + 999) == Status.ok);
    assert(context.statusAt(now + 1_000) == Status.timedOut);
    assert(Context.init.statusAt(long.max - 1) == Status.ok);
    assert(Context.init.withDeadline(Deadline(now)).statusAt(now) == Status.timedOut);
    source.value.cancel();
    // The cancellation precedes the deadline, so it wins at every later sample.
    assert(context.statusAt(now + 2_000) == Status.cancelled);
    auto expired = CancelSource.create(Context.init, Deadline(0));
    expired.value.cancel();
    assert(expired.value.context().statusAt(now) == Status.timedOut);
}
