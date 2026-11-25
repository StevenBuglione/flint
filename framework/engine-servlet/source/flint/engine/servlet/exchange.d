/++
Pooled private storage of one servlet exchange (coordination/notes/exchange-pool.md; owner decision (a)).

The objects user code receives, `ServletEngineRequest` and `ServletEngineResponse`, are fresh GC façades for every
exchange. Their bulky inline storage lives in a state object taken from a per-worker pool when the exchange starts and
returned when it ends. A façade remembers the state's generation at checkout. Once the exchange has completed, the
state's generation has moved on, and every façade method throws `IllegalStateException`. A retained façade can never
read or write another exchange's storage:
- On the state's owner thread, where the exchange's fibers and its return run, an acquire load and a compare are
  enough: fibers switch only at yields, and no access to pooled storage yields.
- Another thread takes the state's access lock, which the return also takes, so the check and the access are atomic
  with respect to the return.

States are individual GC blocks. A pool holds only free states and at most `poolCap` of them, and only its owner
thread touches it. A return whose generation no longer matches is ignored, so a double return or a dropped state
cannot corrupt the free list.
+/
module flint.engine.servlet.exchange;

import core.atomic : MemoryOrder, atomicLoad, atomicOp, atomicStore, cas, pause;
import core.thread : Thread;
import flint.java.lang : IllegalStateException;

@safe:

/// A state outside any pool (no worker known), owned by the calling thread, and its generation.
package(flint.engine.servlet) T freshState(T : PooledState)(out ulong generation) nothrow
{
    auto state = new T;
    PooledState base = state;
    base.owner = Thread.getThis();
    generation = atomicOp!"+="(base.generationWord, 1);
    return state;
}

/// End a state's exchange without pooling it: its façades stop working (owner decision (a)), and it is never reused.
package(flint.engine.servlet) void retire(PooledState state, ulong generation) nothrow
{
    if (state !is null)
        cas(&state.generationWord, generation, generation + 1);
}

/// Free states a worker keeps; a return beyond this drops the state to the GC.
package(flint.engine.servlet) enum size_t poolCap = 64;

/// What a pooled state needs: a generation, an owner thread and an access lock.
package(flint.engine.servlet) abstract class PooledState
{
    private shared ulong generationWord;
    // The thread inside the state other than its owner (its id), `releasing` while the owner returns it, else 0;
    // `depth` counts that thread's nested entries and is touched only by it.
    private shared ulong accessHolder;
    private uint depth;
    private Thread owner;
    private PooledState nextFree;

    /// The current generation (acquire).
    final ulong generation() const nothrow @nogc
    {
        return atomicLoad!(MemoryOrder.acq)(generationWord);
    }

    /// Clear every reference and length this state holds, for its next exchange.
    protected abstract void clear() nothrow;
}

/// One worker's free states of type `T`.
package(flint.engine.servlet) struct StatePool(T : PooledState)
{
    private T free;
    private size_t count;
    private Thread owner;

    /// A state for a new exchange on the calling thread, and its generation. A thread other than the pool's
    /// owner gets a fresh state and leaves the pool alone.
    T take(out ulong generation) nothrow
    {
        auto self = Thread.getThis();
        if (owner is null)
            owner = self;
        T state;
        if (owner is self && free !is null)
        {
            state = free;
            PooledState base = state;
            free = cast(T) base.nextFree;
            base.nextFree = null;
            --count;
        }
        else
            state = new T;
        PooledState base = state;
        base.owner = self;
        generation = atomicOp!"+="(base.generationWord, 1);
        return state;
    }

    /// Return `state` at the end of the exchange that took it with `generation`. Ignored (no-op) when the state has
    /// moved on, when the caller is not the pool's owner, or when the pool is full (the state is dropped).
    void release(T released, ulong generation) nothrow
    {
        PooledState state = released;
        if (state is null || state.generation() != generation)
            return;
        auto self = Thread.getThis();
        if (owner !is self || state.owner !is self || count >= poolCap)
        {
            // Not reused: its façades still stop working, as every completed exchange's do (owner decision (a)).
            atomicStore!(MemoryOrder.rel)(state.generationWord, generation + 1);
            return;
        }
        // Wait out any other thread inside the state (its access is a few instructions), and keep later ones out
        // while it moves on.
        while (!cas(&state.accessHolder, 0UL, releasing))
            pause();
        atomicStore!(MemoryOrder.rel)(state.generationWord, generation + 1);
        state.clear();
        atomicStore!(MemoryOrder.rel)(state.accessHolder, 0UL);
        state.nextFree = free;
        free = released;
        ++count;
    }

    /// Free states held (for tests).
    size_t held() const pure nothrow @nogc
    {
        return count;
    }
}

// The access holder while the owner returns a state; no thread has this id.
private enum ulong releasing = ulong.max;

// This thread's id for the access lock: druntime's id, or one fixed value for a thread druntime does not know.
private ulong selfId() nothrow
{
    auto self = Thread.getThis();
    ulong id = 1;
    if (self !is null)
    {
        try
            id = cast(ulong) self.id;
        catch (Exception)
            id = 1;
    }
    return id == 0 || id == releasing ? 1UL : id;
}

/++
Entered at the top of every façade method that may reach pooled storage. On the owner thread it only checks the
generation. On another thread it takes the access lock (reentrant per thread) and then checks, so the access cannot
straddle a return. A completed exchange throws `IllegalStateException`.
+/
package(flint.engine.servlet) struct Access
{
    private PooledState state;
    private bool locked;

    @disable this(this);

    this(PooledState state, ulong generation, string what)
    {
        this.state = state;
        if (state is null)
            return;
        if (Thread.getThis() is state.owner)
        {
            if (state.generation() != generation)
                throw completed(what);
            return;
        }
        const id = selfId();
        for (;;)
        {
            const holder = atomicLoad!(MemoryOrder.acq)(state.accessHolder);
            if (holder == id)
                break;
            if (holder == 0 && cas(&state.accessHolder, 0UL, id))
                break;
            pause();
        }
        ++state.depth;
        locked = true;
        if (state.generation() != generation)
        {
            leave();
            throw completed(what);
        }
    }

    ~this()
    {
        leave();
    }

    private void leave() nothrow @nogc
    {
        if (!locked)
            return;
        locked = false;
        if (--state.depth == 0)
            atomicStore!(MemoryOrder.rel)(state.accessHolder, 0UL);
    }
}

private IllegalStateException completed(string what) pure nothrow
{
    return new IllegalStateException("the " ~ what ~ " object is no longer valid: its exchange has completed");
}

version (unittest)
{
    import flint.arena : Status;
    import flint.conc : Background, startManagedBackground;

    // Run `run` on a new thread and wait for it to finish.
    private void onAnotherThread(void delegate() @safe nothrow run) nothrow
    {
        Background worker;
        try
            assert(startManagedBackground(run, worker).code == Status.ok);
        catch (Exception)
            assert(0, "could not start a test thread");
        worker.join();
    }

    // Enter `state` twice on the calling thread (the lock is reentrant per thread), then leave both.
    private bool entersTwice(PooledState state, ulong generation)
    {
        auto outer = Access(state, generation, "test");
        auto inner = Access(state, generation, "test");
        return true;
    }

    private final class TestState : PooledState
    {
        string value;
        int clears;

        protected override void clear() nothrow
        {
            value = null;
            ++clears;
        }
    }

    private bool throwsCompleted(scope void delegate() @safe action)
    {
        try
            action();
        catch (IllegalStateException)
            return true;
        return false;
    }
}

@("a returned state is cleared, reused, and its old generation's access throws on the owner thread")
unittest
{
    StatePool!TestState pool;
    ulong first;
    auto state = pool.take(first);
    state.value = "a";
    {
        auto access = Access(state, first, "test");
    }
    pool.release(state, first);
    assert(pool.held() == 1 && state.value is null && state.clears == 1);
    assert(throwsCompleted(() { auto access = Access(state, first, "test"); }));
    ulong second;
    auto again = pool.take(second);
    assert(again is state && second > first && pool.held() == 0);
    assert(throwsCompleted(() { auto access = Access(state, first, "test"); }));
    {
        auto access = Access(again, second, "test");
    }
}

@("release is idempotent per generation: a double or stale return changes nothing")
unittest
{
    StatePool!TestState pool;
    ulong generation;
    auto state = pool.take(generation);
    pool.release(state, generation);
    pool.release(state, generation);
    assert(pool.held() == 1 && state.clears == 1);
    ulong next;
    auto again = pool.take(next);
    pool.release(again, generation); // a stale generation: still checked out
    assert(pool.held() == 0 && again.clears == 1);
    pool.release(again, next);
    assert(pool.held() == 1);
}

@("the pool keeps at most poolCap free states; the rest are dropped, and their old façades still throw")
unittest
{
    StatePool!TestState pool;
    TestState[] states;
    ulong[] generations;
    foreach (_; 0 .. poolCap + 3)
    {
        ulong generation;
        states ~= pool.take(generation);
        generations ~= generation;
    }
    foreach (index, state; states)
        pool.release(state, generations[index]);
    assert(pool.held() == poolCap);
    foreach (index, state; states)
        assert(throwsCompleted(() { auto access = Access(state, generations[index], "test"); }));
}

@("another thread's access is checked under the lock: it works during the exchange and throws after it")
unittest
{
    StatePool!TestState pool;
    ulong generation;
    auto state = pool.take(generation);
    bool during, after;
    onAnotherThread(() nothrow {
        try
            during = entersTwice(state, generation);
        catch (Exception)
            during = false;
    });
    assert(during);
    pool.release(state, generation);
    onAnotherThread(() nothrow {
        try
            entersTwice(state, generation);
        catch (Exception e)
            after = cast(IllegalStateException) e !is null;
    });
    assert(after);
}

@("a state taken off its pool's owner thread is fresh, and its return only retires it")
unittest
{
    StatePool!TestState pool;
    ulong mine;
    auto own = pool.take(mine); // this thread becomes the owner
    pool.release(own, mine);
    assert(pool.held() == 1);
    TestState foreign;
    ulong foreignGeneration;
    onAnotherThread(() nothrow {
        foreign = pool.take(foreignGeneration);
        pool.release(foreign, foreignGeneration);
    });
    assert(foreign !is own && pool.held() == 1);
    assert(throwsCompleted(() { auto access = Access(foreign, foreignGeneration, "test"); }));
}
