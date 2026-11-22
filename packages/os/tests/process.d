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

    version (OSX)
    {
        assertRetired(fields[1]);
    }
    else
    {
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
        const pid = (cast(const(char)[]) data).strip().idup;
        const limit = Deadline.afterMillis(2_000).monotonicNanoseconds;
        while (Deadline.afterMillis(0).monotonicNanoseconds < limit)
        {
            if (!processPresent(pid))
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
            path = (cast(const(char)[]) data).strip().idup;
            throw expected;
        }, null, options);
        assert(0, "sink exception was suppressed: " ~ unexpected.error.message);
    }
    catch (Exception caught)
    {
        assert(caught is expected && calls == 1);
        assert(!processPresent(path));
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
        "sh", "-c", "test ! -e " ~ descriptorDirectory ~ "/\"$1\" && printf ready", "probe",
        descriptor.to!string
    ], options);
    assert(result.ok && result.value.code == 0);
    assert(result.value.stdoutBytes == cast(const(ubyte)[]) "ready");
}

@("a quickly exiting child is reaped as soon as its pipes close rather than on the next supervisor poll")
unittest
{
    import core.time : MonoTime;
    import std.algorithm.sorting : sort;
    import std.conv : to;

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
    // The supervisor previously noticed a finished child only on its 5 ms polling tick. Under
    // AddressSanitizer, forking a process with its shadow mappings alone costs milliseconds, so
    // wall-clock latency is not representative there; the functional checks above still run.
    version (LDC_AddressSanitizer)
    {
    }
    else
        assertWallClock(elapsed[rounds / 2] < 3_000, "child reaping median " ~ elapsed[rounds / 2].to!string
                ~ " us (bound 3000 us; above it, reaping waits for the supervisor poll)");
}

@("concurrent stdout and stderr each reach their sink in emission order")
unittest
{
    import std.conv : to;

    Context context;
    char[] stdoutText, stderrText;
    const result = stream(context, ["/bin/sh", "-c", "seq 1 100000 & seq 1 100000 >&2 & wait"],
            (scope const(ubyte)[] bytes) @safe { stdoutText ~= cast(const(char)[]) bytes; },
            (scope const(ubyte)[] bytes) @safe { stderrText ~= cast(const(char)[]) bytes; });
    assert(result.ok, result.error.message);
    assert(result.value.code == 0);
    char[] expected;
    foreach (value; 1 .. 100_001)
        expected ~= value.to!string ~ "\n";
    // Each stream is far larger than a pipe buffer, so both readers must have interleaved.
    assert(expected.length > 512 * 1024);
    assert(stdoutText == expected);
    assert(stderrText == expected);
}

/// Wait for a descendant reparented away from the caller to be dead or a zombie owned by its new parent.
private void assertRetired(scope const(char)[] pid)
{
    import core.thread : Thread;
    import core.time : msecs;
    import std.file : exists, readText;
    import std.string : split;

    version (OSX)
    {
        foreach (_; 0 .. 1000)
        {
            if (deadOrZombie(pid))
                return;
            Thread.sleep(1.msecs);
        }
        assert(0, "descendant survived termination");
    }
    const path = "/proc/" ~ pid.idup ~ "/stat";
    foreach (_; 0 .. 1000)
    {
        if (!exists(path))
            return;
        try
        {
            if (readText(path).split(") ")[1][0] == 'Z')
                return;
        }
        catch (Exception)
        {
            if (!exists(path))
                return;
        }
        Thread.sleep(1.msecs);
    }
    assert(0, "descendant survived termination");
}

@("a deadline escalates past an ignored SIGTERM, kills the grandchild and reaps the direct child")
unittest
{
    import core.stdc.errno : ECHILD, errno;
    import core.sys.posix.sys.wait : WNOHANG, waitpid;
    import std.conv : to;
    import std.string : split;

    auto source = CancelSource.create(Context.init, Deadline.afterMillis(500));
    assert(source.ok);
    auto context = source.value.context();
    ProcessOptions options;
    options.terminateGraceNanos = 20_000_000;
    char[] receipt;
    const timedOut = stream(context, [
        "/bin/sh", "-c", "trap '' TERM; sleep 30 & printf '%s %s\\n' \"$$\" \"$!\"; wait"
    ], (scope const(ubyte)[] data) @safe { receipt ~= cast(const(char)[]) data; }, null, options);
    assert(timedOut.ok, timedOut.error.message);
    assert(timedOut.value.timedOut && timedOut.value.signalled);
    // The ignored SIGTERM forces the SIGKILL escalation.
    enum sigkill = 9;
    assert(timedOut.value.code == sigkill);

    const fields = receipt.split();
    assert(fields.length == 2);
    assert(waitpid(fields[0].to!int, null, WNOHANG) == -1 && errno == ECHILD);
    assertRetired(fields[1]);
}

/// Wall-clock bounds are enforced on native hardware. A lane that runs these tests under full-system
/// emulation sets `FLINT_EMULATED=1`, and the bound is then reported with its measurement instead of
/// asserted, because emulated syscalls and context switches cost milliseconds (ADR-017).
private void assertWallClock(bool within, lazy string measurement) @trusted
{
    import core.stdc.stdio : fflush, printf, stdout;
    import std.process : environment;

    if (environment.get("FLINT_EMULATED") == "1")
    {
        const text = measurement;
        printf("FLINT-EMULATED wall-clock bound %s: %.*s\n", within ? "met".ptr : "not met".ptr,
                cast(int) text.length, text.ptr);
        fflush(stdout);
        return;
    }
    assert(within, measurement);
}

/// The directory listing the calling process's open descriptors.
version (OSX)
    private enum descriptorDirectory = "/dev/fd";
else
    private enum descriptorDirectory = "/proc/self/fd";

/// Whether a process with this decimal ID exists, including as a zombie.
private bool processPresent(string pid) @trusted
{
    version (OSX)
    {
        import core.stdc.errno : EPERM, errno;
        import core.sys.posix.signal : kill;
        import std.conv : to;

        return kill(pid.to!int, 0) == 0 || errno == EPERM;
    }
    else
    {
        import std.file : exists;

        return exists("/proc/" ~ pid);
    }
}

version (OSX)
{
    private extern (C) @system nothrow @nogc
    {
        int sysctl(int* name, uint length, void* value, size_t* size, void* update, size_t updateSize);
    }

    /// Whether a process is gone or a zombie, from the kernel's kinfo_proc (<sys/sysctl.h>).
    private bool deadOrZombie(scope const(char)[] pid) @trusted
    {
        import std.conv : to;

        enum ctlKern = 1, kernProc = 14, kernProcPid = 1;
        enum statOffset = 40; // kinfo_proc.kp_proc.p_stat
        enum zombie = 5; // SZOMB
        int[4] name = [ctlKern, kernProc, kernProcPid, pid.to!int];
        ubyte[648] info; // sizeof(struct kinfo_proc) on arm64
        size_t size = info.length;
        assert(sysctl(name.ptr, name.length, info.ptr, &size, null, 0) == 0);
        return size == 0 || info[statOffset] == zombie;
    }
}
