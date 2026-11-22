module flint.log.lifecycle_test;

import core.atomic : atomicLoad, atomicStore;
import flint.arena : Status;
import flint.log : Level, LogOptions, Logger;

private shared bool hold;

@("normal and error reserves saturate independently and close drains accepted records")
unittest
{
    atomicStore(hold, true);
    LogOptions options;
    options.ringBytes = 4096;
    options.sink = (scope const(char)[] line) @safe nothrow @nogc {
        assert(line[$ - 1] == '\n');
        return atomicLoad(hold) ? Status.unavailable : Status.ok;
    };
    auto logger = Logger.create(options).value;
    scope (exit)
        logger.close();

    assert(logger.info("fills the normal shard") == Status.ok);
    assert(logger.info("normal overflow") == Status.resourceExhausted);
    foreach (_; 0 .. 16)
        assert(logger.error("reserved") == Status.ok);
    assert(logger.error("priority overflow") == Status.resourceExhausted);
    assert(logger.flush(10).code == Status.timedOut);
    atomicStore(hold, false);
    auto second = logger;
    second.close();
    logger.close();
    assert(logger.stats().delivered == 17);
    assert(logger.stats().dropped[Level.info] == 1 && logger.stats().dropped[Level.error] == 1);
    assert(logger.info("closed") == Status.unavailable);
}

@("a drain deadline abandons a blocked sink and leaves flush able to report loss")
unittest
{
    LogOptions options;
    options.closeTimeoutMillis = 15;
    options.sink = (scope const(char)[] line) @safe nothrow @nogc {
        assert(line.length != 0);
        return Status.unavailable;
    };
    auto logger = Logger.create(options).value;
    assert(logger.warn("pending") == Status.ok);
    logger.close();
    assert(logger.flush(0).code == Status.cancelled);
    assert(logger.stats().delivered == 0);
}

@("a native sink error is reported and subsequent producers see the fault")
unittest
{
    LogOptions options;
    options.filePath = "/dev/full";
    auto created = Logger.create(options);
    assert(created.ok, created.error.message);
    scope (exit)
        created.value.close();

    assert(created.value.info("device exhausts writes") == Status.ok);
    assert(created.value.flush().code == Status.ioError);
    assert(created.value.stats().sinkFailures == 1);
    assert(created.value.error("already closed") == Status.ioError);
}

@("native pipe output resumes a partial record without rewriting its accepted prefix")
unittest
{
    import core.sys.posix.fcntl : O_CLOEXEC, fcntl;
    import core.sys.posix.unistd : close, pipe2, read;
    import std.conv : to;
    import std.json : parseJSON;

    int[2] pipe;
    assert(pipe2(pipe, O_CLOEXEC) == 0);
    enum setPipeSize = 1031;
    assert(fcntl(pipe[1], setPipeSize, 4096) == 4096);
    scope (exit)
    {
        close(pipe[0]);
        close(pipe[1]);
    }
    LogOptions options;
    options.maxRecordBytes = 65_536;
    options.ringBytes = 65_536;
    options.filePath = "/proc/self/fd/" ~ pipe[1].to!string;
    auto created = Logger.create(options);
    assert(created.ok, created.error.message);
    scope (exit)
        created.value.close();
    char[50_000] message;
    message[] = 'x';
    assert(created.value.info(message[]) == Status.ok);
    assert(created.value.flush(10).code == Status.timedOut);

    char[65_536] output;
    size_t received;
    while (received == 0 || output[received - 1] != '\n')
    {
        assert(received < output.length);
        const count = read(pipe[0], &output[received], output.length - received);
        assert(count > 0);
        received += count;
    }

    assert(created.value.flush().code == Status.ok);
    assert(parseJSON(output[0 .. received])["message"].str == message[]);
    assert(created.value.stats().delivered == 1);
}

@("the native sink reports a closed pipe without delivering SIGPIPE to the caller")
unittest
{
    import core.sys.posix.fcntl : O_CLOEXEC;
    import core.sys.posix.unistd : close, pipe2;
    import std.conv : to;

    int[2] pipe;
    assert(pipe2(pipe, O_CLOEXEC) == 0);
    scope (exit)
    {
        if (pipe[0] >= 0)
            close(pipe[0]);
        close(pipe[1]);
    }

    LogOptions options;
    options.filePath = "/proc/self/fd/" ~ pipe[1].to!string;
    auto created = Logger.create(options);
    assert(created.ok);
    scope (exit)
        created.value.close();
    close(pipe[0]);
    pipe[0] = -1;
    assert(created.value.info("closed pipe") == Status.ok);
    assert(created.value.flush().code == Status.ioError);
}
