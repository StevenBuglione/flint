/// Flint tests for Boot's default console line (`CONSOLE_LOG_PATTERN` in Boot's logback `defaults.xml`).
module boot_tests.logging_test;

import flint.boot.logging : ConsoleLogFormat, LogEvent, LogLevel, abbreviate, fit, timestamp;

@safe:

@("flint.logging.timestampIsIsoWithMillisAndOffset") unittest
{
    assert(timestamp(0, 0) == "1970-01-01T00:00:00.000Z");
    assert(timestamp(1_795_428_930_123, 60) == "2026-11-23T11:15:30.123+01:00");
    assert(timestamp(1_795_428_930_123, -300) == "2026-11-23T05:15:30.123-05:00");
}

@("flint.logging.loggerNameAbbreviation") unittest
{
    const restService = abbreviate("com.example.restservice.RestServiceApplication", 39);
    assert(restService == "c.e.restservice.RestServiceApplication");
    assert(abbreviate("org.springframework.boot.web.embedded.tomcat.TomcatWebServer",
            39) == "o.s.b.w.embedded.tomcat.TomcatWebServer");
    assert(abbreviate("Short", 39) == "Short");
}

@("flint.logging.paddingAndTruncation") unittest
{
    assert(fit("main", 15, true) == "           main");
    assert(fit("a-very-long-thread-name", 15, true) == "long-thread-name"[1 .. $]);
    assert(fit("x", 3, false) == "x  ");
}

@("flint.logging.consoleLine") unittest
{
    LogEvent event;
    event.timestampMillis = 1_795_428_930_123;
    event.level = LogLevel.INFO;
    event.pid = 12_345;
    event.logger = "com.example.restservice.RestServiceApplication";
    event.message = "Started RestServiceApplication in 0.512 seconds (process running for 0.6)";
    ConsoleLogFormat format;
    assert(format.format(event) == "2026-11-23T10:15:30.123Z  INFO 12345 --- [           main] "
            ~ "c.e.restservice.RestServiceApplication   : Started RestServiceApplication in 0.512 seconds "
            ~ "(process running for 0.6)\n");
    format.applicationName = "demo";
    import std.algorithm.searching : canFind;

    assert(format.format(event).canFind("--- [demo] [           main] "));
    event.level = LogLevel.WARN;
    format.ansi = true;
    assert(format.format(event).canFind("\x1b[33m WARN\x1b[0;39m"));
}

import boot_tests.support : RegisterTests;

mixin RegisterTests;
