module app;

import core.time : MonoTime;
import flint.arena : Error, Result, Status;
import flint.conc : CancelSource, Channel, Context, Deadline, QueueKind, WorkerOptions, WorkerPool;
import core.lifetime : move;
import probe : check, pauseWorker, printCancellation, printChecksum, runProbe;

@safe:

private struct Adapter(QueueKind kind)
{
    private Channel!(uint, kind) channel;

    void prepare(size_t capacity)
    {
        auto result = Channel!(uint, kind).create(capacity);
        check(result.ok());
        move(result.value, channel);
    }

    Status offer(uint word) nothrow @nogc
    {
        return channel.trySend(word);
    }

    Result!uint take() nothrow @nogc
    {
        return channel.tryReceive();
    }

    void close() nothrow @nogc
    {
        channel.close();
    }
}

private WorkerPool* currentPool;

private Error copyBytes(scope const(ubyte)[] input, scope ubyte[] output, out size_t written) nothrow @nogc
{
    output[0 .. input.length] = input[];
    written = input.length;
    return Error.init;
}

private Error roundTrip(scope const(ubyte)[] input, scope ubyte[] output, out size_t written) nothrow @nogc
{
    const sent = currentPool.submit(Context.init, input, &copyBytes);
    if (!sent.ok())
        return sent.error;

    const began = MonoTime.currTime;
    for (;;)
    {
        const result = currentPool.join(sent.value, output, written);
        if (result.code != Status.unavailable)
            return result;
        if ((MonoTime.currTime - began).total!"nsecs" >= 5_000_000_000)
            return Error(Status.timedOut);
        pauseWorker();
    }
}

private ulong cancelled()
{
    auto source = CancelSource.create(Context.init, Deadline.none());
    check(source.ok());
    const context = source.value.context();
    ulong observed;
    foreach (_; 0 .. 1_024)
    {
        check(context.check().code == Status.ok);
        observed += 1;
    }
    source.value.cancel();
    foreach (_; 0 .. 1_024)
    {
        check(context.check().code == Status.cancelled);
        observed += 1;
    }
    return observed;
}

void main(string[] args)
{
    check(args.length == 1 || (args.length == 2 && args[1] == "--measure"));
    auto pool = WorkerPool.create(WorkerOptions(1, 2));
    check(pool.ok());
    currentPool = new WorkerPool;
    move(pool.value, *currentPool);
    scope (exit)
    {
        currentPool.shutdown();
        currentPool = null;
    }

    const checksum = runProbe!(Adapter!(QueueKind.mpsc), Adapter!(QueueKind.mpmc))(&roundTrip,
            &cancelled, args.length == 2);
    if (args.length == 2)
    {
        ulong checked;
        long elapsed;
        const began = MonoTime.currTime;
        do
        {
            checked += cancelled();
            elapsed = (MonoTime.currTime - began).total!"nsecs";
        }
        while (elapsed < 100_000_000);
        printCancellation(checked, elapsed);
    }
    printChecksum(checksum);
}
