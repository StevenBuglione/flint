module app;

import flint.arena : Status;
import flint.log : Level, LogOptions, Logger;
import log_workload : Capture, expectedDeliveries, runProbe;
import std.exception : enforce;

/// Exercise the bounded Flint producer/consumer with the common sink.
int main()
{
    auto capture = new Capture;
    LogOptions options;
    options.maxRecordBytes = 8192;
    options.sink = &capture.take;
    auto configured = Logger.create(options);
    enforce(configured.ok, configured.error.message);
    auto logger = configured.value;
    scope (exit)
        logger.close();

    const result = runProbe((bool enabled, scope const(char)[] message) @safe nothrow @nogc {
        return logger.write(enabled ? Level.info : Level.debug_, message, null);
    }, () @safe nothrow @nogc { return logger.flush(5000).code; }, capture);
    const stats = logger.stats();
    enforce(stats.accepted[Level.info] == expectedDeliveries && stats.delivered == expectedDeliveries,
            "Flint counters disagree with observed output");
    return result;
}
