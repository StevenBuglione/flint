module flint.conc.linearizability_test;

import core.atomic : atomicLoad, atomicOp, atomicStore;
import flint.arena : Error, Result, Status;
import flint.conc : Channel, QueueKind;
import flint.conc.sys.ring : SequenceRing;
import flint.conc.sys.atomics : yieldThread;
import flint.conc.sys.workers : WorkerThreads;
import std.algorithm.mutation : move;

@safe:

private enum Action
{
    send,
    receive,
    close
}

private struct Event
{
    uint start;
    uint finish;
    Action action;
    Status result;
    uint value;
}

private struct State
{
    uint[2] values = [42, 0];
    uint count = 1;
    bool closed;

    bool accept(Event event) nothrow @nogc
    {
        final switch (event.action)
        {
        case Action.send:
            return modelSend(event);
        case Action.receive:
            return modelReceive(event);
        case Action.close:
            closed = true;
            return true;
        }
    }

    private bool modelSend(Event event) nothrow @nogc
    {
        if (closed)
            return event.result == Status.cancelled;
        if (count == values.length)
            return event.result == Status.resourceExhausted;
        values[count++] = event.value;
        return event.result == Status.ok;
    }

    private bool modelReceive(Event event) nothrow @nogc
    {
        if (count == 0)
            return event.result == (closed ? Status.cancelled : Status.unavailable);
        auto value = values[0];
        values[0] = values[1];
        --count;
        return event.result == Status.ok && event.value == value;
    }
}

private bool replay(scope const Event[] events, scope const uint[] precedes, uint pending,
        State model, ref uint searchBudget) nothrow @nogc
{
    if (pending == 0)
        return true;
    if (searchBudget == 0)
        return false;
    --searchBudget;
    foreach (index, event; events)
    {
        immutable bit = 1U << index;
        if ((bit & pending) == 0 || (precedes[index] & pending) != 0)
            continue;
        State candidate = model;
        if (candidate.accept(event) && replay(events, precedes, pending ^ bit, candidate, searchBudget))
            return true;
    }
    return false;
}

private struct ReplaySearch
{
    uint[17] precedes;
    uint budget = 250_000;
}

private bool anyLinearization(scope const Event[] events) nothrow @nogc
{
    ReplaySearch search;
    foreach (index, event; events)
    {
        foreach (other, candidate; events)
        {
            if (candidate.finish < event.start)
                search.precedes[index] |= 1U << other;
        }
    }
    return replay(events, search.precedes[0 .. events.length], (1U << events.length) - 1, State.init, search.budget);
}

// Channel counters are 64-bit. This adapter drives the same ring with an 8-bit counter, so
// concurrent histories cross sequence wrap within a few operations.
private struct ReducedQueue(QueueKind kind)
{
    SequenceRing!(uint, kind == QueueKind.mpmc, ubyte) ring;

    @disable this(this);

    static Result!ReducedQueue create(size_t capacity, ubyte initial) nothrow @nogc
    {
        Result!ReducedQueue result;
        immutable status = result.value.ring.initialize(capacity, initial);
        if (status != Status.ok)
            result.error = Error(status, "unable to create reduced ring");
        return result;
    }

    Status trySend(uint value) nothrow @nogc
    {
        return ring.send(value);
    }

    Result!uint tryReceive() nothrow @nogc
    {
        return ring.receive();
    }

    void close() nothrow @nogc
    {
        ring.close();
    }
}

private struct History(Queue)
{
    Queue channel;
    shared uint sequence;
    shared uint nextWriter;
    shared uint nextReader;
    shared bool begin;
    Event[17] events;

    void record(Action action, uint slot) nothrow @nogc
    {
        while (!atomicLoad(begin))
            yieldThread();

        ref Event event = events[slot];
        event.action = action;
        event.start = atomicOp!"+="(sequence, 1U);
        final switch (action)
        {
        case Action.send:
            event.value = slot + 100;
            event.result = channel.trySend(event.value);
            break;
        case Action.receive:
            const receipt = channel.tryReceive();
            event.result = receipt.error.code;
            event.value = receipt.value;
            break;
        case Action.close:
            channel.close();
            break;
        }
        event.finish = atomicOp!"+="(sequence, 1U);
    }
}

private void verifyHistory(QueueKind kind, bool reduced = false)(uint producers, uint consumers)
{
    static if (reduced)
    {
        alias Queue = ReducedQueue!kind;
        // The prefilled item takes the last counter value, so the first concurrent send wraps.
        auto ring = Queue.create(2, ubyte.max);
    }
    else
    {
        alias Queue = Channel!(uint, kind);
        auto ring = Queue.create(2);
    }
    auto state = new History!Queue;
    assert(ring.ok());
    move(ring.value, state.channel);
    scope (exit)
        destroy(state.channel);
    assert(state.channel.trySend(42) == Status.ok);

    WorkerThreads senders;
    WorkerThreads receivers;
    assert(senders.start(producers, () @safe nothrow @nogc {
            state.record(Action.send, atomicOp!"+="(state.nextWriter, 1U) - 1);
        }));
    assert(receivers.start(consumers, () @safe nothrow @nogc {
            state.record(Action.receive, producers + atomicOp!"+="(state.nextReader, 1U) - 1);
        }));

    atomicStore(state.begin, true);
    state.record(Action.close, producers + consumers);
    senders.join();
    receivers.join();
    assert(anyLinearization(state.events[0 .. producers + consumers + 1]));
}

@("replay concurrent histories against a bounded sequential FIFO")
unittest
{
    foreach (_; 0 .. 4)
    {
        foreach (producers; [1U, 2U, 8U])
        {
            const consumers = producers;
            verifyHistory!(QueueKind.mpsc)(producers, 1);
            verifyHistory!(QueueKind.mpmc)(producers, consumers);
            verifyHistory!(QueueKind.mpsc, true)(producers, 1);
            verifyHistory!(QueueKind.mpmc, true)(producers, consumers);
        }
    }

    // An accepted send followed by an empty result cannot be serialized.
    Event[3] impossible = [
        Event(1, 2, Action.receive, Status.ok, 42), Event(3, 4, Action.send, Status.ok, 100),
        Event(5, 6, Action.receive, Status.unavailable)
    ];
    assert(!anyLinearization(impossible));
}

private enum wrapKeys = 256;

private struct WrapTraffic(QueueKind kind)
{
    ReducedQueue!kind queue;
    shared uint producerIndex;
    shared uint[8 * wrapKeys] received;
}

private void produceAcrossWrap(QueueKind kind)(WrapTraffic!kind* state) nothrow @nogc
{
    const first = (atomicOp!"+="(state.producerIndex, 1U) - 1) * wrapKeys;
    foreach (key; first .. first + wrapKeys)
    {
        for (Status status = state.queue.trySend(key); status != Status.ok; status = state.queue.trySend(key))
        {
            assert(status == Status.resourceExhausted);
            yieldThread();
        }
    }
}

private void consumeAcrossWrap(QueueKind kind)(WrapTraffic!kind* state) nothrow @nogc
{
    uint[8] next;
    for (;;)
    {
        const result = state.queue.tryReceive();
        if (result.ok())
        {
            assert(result.value < state.received.length);
            static if (kind == QueueKind.mpsc)
                assert(next[result.value / wrapKeys]++ == result.value % wrapKeys);
            assert(atomicOp!"+="(state.received[result.value], 1U) == 1);
            continue;
        }
        if (result.error.code == Status.cancelled)
            return;
        assert(result.error.code == Status.unavailable);
        yieldThread();
    }
}

private void exerciseWrap(QueueKind kind)(uint producers, uint consumers)
{
    auto state = new WrapTraffic!kind;
    auto created = ReducedQueue!kind.create(4, 250);
    assert(created.ok());
    move(created.value, state.queue);
    scope (exit)
        destroy(state.queue);

    WorkerThreads senders;
    WorkerThreads readers;
    assert(readers.start(consumers, () @safe nothrow @nogc { consumeAcrossWrap(state); }));
    assert(senders.start(producers, () @safe nothrow @nogc { produceAcrossWrap(state); }));
    senders.join();
    state.queue.close();
    readers.join();
    foreach (key, ref count; state.received)
        assert(atomicLoad(count) == (key < producers * wrapKeys ? 1 : 0));
    assert(state.queue.tryReceive().error.code == Status.cancelled);
}

@("concurrent traffic keeps every accepted item exactly once across repeated reduced-counter wrap")
unittest
{
    // 2,048 items through four cells of an 8-bit counter wrap the sequence eight times.
    foreach (count; [1U, 2U, 8U])
    {
        exerciseWrap!(QueueKind.mpsc)(count, 1);
        exerciseWrap!(QueueKind.mpmc)(count, count);
    }
}
