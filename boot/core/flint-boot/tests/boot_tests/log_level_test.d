// Ported from spring-boot v4.2.0: core/spring-boot/src/test/java/org/springframework/boot/logging/LogLevelTests.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: Mockito's commons-logging `Log` is a recording one; `LogLevel.X.log(...)` is the
// uniform call syntax of a free `log(LogLevel, ...)`, since D enums have no methods.
module boot_tests.log_level_test;

@safe:

version (FlintLogLevelLog)
{
    // Gap: LogLevel is a plain enum; Boot's `LogLevel.log(Log, message[, cause])` does not exist.
    import flint.boot.logging : LogLevel, log;
    import flint.boot.logging.slf4j : JclLog = Log;

    /// A commons-logging `Log` recording `level(message, cause)` calls.
    final class RecordingLog : JclLog
    {
        /// Part of the upstream test fixture.
        string[] calls;

        private void record(string level, string message, Throwable cause)
        {
            calls ~= level ~ "(" ~ message ~ ", " ~ (cause is null ? "null" : "exception") ~ ")";
        }

        /// Part of the upstream test fixture.
        void trace(string message, Throwable cause = null)
        {
            record("trace", message, cause);
        }

        /// Part of the upstream test fixture.
        void debug_(string message, Throwable cause = null)
        {
            record("debug", message, cause);
        }

        /// Part of the upstream test fixture.
        void info(string message, Throwable cause = null)
        {
            record("info", message, cause);
        }

        /// Part of the upstream test fixture.
        void warn(string message, Throwable cause = null)
        {
            record("warn", message, cause);
        }

        /// Part of the upstream test fixture.
        void error(string message, Throwable cause = null)
        {
            record("error", message, cause);
        }

        /// Part of the upstream test fixture.
        void fatal(string message, Throwable cause = null)
        {
            record("fatal", message, cause);
        }
    }

    private string[] logBoth(LogLevel level)
    {
        auto logger = new RecordingLog;
        auto exception = new Exception("test");
        level.log(logger, "test");
        level.log(logger, "test", exception);
        return logger.calls;
    }

    @("logWhenTraceLogsAtTrace") unittest
    {
        assert(logBoth(LogLevel.TRACE) == ["trace(test, null)", "trace(test, exception)"]);
    }

    @("logWhenDebugLogsAtDebug") unittest
    {
        assert(logBoth(LogLevel.DEBUG) == ["debug(test, null)", "debug(test, exception)"]);
    }

    @("logWhenInfoLogsAtInfo") unittest
    {
        assert(logBoth(LogLevel.INFO) == ["info(test, null)", "info(test, exception)"]);
    }

    @("logWhenWarnLogsAtWarn") unittest
    {
        assert(logBoth(LogLevel.WARN) == ["warn(test, null)", "warn(test, exception)"]);
    }

    @("logWhenErrorLogsAtError") unittest
    {
        assert(logBoth(LogLevel.ERROR) == ["error(test, null)", "error(test, exception)"]);
    }

    @("logWhenFatalLogsAtFatal") unittest
    {
        assert(logBoth(LogLevel.FATAL) == ["fatal(test, null)", "fatal(test, exception)"]);
    }

    @("logWhenOffDoesNotLog") unittest
    {
        assert(logBoth(LogLevel.OFF).length == 0);
    }
}

import boot_tests.support : RegisterTests;

mixin RegisterTests;
