module flint.os.types;

@safe:

/// One literal child environment override.
struct EnvVar
{
    /// A nonempty name without NUL or '='.
    string name;
    /// The literal value, without NUL.
    string value;
}

/// Startup, capture, and termination policy.
struct ProcessOptions
{
    /// Directory resolved in the child before executing argv.
    string workingDirectory;
    /// Environment entries applied in order to the selected base environment.
    EnvVar[] environment;
    /// Copy the parent environment before applying overrides.
    bool inheritEnvironment = true;
    /// Combined stdout and stderr bytes retained by run.
    ulong maxCaptureBytes = 1_048_576;
    /// Time between SIGTERM and SIGKILL of the owned Linux process group.
    long terminateGraceNanos = 2_000_000_000;
    /// Maximum uninterrupted time inside a streaming sink before terminating the child.
    long sinkStallNanos = 2_000_000_000;
}

/// Terminal outcome and owned output when requested.
struct ExitStatus
{
    /// Normal exit code or native signal number when signalled is true.
    int code;
    /// The kernel reported signal termination.
    bool signalled;
    /// The Context deadline elapsed before completion.
    bool timedOut;
    /// Bytes captured from standard output by run.
    ubyte[] stdoutBytes;
    /// Bytes captured from standard error by run.
    ubyte[] stderrBytes;
}

/// A callback may use the bytes until that invocation returns.
alias OutputSink = void delegate(scope const(ubyte)[]) @safe;

/// Traversal limits for a root-relative glob.
struct GlobOptions
{
    /// Follow links that resolve beneath the opened root, excluding ancestor cycles.
    bool followSymlinks;
    /// Maximum path depth below the root, up to 64.
    uint maxDepth = 64;
    /// Maximum number of results, up to 100,000.
    uint maxResults = 100_000;
}

/// A process signal that asks the application to stop.
enum ShutdownSignal : ubyte
{
    /// SIGINT, or Ctrl+C in a Windows console.
    interrupt,
    /// SIGTERM, or Ctrl+Break in a Windows console.
    terminate
}
