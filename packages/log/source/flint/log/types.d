module flint.log.types;

import flint.arena : Status;

@safe:

/// Severity threshold and emitted severity.
enum Level : ubyte
{
    trace,
    debug_,
    info,
    warn,
    error,
    off
}

/// Selected representation of each complete record.
enum Format : ubyte
{
    json,
    console
}

/// A UTF-8 structured key and a string value.
struct Field
{
    /// At most 128 UTF-8 bytes.
    string key;
    /// Values under sensitive keys are replaced before producer storage is touched.
    string value;
}

/// Copied correlation values. The zero value represents no task context.
struct LogContext
{
    /// Numeric request identifier from the active task.
    ulong requestId;
    /// High half of the 128-bit trace identifier.
    ulong traceIdHigh;
    /// Low half of the 128-bit trace identifier.
    ulong traceIdLow;
    /// The current span's identifier.
    ulong spanId;
}

/// Nonblocking consumer callback. Status.unavailable retries the same complete line.
alias LogSink = Status delegate(scope const(char)[] line) @safe nothrow @nogc;
/// Optional application composition hook for convenience calls.
alias LogContextProvider = LogContext function() @safe nothrow @nogc;

/// Startup-only storage, redaction, context and sink settings.
struct LogOptions
{
    /// The lowest eligible severity.
    Level level = Level.info;
    /// The emitted line format.
    Format format = Format.json;
    /// Total normal ring payload capacity, shared across producer shards.
    uint ringBytes = 1_048_576;
    /// Maximum serialized line size, including its newline and metadata.
    uint maxRecordBytes = 4096;
    /// Optional append-only file. The default uses stdout with errors on stderr.
    string filePath;
    /// An optional owned consumer delegate, mutually exclusive with filePath.
    LogSink sink;
    /// Consulted by info, warn and error. Explicit write uses the supplied context.
    LogContextProvider currentContext;
    /// Explicit ASCII case-insensitive exceptions to built-in key redaction.
    string[] allowSensitiveKeys;
    /// Maximum time close allows accepted records to drain.
    ulong closeTimeoutMillis = 1000;
}

/// A concurrent snapshot of acceptance, loss and delivery observations.
struct LogStats
{
    /// Accepted entries indexed by severity from trace through error.
    ulong[5] accepted;
    /// Rejected producer entries indexed by severity from trace through error.
    ulong[5] dropped;
    /// Complete lines accepted by the sink.
    ulong delivered;
    /// Terminal sink errors.
    ulong sinkFailures;
}
