module flint.log.internal;

import core.atomic : atomicLoad, atomicOp, atomicStore, cas;
import core.thread : Thread;
import flint.arena : Error, Result, Status;
import flint.conc : Deadline;
import flint.log.encoding : RecordHeader, allowedMask, maximumRecord, measure;
import flint.log.sys.clock : timestampMillis;
import flint.log.sys.ring : Ring, producerIdentity;
import flint.log.sys.sinks : NativeSink, closeSink, joinConsumer, openSink, pauseConsumer,
    protectSink, push, startConsumer;
import flint.log.types : Field, Format, Level, LogContext, LogContextProvider, LogOptions, LogSink, LogStats;

@safe:

private enum workerShards = 32;
private enum errorCapacityBytes = 65_536;

private enum Phase : ubyte
{
    open,
    draining,
    abort,
    stopped
}

private shared ulong lastLogger;
private ulong currentConsumer;

package(flint.log) struct LoggerState
{
    private ulong id;
    private Level threshold;
    private Format format;
    private ubyte allowed;
    private uint recordLimit;
    private ulong closeMillis;
    private LogSink sink;
    private LogContextProvider provider;
    private NativeSink nativeSink;
    private Ring[] normal;
    private Ring priority;
    private char[] output;
    private Thread worker;
    private shared Phase phase;
    private shared ulong writers;
    private shared bool joined;
    private shared Status sinkFault;
    private shared ulong[5] accepted;
    private shared ulong[5] dropped;
    private shared ulong delivered;
    private shared ulong sinkFailures;
    private size_t nextShard;
    private bool previousWasPriority;

    @disable this(this);

    static Result!(LoggerState*) create(LogOptions options)
    {
        if (!validOptions(options))
            return Result!(LoggerState*)(null, Error(Status.invalidArgument, "invalid logger options"));

        const id = atomicOp!"+="(lastLogger, 1UL);
        if (id == 0)
            return Result!(LoggerState*)(null, Error(Status.resourceExhausted, "logger identities exhausted"));
        auto state = new LoggerState;
        state.id = id;
        state.threshold = options.level;
        state.format = options.format;
        state.recordLimit = options.maxRecordBytes;
        state.closeMillis = options.closeTimeoutMillis;
        state.sink = options.sink;
        state.provider = options.currentContext;
        state.allowed = allowedMask(options.allowSensitiveKeys);
        state.initializeRings(options.ringBytes);
        state.output = new char[options.maxRecordBytes];

        if (state.sink is null)
        {
            const opened = openSink(options.filePath);
            if (!opened.ok)
                return Result!(LoggerState*)(null, opened.error);
            state.nativeSink = opened.value;
        }
        scope (failure)
            closeSink(state.nativeSink);
        state.worker = startConsumer(&state.consume);
        return Result!(LoggerState*)(state);
    }

    private static bool validOptions(LogOptions options) pure nothrow @nogc
    {
        if (options.level > Level.off || options.format > Format.console
                || options.maxRecordBytes == 0 || options.maxRecordBytes > maximumRecord
                || options.ringBytes < options.maxRecordBytes)
            return false;
        if (options.filePath.length != 0 && options.sink !is null)
            return false;
        foreach (value; options.filePath)
            if (value == '\0')
                return false;
        return true;
    }

    private void initializeRings(uint bytes)
    {
        const slots = bytes / recordLimit;
        const count = slots < workerShards ? slots : workerShards;
        normal = new Ring[count];
        foreach (index, ref ring; normal)
            ring.initialize(slots / count + (index < slots % count), recordLimit);
        priority.initialize(errorCapacityBytes / recordLimit, recordLimit);
    }

    Status submit(Level level, scope const(char)[] message, scope const(Field)[] fields,
            LogContext context, bool useProvider) nothrow @nogc
    {
        if (level > Level.off)
            return Status.invalidArgument;
        if (level < threshold || level == Level.off)
            return Status.ok;

        const currentPhase = atomicLoad(phase);
        if (currentPhase != Phase.open)
            return disabledStatus();
        atomicOp!"+="(writers, 1UL);
        scope (exit)
            atomicOp!"-="(writers, 1UL);

        if (atomicLoad(phase) != Phase.open)
            return disabledStatus();

        if (useProvider && provider !is null)
            context = provider();
        const status = publishRecord(level, message, fields, context);
        if (status == Status.ok)
            atomicOp!"+="(accepted[level], 1UL);
        else
            atomicOp!"+="(dropped[level], 1UL);
        return status;
    }

    private Status disabledStatus() const nothrow @nogc
    {
        const fault = atomicLoad(sinkFault);
        return fault == Status.ok ? Status.unavailable : fault;
    }

    private Status publishRecord(Level level, scope const(char)[] message, scope const(Field)[] fields,
            LogContext context) nothrow @nogc
    {
        auto ring = level == Level.error ? &priority : chooseShard();
        if (ring.full())
            return Status.resourceExhausted;

        auto header = measure(format, level, context, message, fields, allowed, recordLimit);
        if (!header.ok)
            return header.error.code;
        const millis = timestampMillis();
        if (!millis.ok)
            return millis.error.code;
        header.value.timestamp = millis.value;
        return ring.publish(header.value, message, fields, allowed);
    }

    private Ring* chooseShard() return nothrow @nogc
    {
        const producer = producerIdentity();
        const first = cast(size_t)(producer % normal.length);
        foreach (offset; 0 .. normal.length)
        {
            const shard = (first + offset) % normal.length;
            if (normal[shard].belongsTo(producer))
                return &normal[shard];
        }
        return &normal[first];
    }

    private Ring* readyRing() return nothrow @nogc
    {
        if (!previousWasPriority && priority.ready())
        {
            previousWasPriority = true;
            return &priority;
        }

        foreach (offset; 0 .. normal.length)
        {
            const shard = (nextShard + offset) % normal.length;
            if (normal[shard].ready())
            {
                nextShard = (shard + 1) % normal.length;
                previousWasPriority = false;
                return &normal[shard];
            }
        }
        if (priority.ready())
        {
            previousWasPriority = true;
            return &priority;
        }
        return null;
    }

    private void consume() nothrow @nogc
    {
        currentConsumer = id;
        scope (exit)
        {
            closeSink(nativeSink);
            sink = null;
            currentConsumer = 0;
            atomicStore(phase, Phase.stopped);
        }

        if (sink is null && protectSink() != Status.ok)
        {
            fail(Status.ioError);
            return;
        }

        ulong sequence;
        while (atomicLoad(phase) != Phase.abort)
        {
            auto ring = readyRing();
            if (ring is null)
            {
                if (drainedAndClosing())
                    return;
                pauseConsumer();
                continue;
            }
            const status = deliver(*ring, ++sequence);
            if (status == Status.ok)
            {
                atomicOp!"+="(delivered, 1UL);
                ring.retire();
            }
            else if (atomicLoad(phase) != Phase.abort)
            {
                fail(status);
                return;
            }
        }
    }

    private bool drainedAndClosing() nothrow @nogc
    {
        // Once draining is visible no new producer can be admitted. Recheck after reading writers.
        return atomicLoad(phase) == Phase.draining && atomicLoad(writers) == 0 && readyRing() is null;
    }

    private void fail(Status status) nothrow @nogc
    {
        atomicStore(sinkFault, status);
        atomicOp!"+="(sinkFailures, 1UL);
        cas(&phase, Phase.open, Phase.abort);
        cas(&phase, Phase.draining, Phase.abort);
    }

    private Status deliver(ref Ring ring, ulong sequence) nothrow @nogc
    {
        if (sequence == 0)
            return Status.resourceExhausted;
        RecordHeader header;
        const formatted = ring.render(format, output, sequence, header);
        if (formatted != Status.ok)
            return formatted;

        const line = output[0 .. header.outputBytes];
        return sink is null ? deliverNative(header.level, line) : deliverCustom(line);
    }

    private Status deliverCustom(scope const(char)[] line) nothrow @nogc
    {
        while (atomicLoad(phase) != Phase.abort)
        {
            const status = sink(line);
            if (status != Status.unavailable)
                return status;
            pauseConsumer();
        }
        return Status.cancelled;
    }

    private Status deliverNative(Level severity, scope const(char)[] line) nothrow @nogc
    {
        while (line.length != 0 && atomicLoad(phase) != Phase.abort)
        {
            const written = push(nativeSink, severity, line);
            if (written.ok)
                line = line[written.value .. $];
            else if (written.error.code == Status.unavailable)
                pauseConsumer();
            else
                return written.error.code;
        }
        return line.length == 0 ? Status.ok : Status.cancelled;
    }

    Error flush(ulong millis) nothrow @nogc
    {
        if (currentConsumer == id)
            return Error(Status.conflict, "logger sink cannot flush its own batch");

        ulong[workerShards] target;
        foreach (index, ref ring; normal)
            target[index] = ring.published();
        const errors = priority.published();
        const expires = Deadline.afterMillis(millis).monotonicNanoseconds;
        for (;;)
        {
            const failure = atomicLoad(sinkFault);
            if (failure != Status.ok)
                return Error(failure, "logger sink failed");
            if (allDelivered(target[], errors))
                return Error.init;
            if (atomicLoad(phase) >= Phase.abort)
                return Error(Status.cancelled, "logger stopped before draining");
            if (Deadline.afterMillis(0).monotonicNanoseconds >= expires)
                return Error(Status.timedOut, "logger flush deadline elapsed");
            pauseConsumer();
        }
    }

    private bool allDelivered(scope const(ulong)[] targets, ulong errors) const nothrow @nogc
    {
        if (priority.delivered() < errors)
            return false;
        foreach (index, ref ring; normal)
            if (ring.delivered() < targets[index])
                return false;
        return true;
    }

    void close() nothrow
    {
        cas(&phase, Phase.open, Phase.draining);
        if (currentConsumer == id)
            return;

        const expires = Deadline.afterMillis(closeMillis).monotonicNanoseconds;
        while (atomicLoad(phase) == Phase.draining)
        {
            if (Deadline.afterMillis(0).monotonicNanoseconds >= expires)
            {
                cas(&phase, Phase.draining, Phase.abort);
                break;
            }
            pauseConsumer();
        }
        // An OS write may still be blocked. Its worker retains all resources until the call returns.
        const retirement = Deadline.afterMillis(5).monotonicNanoseconds;
        while (atomicLoad(phase) != Phase.stopped)
        {
            if (Deadline.afterMillis(0).monotonicNanoseconds >= retirement)
                return;
            pauseConsumer();
        }
        if (cas(&joined, false, true) && joinConsumer(worker) !is null)
            fail(Status.ioError);
    }

    LogStats stats() const nothrow @nogc
    {
        LogStats snapshot;
        foreach (index; 0 .. 5)
        {
            snapshot.accepted[index] = atomicLoad(accepted[index]);
            snapshot.dropped[index] = atomicLoad(dropped[index]);
        }
        snapshot.delivered = atomicLoad(delivered);
        snapshot.sinkFailures = atomicLoad(sinkFailures);
        return snapshot;
    }
}
