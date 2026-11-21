module flint.os.internal;

import core.atomic : atomicLoad, atomicStore, cas;
import flint.arena : Error, Result, Status;
import flint.conc : Context, Deadline;
import flint.os.sys.process : Child, childExited, closeChildPipes, closeFd, launch, nativeStatus,
    pull, reap, setupResult, signalGroup, validateWaitPolicy, waitForOutput;
import flint.os.sys.threads : joinThread, startThread;
import flint.os.types : ExitStatus, OutputSink, ProcessOptions;
import std.process : environment;

@safe:

private enum maxStringBytes = 131_071;
private enum maxVectorBytes = 2 * 1024 * 1024;
private enum maxVectorEntries = 32_768;
private enum ioChunk = 16_384;
private enum pollMillis = 5;

private struct Command
{
    string[] executablePaths;
    string[] argv;
    string[] envp;
    string directory;
}

private bool validNativeString(scope const(char)[] input, bool isName = false) pure nothrow @nogc
{
    if (input.length > maxStringBytes)
        return false;
    foreach (value; input)
        if (value == '\0' || (isName && value == '='))
            return false;
    return true;
}

private bool appendCString(ref string[] result, scope const(char)[] value, ref size_t used)
{
    if (!validNativeString(value) || value.length >= maxVectorBytes - used || result.length == maxVectorEntries)
        return false;

    used += value.length + 1;
    result ~= value.idup ~ "\0";
    return true;
}

private Result!(Command*) prepare(scope const(char[])[] argv, ProcessOptions options)
{
    if (argv.length == 0 || argv[0].length == 0 || argv.length > maxVectorEntries
            || !validNativeString(options.workingDirectory) || options.terminateGraceNanos < 0
            || options.sinkStallNanos <= 0 || options.maxCaptureBytes > size_t.max)
        return Result!(Command*)(null, Error(Status.invalidArgument, "invalid process options or argv"));

    // The contained slices survive allocation while their fields are borrowed by the builders.
    auto command = new Command;
    size_t bytesUsed;
    foreach (arg; argv)
        if (!appendCString(command.argv, arg, bytesUsed))
            return Result!(Command*)(null, Error(Status.invalidArgument, "invalid or excessive argv"));

    const result = prepareEnvironment(options, command.envp, bytesUsed);
    if (!result.ok)
        return Result!(Command*)(null, result.error);
    if (!preparePaths(argv[0], result.value, command.executablePaths))
        return Result!(Command*)(null, Error(Status.invalidArgument, "executable search path too large"));

    if (options.workingDirectory.length != 0)
        command.directory = options.workingDirectory ~ "\0";
    return Result!(Command*)(command);
}

private Result!string prepareEnvironment(ProcessOptions options, ref string[] entries, ref size_t bytesUsed)
{
    if (options.environment.length > maxVectorEntries)
        return Result!string(null, Error(Status.invalidArgument, "too many environment overrides"));

    string[string] variables;
    if (options.inheritEnvironment)
        variables = environment.toAA();
    foreach (ref item; options.environment)
    {
        if (item.name.length == 0 || !validNativeString(item.name, true) || !validNativeString(item.value))
            return Result!string(null, Error(Status.invalidArgument, "invalid environment override"));
        variables[item.name] = item.value;
    }
    foreach (name, value; variables)
    {
        if (!validNativeString(name, true) || !validNativeString(value) || name.length + value.length >= maxStringBytes)
            return Result!string(null, Error(Status.invalidArgument, "invalid environment entry"));
        if (!appendCString(entries, name ~ "=" ~ value, bytesUsed))
            return Result!string(null, Error(Status.resourceExhausted, "environment exceeds process limit"));
    }
    const path = "PATH" in variables;
    return Result!string(path is null ? "/bin:/usr/bin" : *path);
}

private bool preparePaths(scope const(char)[] executable, string path, ref string[] candidates)
{
    size_t used;
    foreach (character; executable)
        if (character == '/')
            return appendCString(candidates, executable, used);

    size_t first;
    foreach (index, character; path)
    {
        if (character == ':')
        {
            if (!appendPath(candidates, path[first .. index], executable, used))
                return false;
            first = index + 1;
        }
    }
    return appendPath(candidates, path[first .. $], executable, used);
}

private bool appendPath(ref string[] candidates, string directory, scope const(char)[] executable, ref size_t used)
{
    if (directory.length == 0)
        return appendCString(candidates, executable, used);
    if (directory.length + executable.length >= maxStringBytes)
        return false;
    return appendCString(candidates, directory ~ "/" ~ executable, used);
}

private enum StopReason : ubyte
{
    none,
    cancelled,
    deadline,
    sinkStalled,
    failed,
    lingeringGroup
}

private long after(long now, long nanos) pure nothrow @nogc
{
    return now >= long.max - nanos ? long.max : now + nanos;
}

private struct Supervisor
{
    private int pid;
    private Context context;
    private long graceNanos;
    private long stallNanos;
    private shared StopReason stopped;
    private shared long callbackStart = -1;
    private shared bool streamsClosed;
    private shared long outputProgress = -1;
    private shared bool done;
    private Error failure;
    private ExitStatus outcome;

    void stop(StopReason reason) nothrow @nogc
    {
        cas(&stopped, StopReason.none, reason);
    }

    void supervise() nothrow @nogc
    {
        scope (exit)
            atomicStore(done, true);
        long leaderExitAt = -1;
        const idleNanos = graceNanos > stallNanos ? graceNanos : stallNanos;
        long escalatesAt = long.max;
        bool termSent;
        while (true)
        {
            const now = Deadline.afterMillis(0).monotonicNanoseconds;
            observeCancellation(now);
            const observed = childExited(pid);
            if (!observed.ok)
            {
                failure = observed.error;
                return;
            }

            if (observed.value && leaderExitAt < 0)
                leaderExitAt = now;
            if (leaderExitAt >= 0 && !atomicLoad(streamsClosed))
            {
                const progress = atomicLoad(outputProgress);
                const latest = leaderExitAt > progress ? leaderExitAt : progress;
                if (now >= after(latest, idleNanos))
                    stop(StopReason.lingeringGroup);
            }

            if (atomicLoad(stopped) != StopReason.none)
            {
                if (!termSent)
                {
                    termSent = true;
                    escalatesAt = after(now, graceNanos);
                    signalGroup(pid, false);
                }
                if (now >= escalatesAt)
                {
                    retireChild();
                    return;
                }
            }
            else if (observed.value && atomicLoad(streamsClosed))
            {
                retireChild();
                return;
            }
            waitForOutput(-1, -1, pollMillis);
        }
    }

    private void observeCancellation(long now) nothrow @nogc
    {
        if (atomicLoad(stopped) != StopReason.none)
            return;
        const status = context.check().code;
        if (status == Status.cancelled)
            stop(StopReason.cancelled);
        else if (status == Status.timedOut)
            stop(StopReason.deadline);
        else
        {
            const started = atomicLoad(callbackStart);
            if (started >= 0 && now >= after(started, stallNanos))
                stop(StopReason.sinkStalled);
        }
    }

    private void retireChild() nothrow @nogc
    {
        // Even if the leader already exited, its unreaped PID still pins the process group.
        failure = signalGroup(pid, true);
        const exited = reap(pid);
        if (!exited.ok)
            failure = exited.error;
        else
            outcome = ExitStatus(exited.value.code, exited.value.signalled);
    }
}

private Error checkSetup(ref Child child, Supervisor* supervisor) nothrow @nogc
{
    scope (exit)
        closeFd(child.startupFd);
    while (!atomicLoad(supervisor.done))
    {
        const ready = waitForOutput(child.startupFd, -1, pollMillis);
        if (!ready.ok)
            return ready.error;
        if (ready.value == 0)
            continue;
        const code = setupResult(child.startupFd);
        if (code.ok)
            return code.value == 0 ? Error.init : Error(nativeStatus(code.value), "could not start requested child");
        if (code.error.code != Status.unavailable)
            return code.error;
    }
    return Error.init;
}

private struct OutputPump
{
    private Supervisor* supervisor;
    private size_t captureLimit;
    private bool capture;
    private ubyte[] capturedOut;
    private ubyte[] capturedErr;
    private ubyte[ioChunk] scratch;

    Error run(ref Child child, scope OutputSink outSink, scope OutputSink errSink)
    {
        while (child.stdoutFd >= 0 || child.stderrFd >= 0)
        {
            if (atomicLoad(supervisor.done))
                break;
            const ready = waitForOutput(child.stdoutFd, child.stderrFd, pollMillis);
            if (!ready.ok)
                return ready.error;
            if ((ready.value & 1) != 0)
            {
                const outputError = consume(child.stdoutFd, outSink, capturedOut);
                if (outputError.code != Status.ok)
                    return outputError;
            }
            if ((ready.value & 2) != 0)
            {
                const errorOutputError = consume(child.stderrFd, errSink, capturedErr);
                if (errorOutputError.code != Status.ok)
                    return errorOutputError;
            }
        }
        return Error.init;
    }

    private Error consume(ref int reader, scope OutputSink sink, ref ubyte[] captured)
    {
        const result = pull(reader, scratch[]);
        if (!result.ok)
            return result.error.code == Status.unavailable ? Error.init : result.error;
        if (result.value == 0)
        {
            closeFd(reader);
            return Error.init;
        }

        if (atomicLoad(supervisor.stopped) != StopReason.none)
            return Error.init;

        atomicStore(supervisor.outputProgress, Deadline.afterMillis(0).monotonicNanoseconds);
        const chunk = scratch[0 .. result.value];
        if (capture)
        {
            const available = captureLimit - capturedOut.length - capturedErr.length;
            const count = chunk.length < available ? chunk.length : available;
            captured ~= chunk[0 .. count];
            if (count < chunk.length)
                return Error(Status.resourceExhausted, "combined child capture limit reached");
        }
        else if (sink !is null)
        {
            atomicStore(supervisor.callbackStart, Deadline.afterMillis(0).monotonicNanoseconds);
            scope (exit)
                atomicStore(supervisor.callbackStart, -1L);
            sink(chunk);
        }
        return Error.init;
    }
}

private Result!ExitStatus childResult(Supervisor* supervisor, OutputPump* pump, Error outputError)
{
    auto outcome = supervisor.outcome;
    outcome.stdoutBytes = pump.capturedOut;
    outcome.stderrBytes = pump.capturedErr;

    if (supervisor.failure.code != Status.ok)
        return Result!ExitStatus(outcome, supervisor.failure);
    if (outputError.code != Status.ok)
        return Result!ExitStatus(outcome, outputError);

    switch (atomicLoad(supervisor.stopped))
    {
    case StopReason.cancelled:
        return Result!ExitStatus(outcome, Error(Status.cancelled, "child cancelled"));
    case StopReason.deadline:
        outcome.timedOut = true;
        return Result!ExitStatus(outcome);
    case StopReason.sinkStalled:
        return Result!ExitStatus(outcome, Error(Status.timedOut, "child output sink stalled"));
    default:
        return Result!ExitStatus(outcome);
    }
}

package(flint.os) Result!ExitStatus execute(ref scope Context context, scope const(char[])[] argv,
        scope OutputSink outSink, scope OutputSink errSink, ProcessOptions options, bool capture)
{
    const checked = context.check();
    if (checked.code == Status.cancelled)
        return Result!ExitStatus(ExitStatus.init, checked);
    if (checked.code == Status.timedOut)
        return Result!ExitStatus(ExitStatus(0, false, true));

    const waitPolicy = validateWaitPolicy();
    if (waitPolicy.code != Status.ok)
        return Result!ExitStatus(ExitStatus.init, waitPolicy);

    auto command = prepare(argv, options);
    if (!command.ok)
        return Result!ExitStatus(ExitStatus.init, command.error);
    auto supervisor = new Supervisor;
    auto child = launch(command.value.executablePaths, command.value.argv, command.value.envp,
            command.value.directory);
    if (!child.ok)
        return Result!ExitStatus(ExitStatus.init, child.error);
    scope (exit)
        closeChildPipes(child.value);

    supervisor.pid = child.value.pid;
    supervisor.context = context;
    supervisor.graceNanos = options.terminateGraceNanos;
    supervisor.stallNanos = options.sinkStallNanos;
    bool supervising;
    scope (failure)
    {
        if (!supervising)
        {
            signalGroup(child.value.pid, true);
            reap(child.value.pid);
        }
    }
    auto thread = startThread(&supervisor.supervise);
    supervising = true;
    scope (failure)
    {
        supervisor.stop(StopReason.failed);
        atomicStore(supervisor.streamsClosed, true);
        joinThread(thread);
    }

    auto pump = new OutputPump;
    pump.supervisor = supervisor;
    pump.captureLimit = cast(size_t) options.maxCaptureBytes;
    pump.capture = capture;
    auto error = checkSetup(child.value, supervisor);
    if (error.code == Status.ok)
        error = pump.run(child.value, outSink, errSink);
    if (error.code != Status.ok)
        supervisor.stop(StopReason.failed);
    atomicStore(supervisor.streamsClosed, true);
    if (joinThread(thread) !is null)
        return Result!ExitStatus(ExitStatus.init, Error(Status.ioError, "child supervisor failed"));
    return childResult(supervisor, pump, error);
}
