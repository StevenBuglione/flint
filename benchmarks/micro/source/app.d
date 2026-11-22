module app;

import core.time : MonoTime;
import flint.reactor : Backend;
import flint.web.micro_router : RouterCase, paths, routes;
import flint_bench_gc.sys.loopback : diagnostic;
import flint_bench_rest.profile : jsonBody;
import flint_micro.cpu_cases : CpuCases, arenaBytes;
import flint_micro.echo : connectionCount, echoPayload, echoTrial, payloadLength;
import flint_micro.timing : Batch, Trial, minimumNanoseconds, timeTrial, trialCount;
import std.digest : toHexString;
import std.digest.sha : sha256Of;
import std.json : JSONValue;
import std.stdio : writeln;
import std.string : join;

@safe:

private enum cpuBatch = 4096;

private struct Series
{
    Trial[trialCount] trials;
    size_t length;

    bool add(Trial trial) nothrow @nogc
    {
        if (trial.nanoseconds <= 0 || !trial.result.count || !trial.result.checksum || length == trials.length)
            return false;
        trials[length++] = trial;
        return true;
    }

    JSONValue values() const
    {
        auto samples = new double[length];
        foreach (index, ref trial; trials[0 .. length])
            samples[index] = cast(double) trial.nanoseconds / trial.result.count;
        return JSONValue(samples);
    }

    JSONValue observations() const
    {
        auto recorded = new JSONValue[length];
        foreach (index, ref trial; trials[0 .. length])
        {
            recorded[index] = JSONValue([
                "elapsed_nanoseconds": JSONValue(trial.nanoseconds),
                "operations": JSONValue(trial.result.count),
                "checksum": JSONValue(trial.result.checksum),
            ]);
        }
        return JSONValue(recorded);
    }
}

private bool cpuSeries(scope Batch work, bool smoke, ref Series series)
{
    foreach (_; 0 .. (smoke ? 1 : trialCount))
        if (!series.add(timeTrial(work, smoke ? 32 : cpuBatch, smoke)))
            return false;
    return true;
}

private bool echoSeries(bool smoke, out Backend backend, ref Series series)
{
    foreach (index; 0 .. (smoke ? 1 : trialCount))
    {
        Backend current;
        const sample = echoTrial(smoke, current);
        if (!series.add(sample) || (index && current != backend))
            return false;
        backend = current;
    }
    return true;
}

private string digest(scope const(char)[] data)
{
    const bytes = sha256Of(cast(const(ubyte)[]) data).toHexString();
    return bytes[].idup;
}

private JSONValue metadata(Backend backend, bool smoke, JSONValue observations)
{
    return JSONValue([
        "phase": JSONValue(smoke ? "smoke" : "production"),
        "clock_ticks_per_second": JSONValue(MonoTime.ticksPerSecond),
        "minimum_trial_ns": JSONValue(smoke ? 0 : minimumNanoseconds),
        "cpu_batch_operations": JSONValue(smoke ? 32 : cpuBatch),
        "arena_bytes": JSONValue(arenaBytes),
        "canonical_json_sha256": JSONValue(digest(jsonBody)),
        "router_routes": JSONValue(routes[]),
        "router_paths": JSONValue(paths[]),
        "router_routes_sha256": JSONValue(digest(routes[].join("\n"))),
        "router_paths_sha256": JSONValue(digest(paths[].join("\n"))),
        "reactor_backend": JSONValue(backend == Backend.ioUring ? "io_uring" : "epoll"),
        "reactor_connections": JSONValue(connectionCount),
        "reactor_payload_bytes": JSONValue(payloadLength),
        "reactor_payload_sha256": JSONValue(digest(echoPayload[])),
        "raw_observations": observations,
    ]);
}

private int failure(string workload)
{
    diagnostic("microbenchmark failed: " ~ workload);
    return 1;
}

private int run(bool smoke)
{
    auto cpu = new CpuCases;
    auto router = new RouterCase;
    if (!cpu.verifyArena() || !router.open())
        return failure("fixture initialization");
    Series arena, serde, validate, route, echo, toml;
    if (!cpuSeries(&cpu.arena, smoke, arena))
        return failure("arena");
    if (!cpuSeries(&cpu.serde, smoke, serde))
        return failure("serde");
    if (!cpuSeries(&cpu.validation, smoke, validate))
        return failure("validate");
    if (!cpuSeries(&router.run, smoke, route))
        return failure("router");
    Backend backend;
    if (!echoSeries(smoke, backend, echo))
        return failure("reactor_echo");
    if (!cpuSeries(&cpu.toml, smoke, toml))
        return failure("serde_toml");
    auto samples = JSONValue([
        "arena": arena.values(),
        "serde": serde.values(),
        "validate": validate.values(),
        "router": route.values(),
        "reactor_echo": echo.values(),
    ]);
    auto observations = JSONValue([
        "arena": arena.observations(),
        "serde": serde.observations(),
        "validate": validate.observations(),
        "router": route.observations(),
        "reactor_echo": echo.observations(),
        "serde_toml": toml.observations(),
    ]);
    writeln(JSONValue([
        "unit": JSONValue("nanoseconds_per_operation"),
        "micro": samples,
        "diagnostics": JSONValue(["serde_toml": toml.values()]),
        "metadata": metadata(backend, smoke, observations),
    ]).toString());
    return 0;
}

int main(string[] args)
{
    const smoke = args.length == 2 && args[1] == "--smoke";
    if (args.length != 1 && !smoke)
        return failure("usage: bench-micro [--smoke]");
    try
        return run(smoke);
    catch (Exception error)
        return failure(error.msg);
}
