// Ported from spring-boot v4.2.0: core/spring-boot/src/main/java/org/springframework/boot/logging/LoggingSystem.java
// and logback/LogbackLoggingSystem.java (its level handling and console appender), in shape.
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: Flint has no Logback; Boot's logging system drives `flint.slf4j`'s default provider,
// replacing its output with Boot's console format and its levels with `logging.level.*`.

/// Boot's logging system on `flint.slf4j`: every SLF4J logger in the application prints Boot's console line.
///
/// `flint.slf4j`'s default provider keeps the loggers, their levels and the fiber-local MDC. Boot installs its
/// `ConsoleLogFormat` as that provider's appender and sets each `logging.level.<name>` (`root` for the root
/// logger), as `LogbackLoggingSystem` configures Logback. When an application installs its own SLF4J provider, Boot
/// leaves it alone.
module flint.boot.logging.slf4j;

import flint.boot.logging : ConsoleLogFormat, LogEvent, LogLevel;
import flint.slf4j : LoggerFactory;
import flint.slf4j.event : Level, LoggingEvent;
import flint.slf4j.provider : FlintLogLoggerFactory;

@safe:

/// Boot's logging system over `flint.slf4j`.
final class Slf4jLoggingSystem
{
    private ConsoleLogFormat format;
    private void delegate(string) @safe sink;

    /// Print with `format` to `sink` (standard output when `null`).
    this(ConsoleLogFormat format, void delegate(string) @safe sink = null)
    {
        this.format = format;
        this.sink = sink;
    }

    /// Whether `flint.slf4j` is bound to its default provider, which Boot configures.
    static bool isConfigurable()
    {
        return factory() !is null;
    }

    /// Install Boot's console format as the appender of every logger.
    void initialize()
    {
        auto loggers = factory();
        if (loggers is null)
            return;
        auto rendering = format;
        auto output = sink;
        loggers.setAppender((LoggingEvent event) {
            const line = rendering.format(toLogEvent(event));
            if (output !is null)
                output(line);
            else
                writeOut(line);
        });
    }

    /// Set the level of `loggerName` (`root` or empty for the root logger), as `logging.level.<name>` does.
    void setLogLevel(string loggerName, LogLevel level)
    {
        import std.uni : sicmp;

        auto loggers = factory();
        if (loggers is null)
            return;
        loggers.setLevel(sicmp(loggerName, "root") == 0 ? "" : loggerName, toLevel(level));
    }

    /// Restore `flint.slf4j`'s own output.
    void cleanUp()
    {
        if (auto loggers = factory())
            loggers.setAppender(null);
    }

    private static FlintLogLoggerFactory factory()
    {
        return cast(FlintLogLoggerFactory) LoggerFactory.getILoggerFactory();
    }
}

/// SLF4J's level for Boot's; `OFF` is above `ERROR`, so nothing is enabled.
Level toLevel(LogLevel level) pure nothrow @nogc
{
    final switch (level)
    {
    case LogLevel.TRACE:
        return Level.TRACE;
    case LogLevel.DEBUG:
        return Level.DEBUG;
    case LogLevel.INFO:
        return Level.INFO;
    case LogLevel.WARN:
        return Level.WARN;
    case LogLevel.ERROR:
    case LogLevel.FATAL:
        return Level.ERROR;
    case LogLevel.OFF:
        return cast(Level) 1000;
    }
}

/// Boot's console event for an SLF4J event: the message formatted with its arguments, the throwable rendered.
LogEvent toLogEvent(LoggingEvent event)
{
    import flint.boot.internal.log : localOffsetMinutes, processId, render;
    import flint.slf4j.helpers : MessageFormatter;

    LogEvent result;
    result.timestampMillis = event.getTimeStamp();
    result.utcOffsetMinutes = localOffsetMinutes();
    result.level = fromLevel(event.getLevel());
    result.pid = processId();
    result.thread = event.getThreadName().length ? event.getThreadName() : "main";
    result.logger = event.getLoggerName();
    auto formatted = MessageFormatter.arrayFormat(event.getMessage(), event.getArgumentArray());
    result.message = formatted.getMessage();
    auto failure = event.getThrowable() !is null ? event.getThrowable() : formatted.getThrowable();
    if (failure !is null)
        result.throwable = render(failure);
    return result;
}

private LogLevel fromLevel(Level level) pure nothrow @nogc
{
    final switch (level)
    {
    case Level.TRACE:
        return LogLevel.TRACE;
    case Level.DEBUG:
        return LogLevel.DEBUG;
    case Level.INFO:
        return LogLevel.INFO;
    case Level.WARN:
        return LogLevel.WARN;
    case Level.ERROR:
        return LogLevel.ERROR;
    }
}

private void writeOut(string line)
{
    import flint.term : Stream, writeStream;

    cast(void) writeStream(Stream.output, line);
}
