module app;

import core.sync.mutex : Mutex;
import flint.arena : Error, Result, Status;
import probe : check, printChecksum, runProbe;

@safe:

private struct ReferenceQueue
{
    private Mutex lock;
    private uint[] storage;
    private size_t head;
    private size_t filled;
    private bool closed;

    void prepare(size_t capacity)
    {
        lock = new Mutex;
        storage = new uint[capacity];
    }

    Status offer(uint word) nothrow @nogc
    {
        lock.lock_nothrow();
        scope (exit)
            lock.unlock_nothrow();

        if (closed)
            return Status.cancelled;
        if (filled == storage.length)
            return Status.resourceExhausted;
        storage[(head + filled) % storage.length] = word;
        ++filled;
        return Status.ok;
    }

    Result!uint take() nothrow @nogc
    {
        lock.lock_nothrow();
        scope (exit)
            lock.unlock_nothrow();

        if (filled == 0)
            return Result!uint(0, Error(closed ? Status.cancelled : Status.unavailable));
        const word = storage[head];
        head = (head + 1) % storage.length;
        --filled;
        return Result!uint(word);
    }

    void close() nothrow @nogc
    {
        lock.lock_nothrow();
        closed = true;
        lock.unlock_nothrow();
    }
}

private Error roundTrip(scope const(ubyte)[] input, scope ubyte[] output, out size_t written) nothrow @nogc
{
    output[0 .. input.length] = input[];
    written = input.length;
    return Error.init;
}

private ulong cancelled()
{
    // The provider-free control omits the Flint cancellation operation.
    return 2_048;
}

void main(string[] args)
{
    check(args.length == 1 || (args.length == 2 && args[1] == "--measure"));
    const checksum = runProbe!(ReferenceQueue, ReferenceQueue)(&roundTrip, &cancelled, args.length == 2);
    printChecksum(checksum);
}
