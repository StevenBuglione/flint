/// Boot's own logger until `flint.slf4j` lands: Commons Logging's `Log` shape (which Boot's classes use through
/// spring-jcl), writing Boot's console format to standard output.
///
/// Once third-party-apis publishes `flint.slf4j`, Boot installs its console format as the SLF4J provider
/// (`LoggerFactory.installProvider`) and this module forwards to it.
module flint.boot.internal.log;

import flint.boot.logging : ConsoleLogFormat, LogEvent, LogLevel;

@safe:

/// Where formatted lines go; tests capture them.
alias LogSink = void delegate(string line) @safe;

/// The process-wide console settings, set once by `FlintApplication` before it logs.
final class LogSettings
{
    /// The console format.
    ConsoleLogFormat format;
    /// The threshold: events below it are dropped.
    LogLevel threshold = LogLevel.INFO;
    /// Per-logger thresholds (`logging.level.<name>`), longest prefix wins.
    LogLevel[string] levels;
    /// The sink; standard output when `null`.
    LogSink sink;

    /// Whether `logger` logs at `level`.
    bool enabled(string logger, LogLevel level) const pure
    {
        import std.algorithm.searching : startsWith;

        size_t best;
        LogLevel effective = threshold;
        foreach (name, configured; levels)
        {
            const matches = name == "root" || logger == name || logger.startsWith(name ~ ".");
            const length = name == "root" ? 0 : name.length;
            if (matches && length >= best)
            {
                best = length;
                effective = configured;
            }
        }
        return level >= effective && effective != LogLevel.OFF;
    }
}

/// A named logger.
final class Log
{
    private string name;
    private LogSettings settings;

    /// The logger `name` writing with `settings`.
    this(string name, LogSettings settings) pure nothrow @nogc
    {
        this.name = name;
        this.settings = settings;
    }

    /// Whether debug output is on.
    bool isDebugEnabled() const
    {
        return settings.enabled(name, LogLevel.DEBUG);
    }

    /// Whether info output is on.
    bool isInfoEnabled() const
    {
        return settings.enabled(name, LogLevel.INFO);
    }

    /// Log at DEBUG.
    void debug_(string message, Throwable failure = null)
    {
        write(LogLevel.DEBUG, message, failure);
    }

    /// Log at INFO.
    void info(string message, Throwable failure = null)
    {
        write(LogLevel.INFO, message, failure);
    }

    /// Log at WARN.
    void warn(string message, Throwable failure = null)
    {
        write(LogLevel.WARN, message, failure);
    }

    /// Log at ERROR.
    void error(string message, Throwable failure = null)
    {
        write(LogLevel.ERROR, message, failure);
    }

    private void write(LogLevel level, string message, Throwable failure)
    {
        if (!settings.enabled(name, level))
            return;
        LogEvent event;
        event.timestampMillis = nowMillis();
        event.utcOffsetMinutes = localOffsetMinutes();
        event.level = level;
        event.pid = processId();
        event.logger = name;
        event.message = message;
        if (failure !is null)
            event.throwable = render(failure);
        const line = settings.format.format(event);
        if (settings.sink !is null)
            settings.sink(line);
        else
            writeOut(line);
    }
}

/// `Type: message` and the stack, as Logback's `%wEx` prints a throwable, with each cause after `Caused by: `.
string render(Throwable failure)
{
    string text;
    for (Throwable current = failure; current !is null; current = current.next)
    {
        text ~= (text.length ? "Caused by: " : "") ~ typeid(current).name ~ ": " ~ current.message.idup ~ "\n";
        text ~= "\tat " ~ current.file ~ ":" ~ lineText(current.line) ~ "\n";
    }
    return text;
}

private string lineText(size_t line) pure
{
    import std.conv : to;

    return line.to!string;
}

/// Milliseconds since the Unix epoch.
long nowMillis()
{
    import std.datetime.systime : Clock;

    return (Clock.currTime.stdTime - 621_355_968_000_000_000L) / 10_000;
}

/// The local zone's current offset from UTC, in minutes.
int localOffsetMinutes()
{
    import std.datetime.systime : Clock;

    return cast(int) Clock.currTime.utcOffset.total!"minutes";
}

/// This process's id.
long processId()
{
    import std.process : thisProcessID;

    return thisProcessID;
}

private void writeOut(string line)
{
    import flint.term : Stream, writeStream;

    cast(void) writeStream(Stream.output, line);
}
