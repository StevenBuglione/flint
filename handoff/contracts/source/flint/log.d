/// Public API contract; declarations are not runtime implementations.
module flint.log;
import flint.arena : Status, Error, Result;

@safe:
enum Level : ubyte
{
    trace,
    debug_,
    info,
    warn,
    error,
    off
}

enum Format : ubyte
{
    json,
    console
}

struct Field
{
    string key;
    string value;
}

struct LogContext
{
    ulong requestId;
    ulong traceIdHigh;
    ulong traceIdLow;
    ulong spanId;
}

struct LogOptions
{
    Level level = Level.info;
    Format format = Format.json;
    uint ringBytes = 1048576;
    uint maxRecordBytes = 4096;
}

struct Logger
{
    private ulong id;
    static Result!Logger create(LogOptions options);
    Status write(Level level, scope const(char)[] message, scope const(Field)[] fields,
            LogContext context = LogContext.init) nothrow @nogc;
    Status info(scope const(char)[] message, scope const(Field)[] fields = null) nothrow @nogc;
    Status warn(scope const(char)[] message, scope const(Field)[] fields = null) nothrow @nogc;
    Status error(scope const(char)[] message, scope const(Field)[] fields = null) nothrow @nogc;
    Error flush(ulong timeoutMillis = 1000) nothrow @nogc;
    void close() nothrow;
}
