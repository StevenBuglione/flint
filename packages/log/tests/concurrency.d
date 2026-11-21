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
