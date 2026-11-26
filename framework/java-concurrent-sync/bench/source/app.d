module app;

import core.stdc.stdio : fputc, stdout;
import flint.java.util.concurrent.locks.contracts : Condition, Lock, ReadWriteLock;
import std.traits : Parameters;

@safe:

// Derive provider types from the contract so the closure probe imports just this Java leaf.
private alias TimedWait = __traits(getOverloads, Condition, "await")[1];
private alias TimeUnit = Parameters!TimedWait[1];
private alias Date = Parameters!(Condition.awaitUntil)[0];

// This stateful test double exercises the interface dispatch paths.
private final class Probe : Lock, Condition, ReadWriteLock
{
    private bool held;
    private bool signalled;

    void lock()
    {
        held = true;
    }

    void lockInterruptibly()
    {
        lock();
    }

    bool tryLock()
    {
        if (held)
            return false;
        lock();
        return true;
    }

    bool tryLock(long time, TimeUnit unit)
    {
        return time >= 0 && unit == TimeUnit.NANOSECONDS && tryLock();
    }

    void unlock()
    {
        held = false;
    }

    Condition newCondition()
    {
        return this;
    }

    void await()
    {
        assert(signalled);
    }

    void awaitUninterruptibly()
    {
        await();
    }

    long awaitNanos(long nanosTimeout)
    {
        return signalled ? nanosTimeout : 0;
    }

    bool await(long time, TimeUnit unit)
    {
        return unit == TimeUnit.NANOSECONDS && awaitNanos(time) > 0;
    }

    bool awaitUntil(Date deadline)
    {
        return deadline !is null && signalled;
    }

    void signal()
    {
        signalled = true;
    }

    void signalAll()
    {
        signal();
    }

    Lock readLock()
    {
        return this;
    }

    Lock writeLock()
    {
        return this;
    }
}

pragma(inline, false) private bool exercise(ReadWriteLock locks, long time)
{
    auto lock = time % 2 == 0 ? locks.readLock() : locks.writeLock();
    if (!lock.tryLock(time, TimeUnit.NANOSECONDS))
        return false;
    scope (exit)
        lock.unlock();
    auto condition = lock.newCondition();
    condition.signal();
    return condition.await(time, TimeUnit.NANOSECONDS);
}

int main(string[] args)
{
    fputc(exercise(new Probe, cast(long) args.length - 1) ? '1' : '0', stdout);
    fputc('\n', stdout);
    return 0;
}
