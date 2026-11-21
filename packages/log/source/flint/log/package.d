module flint.log;

import flint.arena : Error, Result, Status;
import flint.log.internal : LoggerState;

public import flint.log.types : Field, Format, Level, LogContext, LogContextProvider, LogOptions, LogSink, LogStats;

@safe:

/// Copyable handle to a bounded asynchronous logger. Close retires the shared sink for every copy.
struct Logger
{
    private LoggerState* state;

    /// Reserve producer storage and open the configured sink before starting its consumer.
    static Result!Logger create(LogOptions options)
    {
        auto created = LoggerState.create(options);
        if (!created.ok)
            return Result!Logger(Logger.init, created.error);
        return Result!Logger(Logger(created.value));
    }

    /// Copy one enabled record into a bounded slot with its explicit copied task context.
    Status write(Level level, scope const(char)[] message, scope const(Field)[] fields,
            LogContext context = LogContext.init) nothrow @nogc
    {
        if (state is null)
            return Status.unavailable;
        return state.submit(level, message, fields, context, false);
    }

    /// Write an information record using the configured context provider.
    Status info(scope const(char)[] message, scope const(Field)[] fields = null) nothrow @nogc
    {
        return convenience(Level.info, message, fields);
    }

    /// Write a warning using the configured context provider.
    Status warn(scope const(char)[] message, scope const(Field)[] fields = null) nothrow @nogc
    {
        return convenience(Level.warn, message, fields);
    }

    /// Write to the reserved error ring using the configured context provider.
    Status error(scope const(char)[] message, scope const(Field)[] fields = null) nothrow @nogc
    {
        return convenience(Level.error, message, fields);
    }

    private Status convenience(Level level, scope const(char)[] message, scope const(Field)[] fields) nothrow @nogc
    {
        if (state is null)
            return Status.unavailable;
        return state.submit(level, message, fields, LogContext.init, true);
    }

    /// Wait for records already published when flush began, until the monotonic deadline.
    Error flush(ulong timeoutMillis = 1000) nothrow @nogc
    {
        if (state is null)
            return Error(Status.unavailable, "logger is unavailable");
        return state.flush(timeoutMillis);
    }

    /// Stop admission and drain until the configured deadline. Repeated calls are harmless.
    void close() nothrow
    {
        if (state !is null)
            state.close();
    }

    /// Read independent atomic counters for accepted, dropped and delivered records.
    LogStats stats() const nothrow @nogc
    {
        return state is null ? LogStats.init : state.stats();
    }
}
