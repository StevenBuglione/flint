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

version (Windows)
{
    /// An inbound named pipe server with a small buffer; the logger opens its client end by path.
    private struct PipeServer
    {
        void* handle;
        string path;

        @disable this(this);

        static PipeServer create(string tag) @trusted
        {
            import core.sys.windows.winbase : CreateNamedPipeW, GetCurrentProcessId,
                INVALID_HANDLE_VALUE, PIPE_ACCESS_INBOUND, PIPE_TYPE_BYTE, PIPE_WAIT;
            import std.conv : to;
            import std.utf : toUTF16z;

            PipeServer server;
            server.path = `\\.\pipe\flint-log-` ~ tag ~ "-" ~ GetCurrentProcessId().to!string;
            server.handle = CreateNamedPipeW(server.path.toUTF16z, PIPE_ACCESS_INBOUND,
                    PIPE_TYPE_BYTE | PIPE_WAIT, 1, 4096, 4096, 0, null);
            assert(server.handle != INVALID_HANDLE_VALUE);
            return server;
        }

        size_t read(scope ubyte[] buffer) @trusted
        {
            import core.sys.windows.winbase : ReadFile;

            uint count;
            assert(ReadFile(handle, buffer.ptr, cast(uint) buffer.length, &count, null));
            return count;
        }

        void close() @trusted
        {
            import core.sys.windows.winbase : CloseHandle;

            if (handle !is null)
                CloseHandle(handle);
            handle = null;
        }

        ~this()
        {
            close();
        }
    }

    @("native pipe output delivers a record larger than the pipe buffer once and completely")
    unittest
    {
        import std.json : parseJSON;

        auto server = PipeServer.create("partial");
        LogOptions options;
        options.maxRecordBytes = 65_536;
        options.ringBytes = 65_536;
        options.filePath = server.path;
        auto created = Logger.create(options);
        assert(created.ok, created.error.message);
        scope (exit)
            created.value.close();
        char[50_000] message;
        message[] = 'x';
        assert(created.value.info(message[]) == Status.ok);
        // The consumer is blocked on the full pipe until the reader drains it.
        assert(created.value.flush(10).code == Status.timedOut);

        ubyte[65_536] output;
        size_t received;
        while (received == 0 || output[received - 1] != '\n')
        {
            assert(received < output.length);
            received += server.read(output[received .. $]);
        }

        assert(created.value.flush().code == Status.ok);
        assert(parseJSON(cast(const(char)[]) output[0 .. received])["message"].str == message[]);
        assert(created.value.stats().delivered == 1);
    }

    @("the native sink reports a closed pipe as a sink failure seen by later producers")
    unittest
    {
        auto server = PipeServer.create("closed");
        LogOptions options;
        options.filePath = server.path;
        auto created = Logger.create(options);
        assert(created.ok, created.error.message);
        scope (exit)
            created.value.close();
        server.close();
        assert(created.value.info("closed pipe") == Status.ok);
        assert(created.value.flush().code == Status.ioError);
        assert(created.value.stats().sinkFailures == 1);
        assert(created.value.error("already closed") == Status.ioError);
    }
}
else
{
    @("a native sink error is reported and subsequent producers see the fault")
    unittest
    {
        LogOptions options;
        version (OSX)
        {
            // Darwin has no /dev/full. A pipe without a reader fails every write with EPIPE.
            import core.sys.posix.unistd : close;

            int[2] pipe = closeOnExecPipe();
            close(pipe[0]);
            scope (exit)
                close(pipe[1]);
            options.filePath = descriptorPath(pipe[1]);
        }
        else
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
        import core.sys.posix.fcntl : fcntl;
        import core.sys.posix.unistd : close, read;
        import std.json : parseJSON;

        int[2] pipe = closeOnExecPipe();
        version (OSX)
        {
            // Darwin has no F_SETPIPE_SZ, and opening /dev/fd/N shares the pipe's open file
            // description. Fill the nonblocking pipe so the record can only be written in parts.
            import core.sys.posix.fcntl : F_GETFL, F_SETFL, O_NONBLOCK;
            import core.sys.posix.unistd : write;

            assert(fcntl(pipe[1], F_SETFL, fcntl(pipe[1], F_GETFL) | O_NONBLOCK) == 0);
            char[4096] fill = 'p';
            size_t prefilled;
            for (ptrdiff_t written; (written = write(pipe[1], fill.ptr, fill.length)) > 0;)
                prefilled += written;
            assert(prefilled != 0);
        }
        else
        {
            enum setPipeSize = 1031;
            assert(fcntl(pipe[1], setPipeSize, 4096) == 4096);
        }
        scope (exit)
        {
            close(pipe[0]);
            close(pipe[1]);
        }
        LogOptions options;
        options.maxRecordBytes = 65_536;
        options.ringBytes = 65_536;
        options.filePath = descriptorPath(pipe[1]);
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
        version (OSX)
        {
            for (size_t drained; drained < prefilled;)
            {
                const count = read(pipe[0], output.ptr, prefilled - drained < output.length
                        ? prefilled - drained : output.length);
                assert(count > 0);
                drained += count;
            }
        }
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
        import core.sys.posix.unistd : close;

        int[2] pipe = closeOnExecPipe();
        scope (exit)
        {
            if (pipe[0] >= 0)
                close(pipe[0]);
            close(pipe[1]);
        }

        LogOptions options;
        options.filePath = descriptorPath(pipe[1]);
        auto created = Logger.create(options);
        assert(created.ok);
        scope (exit)
            created.value.close();
        close(pipe[0]);
        pipe[0] = -1;
        assert(created.value.info("closed pipe") == Status.ok);
        assert(created.value.flush().code == Status.ioError);
    }

    // A pipe whose ends are both close-on-exec. Darwin has no pipe2.
    private int[2] closeOnExecPipe() @system
    {
        int[2] ends;
        version (OSX)
        {
            import core.sys.posix.fcntl : FD_CLOEXEC, F_SETFD, fcntl;
            import core.sys.posix.unistd : pipe;

            assert(pipe(ends) == 0);
            foreach (end; ends)
                assert(fcntl(end, F_SETFD, FD_CLOEXEC) == 0);
        }
        else
        {
            import core.sys.posix.fcntl : O_CLOEXEC;
            import core.sys.posix.unistd : pipe2;

            assert(pipe2(ends, O_CLOEXEC) == 0);
        }
        return ends;
    }

    // The file-system name of one of this process's open descriptors.
    private string descriptorPath(int descriptor)
    {
        import std.conv : to;

        version (OSX)
            return "/dev/fd/" ~ descriptor.to!string;
        else
            return "/proc/self/fd/" ~ descriptor.to!string;
    }
}
