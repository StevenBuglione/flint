/// Boot's own logger: Commons Logging's `Log` shape (which Boot's classes use through spring-jcl), forwarding to
/// `flint.slf4j`, whose output Boot's logging system formats.
module flint.boot.internal.log;

import flint.boot.logging : ConsoleLogFormat;
import flint.slf4j : Logger, LoggerFactory;

@safe:

/// Where formatted lines go; tests capture them.
alias LogSink = void delegate(string line) @safe;

/// The console settings `FlintApplication` applies through Boot's logging system.
final class LogSettings
{
    /// The console format.
    ConsoleLogFormat format;
    /// The sink; standard output when `null`.
    LogSink sink;
}

/// A named logger: Commons Logging's `Log` shape over `flint.slf4j`, so Boot's own lines go through the same
/// provider, levels and format as the application's.
final class Log
{
    private string name;

    /// The logger `name`; the settings are applied by the logging system, not per logger.
    this(string name, LogSettings settings = null) pure nothrow @nogc
    {
        this.name = name;
    }

    private Logger logger()
    {
        return LoggerFactory.getLogger(name);
    }

    /// Whether debug output is on.
    bool isDebugEnabled()
    {
        return logger().isDebugEnabled();
    }

    /// Whether info output is on.
    bool isInfoEnabled()
    {
        return logger().isInfoEnabled();
    }

    /// Log at DEBUG.
    void debug_(string message, Throwable failure = null)
    {
        if (failure is null)
            logger().debug_(message);
        else
            logger().debug_(message, failure);
    }

    /// Log at INFO.
    void info(string message, Throwable failure = null)
    {
        if (failure is null)
            logger().info(message);
        else
            logger().info(message, failure);
    }

    /// Log at WARN.
    void warn(string message, Throwable failure = null)
    {
        if (failure is null)
            logger().warn(message);
        else
            logger().warn(message, failure);
    }

    /// Log at ERROR.
    void error(string message, Throwable failure = null)
    {
        if (failure is null)
            logger().error(message);
        else
            logger().error(message, failure);
    }
}

/// `Type: message` and the stack, as Logback's `%wEx` prints a throwable, with each cause after `Caused by: `.
string render(Throwable failure)
{
    string text;
    import flint.boot.diagnostics : causeOf;

    for (Throwable current = failure; current !is null; current = causeOf(current))
    {
        text ~= (text.length ? "Caused by: " : "") ~ typeid(current).name ~ ": " ~ current.message.idup ~ "\n";
        text ~= "\tat " ~ current.file ~ ":" ~ lineText(current.line) ~ "\n";
    }
    return text;
}

private string lineText(size_t line) pure nothrow
{
    import flint.engine.aot.text : decimal;

    return decimal(line);
}

// Flint: the time, zone offset and process id come from flint.engine.aot, not std.datetime and std.process, whose
// SysTime and process objects pull std.socket, std.net.curl and the rest of Phobos's network objects into every
// app (playbook S-9).

/// Milliseconds since the Unix epoch.
long nowMillis() nothrow @nogc
{
    import flint.engine.aot.clock : currentTimeMillis;

    return currentTimeMillis();
}

/// The local zone's current offset from UTC, in minutes.
int localOffsetMinutes() nothrow @nogc
{
    import flint.engine.aot.clock : aotLocalOffsetMinutes = localOffsetMinutes;

    return aotLocalOffsetMinutes();
}

/// This process's id.
long processId() nothrow @nogc
{
    import flint.engine.aot.host : hostProcessId = processId;

    return hostProcessId();
}
