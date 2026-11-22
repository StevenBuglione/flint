module flint.log.concurrency_test;

import core.memory : GC;
import core.thread : Thread;
import flint.arena : Status;
import flint.log : Level, LogContext, LogOptions, Logger;
import std.json : parseJSON;
import std.string : splitLines;

private enum threadCount = 32;
private enum recordsPerThread = 64;

private struct Producer
{
    Logger logger;
    ulong id;
    ulong gcDelta;
    uint published;

    void produce() @safe nothrow @nogc
    {
        const before = GC.stats.allocatedInCurrentThread;
        foreach (_; 0 .. recordsPerThread)
        {
            const result = logger.write(Level.info, "bounded", null, LogContext(id, id + 1, id + 2, id + 3));
            if (result == Status.ok)
                ++published;
        }
        gcDelta = GC.stats.allocatedInCurrentThread - before;
    }
}

private struct Capture
{
    char[] bytes;
    size_t count;

    Status accept(scope const(char)[] line) @safe nothrow @nogc
    {
        bytes[count .. count + line.length] = line;
        count += line.length;
        return Status.ok;
    }
}

@("32 concurrent producers publish valid complete JSON without allocating on producer threads")
unittest
{
    auto capture = new Capture;
    capture.bytes = new char[threadCount * recordsPerThread * 512];
    LogOptions options;
    options.ringBytes = cast(uint) capture.bytes.length;
    options.maxRecordBytes = 512;
    options.sink = &capture.accept;
    auto created = Logger.create(options);
    assert(created.ok, created.error.message);
    scope (exit)
        created.value.close();

    auto producers = new Producer[threadCount];
    auto threads = new Thread[threadCount];
    foreach (index, ref producer; producers)
    {
        producer.logger = created.value;
        producer.id = index + 1;
        threads[index] = new Thread(&producer.produce).start();
    }
    foreach (thread; threads)
        assert(thread.join(false) is null);
    foreach (ref producer; producers)
        assert(producer.gcDelta == 0 && producer.published == recordsPerThread);
    assert(created.value.flush(5000).code == Status.ok);

    const lines = capture.bytes[0 .. capture.count].splitLines();
    assert(lines.length == threadCount * recordsPerThread);
    uint[threadCount] counts;
    string sequence;
    foreach (line; lines)
    {
        const record = parseJSON(line);
        assert(record["message"].str == "bounded");
        const id = record["requestId"].integer;
        assert(id >= 1 && id <= threadCount);
        ++counts[id - 1];
        assert(record["seq"].str > sequence);
        sequence = record["seq"].str;
    }
    foreach (count; counts)
        assert(count == recordsPerThread);
    assert(created.value.stats().delivered == lines.length);
}

// The task record is the source of truth; this TLS slot is only the cache a scheduler installs on resume.
private LogContext installedTask;

private LogContext installedTaskContext() @safe nothrow @nogc
{
    return installedTask;
}

private struct Task
{
    LogContext context;
    string tag;
    Logger logger;

    void run()
    {
        import core.thread : Fiber;

        foreach (_; 0 .. 3)
        {
            assert(logger.info(tag) == Status.ok);
            Fiber.yield();
        }
    }
}

@("two interleaved fibers and an offloaded worker retain distinct request and trace identifiers")
unittest
{
    import core.thread : Fiber;
    import std.format : format;

    auto capture = new Capture;
    capture.bytes = new char[64 * 512];
    LogOptions options;
    // Sixteen slots per producer shard hold every record of this single-threaded schedule.
    options.ringBytes = 32 * 16 * 512;
    options.maxRecordBytes = 512;
    options.sink = &capture.accept;
    options.currentContext = &installedTaskContext;
    auto created = Logger.create(options);
    assert(created.ok, created.error.message);
    scope (exit)
        created.value.close();

    auto tasks = [
        new Task(LogContext(101, 0xA1, 0xA2, 0xA3), "fiber-a", created.value),
        new Task(LogContext(202, 0xB1, 0xB2, 0xB3), "fiber-b", created.value)
    ];
    Fiber[2] fibers = [new Fiber(&tasks[0].run), new Fiber(&tasks[1].run)];
    // A deterministic round-robin schedule installs and restores each task's context around every resume.
    foreach (_; 0 .. 4)
        foreach (index, fiber; fibers)
        {
            if (fiber.state == Fiber.State.TERM)
                continue;
            installedTask = tasks[index].context;
            fiber.call();
            installedTask = LogContext.init;
        }
    assert(fibers[0].state == Fiber.State.TERM && fibers[1].state == Fiber.State.TERM);

    // Worker input carries a copy of the submitting task's context; the worker thread has no installed task.
    const workerContext = LogContext(303, 0xC1, 0xC2, 0xC3);
    auto worker = new Thread(() {
        assert(created.value.write(Level.info, "worker", null, workerContext) == Status.ok);
        assert(created.value.info("worker-unscoped") == Status.ok);
    }).start();
    assert(worker.join(false) is null);
    assert(created.value.info("standalone") == Status.ok);
    assert(created.value.flush(5000).code == Status.ok);

    const lines = capture.bytes[0 .. capture.count].splitLines();
    assert(lines.length == 9);
    string[] order;
    foreach (line; lines)
    {
        const record = parseJSON(line);
        const message = record["message"].str;
        order ~= message;
        LogContext expected;
        if (message == "fiber-a")
            expected = tasks[0].context;
        else if (message == "fiber-b")
            expected = tasks[1].context;
        else if (message == "worker")
            expected = workerContext;
        else
            assert(message == "worker-unscoped" || message == "standalone");
        assert(record["requestId"].integer == expected.requestId);
        assert(record["traceId"].str == format("%016x%016x", expected.traceIdHigh, expected.traceIdLow));
        assert(record["spanId"].str == format("%016x", expected.spanId));
    }
    assert(order[0 .. 6] == ["fiber-a", "fiber-b", "fiber-a", "fiber-b", "fiber-a", "fiber-b"]);
}
