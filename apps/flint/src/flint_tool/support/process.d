/// Child processes through flint.os, cancelled together when the user interrupts flint.
module flint_tool.support.process;

import flint.arena : Status;
import flint.conc : CancelSource, Context, Deadline;
import flint.log : Field, Format, Level, LogOptions, Logger;
import flint.os : EnvVar, ExitStatus, InterruptSubscription, ProcessOptions, onInterrupt, run, stream;

@safe:

private Context active;
private CancelSource interruptSource;
private InterruptSubscription interruptSubscription;
private Logger trace;
private bool tracing;

/// With FLINT_LOG=<file>, record every child process flint runs as one JSON line (flint.log).
void installTrace()
{
    import std.process : environment;

    const path = environment.get("FLINT_LOG", "");
    if (path.length == 0)
        return;
    LogOptions options;
    options.format = Format.json;
    options.level = Level.info;
    options.filePath = path;
    options.maxRecordBytes = 16 * 1024;
    auto created = Logger.create(options);
    if (!created.ok())
        return;
    trace = created.value;
    tracing = true;
}

/// Drain and close the trace log.
void closeTrace()
{
    if (!tracing)
        return;
    trace.flush();
    trace.close();
    tracing = false;
}

private void record(scope const(string)[] argv, string directory, const ref Outcome outcome, long millis)
{
    import std.array : join;
    import std.conv : to;

    if (!tracing)
        return;
    const fields = [
        Field("argv", argv.join(" ")), Field("directory", directory),
        Field("started", outcome.started ? "true" : "false"),
        Field("exit_code", outcome.code.to!string),
        Field("signalled", outcome.signalled ? "true" : "false"),
        Field("duration_ms", millis.to!string)
    ];
    trace.info("child process finished", fields);
}

/// Cancel running children when SIGINT arrives. Call once from main before starting children.
void installInterruptHandling()
{
    auto created = CancelSource.create(Context.init, Deadline.init);
    if (!created.ok)
        return;
    interruptSource = move(created.value);
    active = interruptSource.context();
    auto source = &interruptSource;
    auto subscription = onInterrupt(() @safe { source.cancel(); });
    if (subscription.ok)
        interruptSubscription = move(subscription.value);
}

private T move(T)(ref T value)
{
    import core.lifetime : coreMove = move;

    return coreMove(value);
}

/// Whether the user interrupted flint.
bool interrupted()
{
    return active.cancelled();
}

/// The outcome of one child process.
struct Outcome
{
    /// The executable started.
    bool started;
    /// Why it did not start, or why it was stopped.
    string failure;
    /// Exit code, or signal number when `signalled`.
    int code;
    /// The child was killed by a signal.
    bool signalled;
    /// Captured standard output.
    string output;
    /// Captured standard error.
    string errors;

    /// Started and exited normally with status zero.
    bool ok() const
    {
        return started && !signalled && code == 0;
    }

    /// Standard output and error, in that order, for diagnostics.
    string combined() const
    {
        if (errors.length == 0)
            return output;
        if (output.length == 0)
            return errors;
        return output ~ (output[$ - 1] == '\n' ? "" : "\n") ~ errors;
    }
}

/// Options shared by capture and stream.
struct Launch
{
    /// Working directory of the child; empty means flint's own.
    string directory;
    /// Environment overrides applied on top of the inherited or empty environment.
    EnvVar[] environment;
    /// Start from flint's environment.
    bool inherit = true;
}

/// Run argv to completion and keep its output.
Outcome capture(scope const(string)[] argv, Launch launch = Launch.init)
{
    import core.time : MonoTime;

    auto options = processOptions(launch);
    options.maxCaptureBytes = 64UL << 20;
    const started = MonoTime.currTime;
    auto result = run(active, argv, options);
    auto finished = outcome(result.ok, result.error.message, result.value, true);
    record(argv, launch.directory, finished, (MonoTime.currTime - started).total!"msecs");
    return finished;
}

/// Callback receiving each chunk of a streamed child's output.
alias Sink = void delegate(scope const(char)[] text) @safe;

/// Run argv, handing each output chunk to the sinks as it arrives.
Outcome streamed(scope const(string)[] argv, Launch launch, scope Sink onOutput, scope Sink onError)
{
    import core.time : MonoTime;

    auto options = processOptions(launch);
    // A slow terminal must not stop a build.
    options.sinkStallNanos = 60_000_000_000;
    const started = MonoTime.currTime;
    auto result = stream(active, argv, (scope const(ubyte)[] bytes) @safe {
        onOutput(cast(const(char)[]) bytes);
    }, (scope const(ubyte)[] bytes) @safe { onError(cast(const(char)[]) bytes); }, options);
    auto finished = outcome(result.ok, result.error.message, result.value, false);
    record(argv, launch.directory, finished, (MonoTime.currTime - started).total!"msecs");
    return finished;
}

private ProcessOptions processOptions(Launch launch)
{
    ProcessOptions options;
    options.workingDirectory = launch.directory;
    options.environment = launch.environment;
    options.inheritEnvironment = launch.inherit;
    return options;
}

private Outcome outcome(bool ok, string message, ref ExitStatus status, bool captured)
{
    Outcome result;
    result.started = ok;
    if (!ok)
    {
        result.failure = message.length ? message : "the process could not be started";
        return result;
    }
    result.code = status.code;
    result.signalled = status.signalled;
    if (status.timedOut || (status.signalled && interrupted()))
        result.failure = "interrupted";
    if (captured)
    {
        result.output = (cast(const(char)[]) status.stdoutBytes).idup;
        result.errors = (cast(const(char)[]) status.stderrBytes).idup;
    }
    return result;
}

/// Find an executable on PATH, as a shell would, or return null.
string which(string name)
{
    import std.algorithm.iteration : splitter;
    import std.file : exists, isFile;
    import std.path : buildPath;
    import std.process : environment;

    if (name.length == 0)
        return null;
    import flint_tool.toolchain.host : pathListSeparator;

    foreach (directory; environment.get("PATH", "").splitter(pathListSeparator))
    {
        if (directory.length == 0)
            continue;
        version (Windows)
        {
            import std.path : extension;

            // Only executables: flint never starts a batch file through cmd.exe.
            foreach (suffix; extension(name).length ? [""] : [".exe", ".com"])
            {
                const candidate = buildPath(directory, name ~ suffix);
                if (exists(candidate) && isFile(candidate))
                    return candidate;
            }
        }
        else
        {
            const candidate = buildPath(directory, name);
            if (exists(candidate) && isFile(candidate) && executable(candidate))
                return candidate;
        }
    }
    return null;
}

version (Posix) private bool executable(string path)
{
    import std.file : getAttributes;

    return (getAttributes(path) & octal!"111") != 0;
}

private template octal(string text)
{
    enum octal = () {
        uint value;
        foreach (ch; text)
            value = value * 8 + (ch - '0');
        return value;
    }();
}
