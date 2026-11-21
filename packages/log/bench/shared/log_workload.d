module log_workload;

import core.atomic : atomicLoad, atomicStore;
import core.sys.posix.time : CLOCK_MONOTONIC, clock_gettime, timespec;
import flint.arena : Status;
import std.algorithm.sorting : sort;
import std.exception : enforce;
import std.stdio : writefln;

@safe:

/// Producer slots available to the single benchmark producer.
enum batchSize = 4;
/// Maximum benchmark message, before metadata and delimiters.
enum longMessage = 4096;
/// Number of output lines traversed by both feature and reference fixtures.
enum expectedDeliveries = 2 * 2048 + batchSize;

/// Match the fixture's info threshold or intentionally exercise level filtering.
alias Submit = Status delegate(bool enabled, scope const(char)[] message) @safe nothrow @nogc;
/// Wait for all published records from within the fixture driver.
alias Drain = Status delegate() @safe nothrow @nogc;

/// The same sink measures both variants and derives an observable checksum from emitted message bytes.
struct Capture
{
    private shared bool blocked;
    private ulong count;
    private ulong bytes;
    private ulong checksum;

    /// A blocked sink leaves the record pending in the bounded queue.
    void hold(bool value) nothrow @nogc
    {
        atomicStore(blocked, value);
    }

    /// Consume an entire serialized record or request a retry.
    Status take(scope const(char)[] line) nothrow @nogc
    {
        if (atomicLoad(blocked))
            return Status.unavailable;
        enum prefix = "\"message\":\"";
        if (line.length <= prefix.length || line[$ - 1] != '\n')
            return Status.ioError;
        foreach (index; 0 .. line.length - prefix.length)
        {
            if (line[index .. index + prefix.length] != prefix)
                continue;
            return message(line[index + prefix.length .. $]);
        }
        return Status.ioError;
    }

    private Status message(scope const(char)[] text) nothrow @nogc
    {
        size_t length;
        ulong content = 5381;
        while (length < text.length && text[length] != '"')
        {
            const value = text[length++];
            if (value != 's' && value != 'L')
                return Status.ioError;
            content = content * 33 + value;
        }
        if (length != 128 && length != longMessage)
            return Status.ioError;
        ++count;
        bytes += length;
        checksum = checksum * 33 + content;
        return Status.ok;
    }
}

// SAFETY: The monotonic clock writes into one local timespec without retaining memory.
private long monotonicNanos() @trusted
{
    timespec current;
    enforce(clock_gettime(CLOCK_MONOTONIC, &current) == 0, "benchmark clock failed");
    return current.tv_sec * 1_000_000_000L + current.tv_nsec;
}

private struct Run
{
    Submit submit;
    Drain drain;
    Capture* capture;

    private long active(string name, scope const(char)[] message)
    {
        long[2048] timings;
        const started = monotonicNanos();
        foreach (index, ref elapsed; timings[])
        {
            const before = monotonicNanos();
            enforce(submit(true, message) == Status.ok, "active log unexpectedly dropped");
            elapsed = monotonicNanos() - before;
            if ((index + 1) % batchSize == 0)
                enforce(drain() == Status.ok, "logger did not deliver the active batch");
        }
        const nanos = monotonicNanos() - started;
        report(name, timings[], 0, nanos);
        return nanos;
    }

    private void disabled(scope const(char)[] message)
    {
        auto times = new long[4_194_304];
        const started = monotonicNanos();
        foreach (ref elapsed; times)
        {
            const before = monotonicNanos();
            enforce(submit(false, message) == Status.ok, "disabled log call failed");
            elapsed = monotonicNanos() - before;
        }
        enforce(drain() == Status.ok && capture.count == 0, "disabled calls emitted records");
        report("disabled", times, 0, monotonicNanos() - started);
    }

    private void saturated(scope const(char)[] message)
    {
        auto times = new long[4_194_304];
        capture.hold(true);
        scope (exit)
            capture.hold(false);
        size_t dropped;
        const started = monotonicNanos();
        foreach (index, ref elapsed; times)
        {
            const before = monotonicNanos();
            const status = submit(true, message);
            elapsed = monotonicNanos() - before;
            if (index < batchSize)
                enforce(status == Status.ok, "saturated fixture did not fill its bounded slots");
            else
            {
                enforce(status == Status.resourceExhausted, "full producer did not report a drop");
                ++dropped;
            }
        }
        report("saturated", times, dropped, monotonicNanos() - started);
    }
}

private void storeSamples(string name, scope const(long)[] timings)
{
    import std.file : mkdirRecurse;
    import std.path : buildPath;
    import std.process : environment;
    import std.stdio : File;

    const directory = environment.get("FLINT_LOG_PROBE_SAMPLE_DIR");
    if (directory.length == 0)
        return;
    mkdirRecurse(directory);
    auto target = File(buildPath(directory, name ~ "-ns.i64"), "wb");
    target.rawWrite(timings);
}

private void report(string name, scope long[] timings, size_t dropped, long elapsed)
{
    storeSamples(name, timings);
    timings.sort;
    const nearest = (timings.length * 99 + 99) / 100;
    writefln("case=%s attempts=%s dropped=%s producer_p99_ns=%s elapsed_ns=%s", name,
            timings.length, dropped, timings[nearest - 1], elapsed);
}

/// Run the fixed filtering, accepted data, saturation and consumer throughput workloads.
int runProbe(Submit submit, Drain drain, Capture* capture)
{
    char[128] shortBody;
    char[longMessage] longBody;
    shortBody[] = 's';
    longBody[] = 'L';
    auto workload = Run(submit, drain, capture);
    workload.disabled(shortBody[]);
    const activeNanos = workload.active("accepted_128", shortBody[]) + workload.active("accepted_4096", longBody[]);
    workload.saturated(shortBody[]);
    enforce(drain() == Status.ok, "saturation batch did not drain");
    enforce(capture.count == expectedDeliveries, "fixture lost accepted records");
    const expectedBytes = 2048UL * (shortBody.length + longBody.length) + batchSize * shortBody.length;
    enforce(capture.bytes == expectedBytes, "emitted message sizes changed");
    writefln("delivered=%s bytes=%s consumer_lines_per_second=%.2f checksum=%s", capture.count,
            capture.bytes, 4096.0e9 / activeNanos, capture.checksum);
    return 0;
}
