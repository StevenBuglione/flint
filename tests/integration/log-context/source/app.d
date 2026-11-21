module app;

import core.lifetime : move;
import core.thread : Thread;
import core.time : msecs;
import flint.arena : Error, Status;
import flint.conc : Context, Deadline, WorkerOptions, WorkerPool;
import flint.log : Format, Level, LogContext, Logger, LogOptions;
import flint.reactor : Backend, Reactor, ReactorOptions, TaskContext;
import std.array : split;
import std.file : mkdir, readText, rmdirRecurse, tempDir;
import std.json : JSONValue, parseJSON;
import std.path : buildPath;
import std.stdio : writeln;
import std.uuid : randomUUID;

@safe:

private __gshared Logger* installed;

// SAFETY: The main thread publishes a GC-owned facade before creating either worker. It clears the
// root only after both workers have joined. Each worker uses the Logger's synchronized producer API.
private void install(Logger* logger) @trusted nothrow @nogc
{
    installed = logger;
}

// SAFETY: Worker startup and join delimit the stable lifetime of this fixture's GC-owned facade.
private Logger* logger() @trusted nothrow @nogc
{
    return installed;
}

private LogContext contextProvider() nothrow @nogc
{
    auto reactor = Reactor.current();
    const current = reactor.currentTask();
    if (!current.ok)
        return LogContext.init;
    return LogContext(current.value.requestId, current.value.traceIdHigh, current.value.traceIdLow,
            current.value.spanId);
}

private TaskContext task(ulong requestId, ulong high, ulong low, ulong span) nothrow @nogc
{
    auto result = TaskContext(requestId);
    result.traceIdHigh = high;
    result.traceIdLow = low;
    result.spanId = span;
    return result;
}

private void first() nothrow @nogc
{
    auto reactor = Reactor.current();
    mustEqual(logger().info("first-enter"), Status.ok);
    mustEqual(reactor.yieldUntil(Deadline.afterMillis(25)).code, Status.ok);
    mustEqual(logger().info("first-leave"), Status.ok);
    reactor.stop();
}

private void second() nothrow @nogc
{
    auto reactor = Reactor.current();
    mustEqual(logger().info("second-enter"), Status.ok);
    mustEqual(reactor.yieldUntil(Deadline.afterMillis(5000)).code, Status.cancelled);
    mustEqual(logger().info("second-leave"), Status.ok);
}

private void mustEqual(Status actual, Status expected) nothrow @nogc
{
    if (actual != expected)
        assert(0, "unexpected fixture status");
}

private ulong field(scope const(ubyte)[] input, size_t offset) pure nothrow @nogc
{
    ulong result;
    foreach (position; 0 .. ulong.sizeof)
        result |= cast(ulong)(input[offset + position]) << (8 * position);
    return result;
}

private Error offloaded(scope const(ubyte)[] input, scope ubyte[], out size_t written) nothrow @nogc
{
    if (input.length != 4 * ulong.sizeof)
        return Error(Status.invalidArgument, "invalid worker context size");
    const context = LogContext(field(input, 0), field(input, 8), field(input, 16), field(input, 24));
    const status = logger().write(Level.info, "offloaded", null, context);
    return Error(status);
}

private struct Expected
{
    string message;
    long request;
    string trace;
    string span;
}

private bool matchingLogs(string filename)
{
    JSONValue[string] records;
    foreach (line; readText(filename).split("\n"))
    {
        if (line.length == 0)
            continue;
        auto record = parseJSON(line);
        const message = record["message"].str;
        if (message in records)
            return false;
        records[message] = move(record);
    }
    const firstTrace = "000000000000000d000000000000000e";
    const secondTrace = "00000000000000230000000000000024";
    const workerTrace = "0000000000000039000000000000003a";
    const Expected[5] expected = [
        Expected("first-enter", 12, firstTrace, "000000000000000f"),
        Expected("first-leave", 12, firstTrace, "000000000000000f"),
        Expected("second-enter", 34, secondTrace, "0000000000000025"),
        Expected("second-leave", 34, secondTrace, "0000000000000025"),
        Expected("offloaded", 56, workerTrace, "000000000000003b"),
    ];
    if (records.length != expected.length)
        return false;
    foreach (ref entry; expected)
    {
        const record = entry.message in records;
        if (record is null || (*record)["requestId"].integer != entry.request
                || (*record)["traceId"].str != entry.trace || (*record)["spanId"].str != entry.span)
            return false;
    }
    return true;
}

private bool exerciseFibers()
{
    ReactorOptions reactorOptions;
    reactorOptions.backend = Backend.epoll;
    reactorOptions.cores = 1;
    reactorOptions.fiberPoolSize = 2;
    auto loop = Reactor.create(reactorOptions);
    if (!loop.ok || loop.value.post(0, &first, task(12, 13, 14, 15)).code != Status.ok
            || loop.value.post(0, &second, task(34, 35, 36, 37)).code != Status.ok)
        return false;
    return loop.value.run().code == Status.ok;
}

private bool exerciseWorker()
{
    auto pool = WorkerPool.create(WorkerOptions(1, 2));
    if (!pool.ok)
        return false;
    scope (exit)
        pool.value.shutdown();
    ubyte[32] metadata;
    metadata[0] = 56;
    metadata[8] = 57;
    metadata[16] = 58;
    metadata[24] = 59;
    const ticket = pool.value.submit(Context.init, metadata[], &offloaded);
    if (!ticket.ok)
        return false;
    metadata[] = 0;
    const deadline = Deadline.afterMillis(2000);
    for (;;)
    {
        size_t written;
        const result = pool.value.join(ticket.value, null, written);
        if (result.code == Status.ok)
            return written == 0;
        const now = Deadline.afterMillis(0).monotonicNanoseconds;
        if (result.code != Status.unavailable || now >= deadline.monotonicNanoseconds)
            return false;
        Thread.sleep(1.msecs);
    }
}

int main()
{
    const directory = buildPath(tempDir(), "flint-log-context-" ~ randomUUID().toString());
    mkdir(directory);
    scope (exit)
        rmdirRecurse(directory);
    const filename = buildPath(directory, "records.jsonl");
    LogOptions options;
    options.format = Format.json;
    options.filePath = filename;
    options.currentContext = &contextProvider;
    auto created = Logger.create(options);
    if (!created.ok)
        return 1;
    auto sink = new Logger;
    *sink = move(created.value);
    install(sink);
    scope (exit)
    {
        sink.close();
        install(null);
    }
    if (!exerciseFibers())
        return 2;
    if (!exerciseWorker())
        return 3;
    if (sink.flush().code != Status.ok)
        return 4;
    sink.close();
    if (!matchingLogs(filename))
        return 5;
    writeln("Two overlapping fibers and one offloaded worker preserved their own log context.");
    return 0;
}
