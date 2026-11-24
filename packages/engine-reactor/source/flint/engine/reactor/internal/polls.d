/++
One-shot readiness polls on descriptors the reactor does not own (a database driver's socket), each resuming the task
fiber that waits on it.

A poll is one io_uring POLL_ADD whose completion carries the poll's token, so the owner wakes the waiting fiber
straight from its completion. The nested native watch (`watchNative`) reports the same readiness through an epoll
descriptor: its completion costs an `epoll_wait` to learn which descriptor is ready, and a level-triggered watch
keeps reporting a readable descriptor until the fiber reads it. A poll is armed when the fiber parks and gone when
it resumes, so no watch outlives the wait.

An entry stays reserved until the kernel's final completion for its poll, including after the waiter left early
(deadline, cancellation, shutdown) and asked the kernel to cancel it, so a token is never reused while the kernel
may still complete it.
+/
module flint.engine.reactor.internal.polls;

import flint.engine.reactor.types : TaskWaker;

@safe:

/// The top token bit marks a descriptor poll; operation tokens stay below it (`operations.maxGeneration`).
package(flint.engine.reactor) enum ulong pollTokenBit = 1UL << 63;
private enum indexBits = 16;
private enum ulong indexMask = (1UL << indexBits) - 1;
/// Generations stay below the token bit once shifted past the index.
private enum ulong maxGeneration = (pollTokenBit >> indexBits) - 1;

/// Whether `token` names a descriptor poll rather than an operation or one of the owner's own polls.
package(flint.engine.reactor) bool isPollToken(ulong token) pure nothrow @nogc
{
    return (token & pollTokenBit) != 0;
}

/// Where a poll stands.
package(flint.engine.reactor) enum PollState : ubyte
{
    /// No poll: the entry can be reserved.
    free,
    /// Submitted; the kernel has not completed it and its waiter still waits.
    armed,
    /// The kernel completed it while its waiter still waited; the waiter releases it.
    fired,
    /// Its waiter left before the completion; the completion frees it.
    abandoned,
}

private struct Entry
{
    ulong generation;
    TaskWaker waker;
    PollState state;
    /// A cancellation for the poll was submitted.
    bool cancelSent;
}

/// One owner's descriptor polls: a fixed table, used below `used`.
package(flint.engine.reactor) struct DescriptorPolls
{
    /// Most polls an owner holds at once: one per parked fiber, plus abandoned polls awaiting their completion.
    enum capacity = 256;

    private Entry[capacity] entries;
    private uint used;
    /// Polls the kernel still holds (armed or abandoned).
    uint outstanding;

    /// Reserve an entry that resumes `waker` and return its token, or zero when every entry is in use.
    ulong reserve(TaskWaker waker) nothrow @nogc
    {
        foreach (index; 0 .. capacity)
        {
            auto entry = &entries[index];
            if (entry.state != PollState.free)
                continue;
            entry.generation = entry.generation == maxGeneration ? 1 : entry.generation + 1;
            entry.waker = waker;
            entry.state = PollState.armed;
            entry.cancelSent = false;
            ++outstanding;
            if (index >= used)
                used = cast(uint) index + 1;
            return tokenOf(index);
        }
        return 0;
    }

    /// Return a reserved entry whose poll the kernel never accepted.
    void unreserve(ulong token) nothrow @nogc
    {
        auto entry = find(token);
        if (entry is null || entry.state != PollState.armed)
            return;
        free(*entry);
    }

    /// Where `token`'s poll stands; `free` for a stale token.
    PollState stateOf(ulong token) const nothrow @nogc
    {
        const index = token & indexMask;
        if (!isPollToken(token) || index >= used || entries[index].generation != generationOf(token))
            return PollState.free;
        return entries[index].state;
    }

    /// The waiter is done with a fired poll.
    void release(ulong token) nothrow @nogc
    {
        auto entry = find(token);
        if (entry !is null && entry.state == PollState.fired)
            free(*entry);
    }

    /// The waiter leaves while the kernel still holds the poll: its completion frees the entry. True when the caller
    /// must submit a cancellation for it.
    bool abandon(ulong token) nothrow @nogc
    {
        auto entry = find(token);
        if (entry is null)
            return false;
        if (entry.state == PollState.fired)
        {
            free(*entry);
            return false;
        }
        if (entry.state != PollState.armed)
            return false;
        entry.state = PollState.abandoned;
        return !entry.cancelSent;
    }

    /// Record that a cancellation for `token`'s poll was submitted.
    void cancelling(ulong token) nothrow @nogc
    {
        auto entry = find(token);
        if (entry !is null)
            entry.cancelSent = true;
    }

    /// The kernel's final completion of `token`'s poll. Returns the waker to resume, or an empty one when the waiter
    /// already left (the entry is then free) or the token is stale.
    TaskWaker complete(ulong token) nothrow @nogc
    {
        auto entry = find(token);
        if (entry is null)
            return TaskWaker.init;
        if (entry.state == PollState.abandoned)
        {
            free(*entry);
            return TaskWaker.init;
        }
        if (entry.state != PollState.armed)
            return TaskWaker.init;
        --outstanding;
        entry.state = PollState.fired;
        return entry.waker;
    }

    /// Each poll the kernel still holds and no cancellation was submitted for (shutdown): `cancel` submits one and
    /// returns whether it did.
    void cancelAll(scope bool delegate(ulong token) nothrow @nogc @safe cancel) nothrow @nogc
    {
        foreach (index; 0 .. used)
        {
            auto entry = &entries[index];
            if ((entry.state == PollState.armed || entry.state == PollState.abandoned) && !entry.cancelSent)
                entry.cancelSent = cancel(tokenOf(index));
        }
    }

    private ulong tokenOf(size_t index) const nothrow @nogc
    {
        return pollTokenBit | (entries[index].generation << indexBits) | index;
    }

    private static ulong generationOf(ulong token) pure nothrow @nogc
    {
        return (token & ~pollTokenBit) >> indexBits;
    }

    private Entry* find(ulong token) return nothrow @nogc
    {
        const index = token & indexMask;
        if (!isPollToken(token) || index >= used || entries[index].generation != generationOf(token))
            return null;
        return &entries[index];
    }

    private void free(ref Entry entry) nothrow @nogc
    {
        if (entry.state == PollState.armed || entry.state == PollState.abandoned)
            --outstanding;
        entry.state = PollState.free;
        entry.waker = TaskWaker.init;
        entry.cancelSent = false;
        while (used != 0 && entries[used - 1].state == PollState.free)
            --used;
    }
}

@("a poll is fired once by its completion, and an abandoned one is freed only by its completion")
unittest
{
    DescriptorPolls polls;
    const waker = TaskWaker(0, 1, 7);
    const first = polls.reserve(waker);
    assert(isPollToken(first) && polls.outstanding == 1 && polls.stateOf(first) == PollState.armed);
    assert(polls.complete(first) == waker && polls.stateOf(first) == PollState.fired && polls.outstanding == 0);
    // A duplicate completion wakes nobody.
    assert(polls.complete(first) == TaskWaker.init);
    polls.release(first);
    assert(polls.stateOf(first) == PollState.free);

    // The waiter leaves first: the cancellation is requested once and the completion frees the entry.
    const second = polls.reserve(waker);
    assert(second != first, "a reused entry gets a new generation");
    assert(polls.abandon(second) && polls.stateOf(second) == PollState.abandoned);
    polls.cancelling(second);
    assert(!polls.abandon(second));
    assert(polls.reserve(waker) != second);
    assert(polls.complete(second) == TaskWaker.init && polls.stateOf(second) == PollState.free);
    assert(polls.outstanding == 1);
}

@("a fired poll abandoned by its waiter is freed at once, and a stale token touches nothing")
unittest
{
    DescriptorPolls polls;
    const token = polls.reserve(TaskWaker(0, 2, 3));
    cast(void) polls.complete(token);
    assert(!polls.abandon(token), "the kernel already completed it: nothing to cancel");
    assert(polls.stateOf(token) == PollState.free && polls.outstanding == 0);
    assert(polls.complete(token) == TaskWaker.init);
    assert(polls.stateOf(token ^ (1UL << 20)) == PollState.free);
    assert(!isPollToken(token & ~pollTokenBit));
}

@("the table is bounded, shutdown cancels each held poll once, and an unsubmitted poll is returned")
unittest
{
    DescriptorPolls polls;
    ulong[DescriptorPolls.capacity] tokens;
    foreach (ref token; tokens)
        token = polls.reserve(TaskWaker(0, 1, 1));
    assert(polls.reserve(TaskWaker(0, 1, 1)) == 0 && polls.outstanding == DescriptorPolls.capacity);
    polls.unreserve(tokens[$ - 1]);
    assert(polls.outstanding == DescriptorPolls.capacity - 1);
    size_t cancels;
    polls.cancelAll((ulong) { ++cancels; return true; });
    polls.cancelAll((ulong) { ++cancels; return true; });
    assert(cancels == DescriptorPolls.capacity - 1);
}
