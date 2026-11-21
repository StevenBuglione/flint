module flint.conc.linearizability_test;

import core.atomic : atomicLoad, atomicOp, atomicStore;
import flint.arena : Status;
import flint.conc : Channel, QueueKind;
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

private struct History(QueueKind kind)
{
    Channel!(uint, kind) channel;
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

private void verifyHistory(QueueKind kind)(uint producers, uint consumers)
{
    auto state = new History!kind;
    auto ring = Channel!(uint, kind).create(2);
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
        }
    }

    // An accepted send followed by an empty result cannot be serialized.
    Event[3] impossible = [
        Event(1, 2, Action.receive, Status.ok, 42), Event(3, 4, Action.send, Status.ok, 100),
        Event(5, 6, Action.receive, Status.unavailable)
    ];
    assert(!anyLinearization(impossible));
}
