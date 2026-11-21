module flint.os;
import flint.arena : Error, Result;
import flint.conc : Context;

@safe:
struct EnvVar
{
    string name;
    string value;
}

struct ProcessOptions
{
    string workingDirectory;
    EnvVar[] environment;
    bool inheritEnvironment = true;
    ulong maxCaptureBytes = 1048576;
    long terminateGraceNanos = 2000000000;
}

struct ExitStatus
{
    int code;
    bool signalled;
    bool timedOut;
}

alias OutputSink = void delegate(scope const(ubyte)[]) @safe;
Result!ExitStatus run(ref scope Context context, scope const(char[])[] argv, ProcessOptions options = ProcessOptions
        .init);
Result!ExitStatus stream(ref scope Context context, scope const(char[])[] argv,
        scope OutputSink stdoutSink, scope OutputSink stderrSink, ProcessOptions options = ProcessOptions.init);
struct GlobOptions
{
    bool followSymlinks = false;
    uint maxDepth = 64;
    uint maxResults = 100000;
}

Result!(string[]) glob(scope const(char)[] root, scope const(char)[] pattern, GlobOptions options = GlobOptions.init);
struct InterruptSubscription
{
    @disable this(this);
    Error close();
}

Result!InterruptSubscription onInterrupt(void delegate() @safe callback);
