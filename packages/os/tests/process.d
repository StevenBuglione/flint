module flint.os.process_test;

import flint.arena : Status;
import flint.conc : CancelSource, Context, Deadline;
import flint.os : EnvVar, ProcessOptions, run, stream;

@("missing executable and the child's exit 127 are distinct")
unittest
{
    Context context;
    const missing = run(context, ["flint-test-nonexistent-command-99817"]);
    assert(missing.error.code == Status.notFound);
    const exited = run(context, ["/bin/sh", "-c", "exit 127"]);
    assert(exited.ok && exited.value.code == 127 && !exited.value.signalled && !exited.value.timedOut);
}

@("argv, scoped environment and child working directory reach the executable directly")
unittest
{
    import std.file : getcwd;

    Context context;
    ProcessOptions options;
    options.workingDirectory = "/";
    options.inheritEnvironment = false;
    options.environment = [EnvVar("FLINT_TEST", "text with spaces")];
    const result = run(context, [
        "/bin/sh", "-c", "printf '%s\\n' \"$1\" \"$2\" \"$PWD\" \"$FLINT_TEST\"", "flint-test",
        "one \"two words\"", "; $(false)"
    ], options);
    assert(result.ok, result.error.message);
    assert(result.value.code == 0);
    assert(result.value.stdoutBytes == cast(ubyte[]) "one \"two words\"\n; $(false)\n/\ntext with spaces\n");
    assert(getcwd() != "/");
    assert(result.value.stderrBytes.length == 0);
}

@("the two output pipes drain independently under concurrent writes")
unittest
{
    Context context;
    size_t stdoutCount, stderrCount;
    const result = stream(context, [
        "/bin/sh", "-c", "head -c 10485760 /dev/zero & head -c 10485760 /dev/zero >&2 & wait"
    ], (scope const(ubyte)[] bytes) @safe {
        foreach (value; bytes)
            assert(value == 0);
        stdoutCount += bytes.length;
    }, (scope const(ubyte)[] bytes) @safe {
        foreach (value; bytes)
            assert(value == 0);
        stderrCount += bytes.length;
    });
    assert(result.ok, result.error.message);
    assert(result.value.code == 0);
    assert(stdoutCount == 10_485_760 && stderrCount == stdoutCount);
}

@("capture overflow terminates the command without growing the retained output")
unittest
{
    Context context;
    ProcessOptions options;
    options.maxCaptureBytes = 7;
    options.terminateGraceNanos = 10_000_000;
    const result = run(context, ["/bin/sh", "-c", "printf abcd; printf EFGH >&2"], options);
    assert(result.error.code == Status.resourceExhausted);
    assert(result.value.stdoutBytes.length + result.value.stderrBytes.length <= 7);
}

@("deadline and explicit cancellation preserve distinct outcomes")
unittest
{
    auto source = CancelSource.create(Context.init, Deadline.afterMillis(40));
    assert(source.ok);
    auto context = source.value.context();
    ProcessOptions options;
    options.terminateGraceNanos = 10_000_000;
    const timedOut = run(context, ["/bin/sh", "-c", "sleep 10 & wait"], options);
    assert(timedOut.ok && timedOut.value.timedOut && timedOut.value.signalled);

    auto manual = CancelSource.create(Context.init, Deadline.none);
    assert(manual.ok);
    manual.value.cancel();
    auto cancelled = manual.value.context();
    assert(run(cancelled, ["/bin/sh", "-c", "exit 0"], options).error.code == Status.cancelled);
}

@("invalid native argument strings are rejected before launch")
unittest
{
    Context context;
    assert(run(context, []).error.code == Status.invalidArgument);
    assert(run(context, ["/bin/sh\0tail"]).error.code == Status.invalidArgument);
    ProcessOptions options;
    options.environment = [EnvVar("A=B", "bad")];
    assert(run(context, ["/bin/sh"], options).error.code == Status.invalidArgument);
    options.environment = [];
    options.workingDirectory = "/\0bad";
    assert(run(context, ["/bin/sh"], options).error.code == Status.invalidArgument);
}

@("cancellation kills the entire owned group and reaps the waitable child")
unittest
{
    import core.stdc.errno : ECHILD, errno;
    import core.sys.posix.sys.wait : WNOHANG, waitpid;
    import core.thread : Thread;
    import core.time : msecs;
    import std.conv : to;
    import std.file : exists, readText;
    import std.string : split;

    auto source = CancelSource.create(Context.init, Deadline.none);
    assert(source.ok);
    auto context = source.value.context();
    ProcessOptions options;
    options.terminateGraceNanos = 10_000_000;
    char[] receipt;
    auto cancelled = stream(context, [
        "/bin/sh", "-c", "trap '' TERM; sleep 30 & printf '%s %s\\n' \"$$\" \"$!\"; wait"
    ], (scope const(ubyte)[] data) @safe {
        receipt ~= cast(const(char)[]) data;
        if (receipt[$ - 1] == '\n')
            source.value.cancel();
    }, null, options);
    assert(cancelled.error.code == Status.cancelled && cancelled.value.signalled);

    const fields = receipt.split();
    assert(fields.length == 2);
    const parent = fields[0].to!int;
    assert(waitpid(parent, null, WNOHANG) == -1 && errno == ECHILD);

    const descendant = "/proc/" ~ fields[1].idup ~ "/stat";
    foreach (_; 0 .. 1000)
    {
        if (!exists(descendant))
            return;
        try
        {
            const status = readText(descendant);
            if (status.split(") ")[1][0] == 'Z')
                return;
        }
        catch (Exception)
        {
            if (!exists(descendant))
                return;
        }
        Thread.sleep(1.msecs);
    }
    assert(0, "descendant survived cancellation");
}

@("a stalled sink does not keep the child alive")
unittest
{
    import std.file : exists;
    import std.string : strip;

    Context context;
    ProcessOptions options;
    options.sinkStallNanos = 25_000_000;
    options.terminateGraceNanos = 10_000_000;
    bool retiredBeforeCallbackReturn;
    auto stalled = stream(context, ["/bin/sh", "-c", "printf '%s\\n' \"$$\"; sleep 30"],
            (scope const(ubyte)[] data) @safe {
        const processPath = "/proc/" ~ (cast(const(char)[]) data).strip().idup;
        const limit = Deadline.afterMillis(2_000).monotonicNanoseconds;
        while (Deadline.afterMillis(0).monotonicNanoseconds < limit)
        {
            if (!exists(processPath))
            {
                retiredBeforeCallbackReturn = true;
                break;
            }
        }
    }, null, options);
    assert(retiredBeforeCallbackReturn);
    assert(stalled.error.code == Status.timedOut && !stalled.value.timedOut);
}

@("a throwing sink propagates the same exception once after reaping")
unittest
{
    import std.file : exists;
    import std.string : strip;

    Context context;
    ProcessOptions options;
    options.terminateGraceNanos = 10_000_000;
    Exception expected = new Exception("test callback exception");
    string path;
    uint calls;
    try
    {
        const unexpected = stream(context, ["/bin/sh", "-c", "printf '%s\\n' \"$$\"; sleep 30"],
                (scope const(ubyte)[] data) @safe {
            ++calls;
            path = "/proc/" ~ (cast(const(char)[]) data).strip().idup;
            throw expected;
        }, null, options);
        assert(0, "sink exception was suppressed: " ~ unexpected.error.message);
    }
    catch (Exception caught)
    {
        assert(caught is expected && calls == 1);
        assert(!exists(path));
    }
}

@("the child resolves its own PATH and does not inherit unrelated descriptors")
unittest
{
    import core.sys.posix.fcntl : F_DUPFD, O_RDONLY, fcntl, open;
    import core.sys.posix.unistd : close;
    import std.conv : to;

    const original = open("/dev/null", O_RDONLY);
    assert(original >= 0);
    scope (exit)
        close(original);
    const descriptor = fcntl(original, F_DUPFD, 128);
    assert(descriptor >= 128);
    scope (exit)
        close(descriptor);

    ProcessOptions options;
    options.workingDirectory = "/bin";
    options.terminateGraceNanos = 0;
    options.inheritEnvironment = false;
    options.environment = [EnvVar("PATH", "/flint-nonexistent-search-directory")];
    Context context;
    assert(run(context, ["sh", "-c", "exit 0"], options).error.code == Status.notFound);

    options.environment[0].value = "";
    const result = run(context, [
        "sh", "-c", "test ! -e /proc/self/fd/\"$1\" && printf ready", "probe", descriptor.to!string
    ], options);
    assert(result.ok && result.value.code == 0);
    assert(result.value.stdoutBytes == cast(const(ubyte)[]) "ready");
}

@("a quickly exiting child is reaped as soon as its pipes close rather than on the next supervisor poll")
unittest
{
    import core.time : MonoTime;
    import std.algorithm.sorting : sort;

    Context context;
    enum rounds = 15;
    long[rounds] elapsed;
    foreach (ref sample; elapsed)
    {
        const started = MonoTime.currTime;
        const result = run(context, ["true"]);
        sample = (MonoTime.currTime - started).total!"usecs";
        assert(result.ok && result.value.code == 0, result.error.message);
    }
    elapsed[].sort();
    // The supervisor previously noticed a finished child only on its 5 ms polling tick.
    assert(elapsed[rounds / 2] < 3_000, "child reaping waited for the supervisor polling interval");
}
