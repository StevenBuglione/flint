module log_workload;

import core.atomic : atomicLoad, atomicStore;
import core.stdc.stdio : printf;
import core.stdc.stdlib : qsort;

version (OSX)
{
    import core.sys.posix.time : timespec;

    // <time.h>: druntime declares neither for Darwin; CLOCK_MONOTONIC is 6 there (ADR-024).
    private enum int CLOCK_MONOTONIC = 6;
    private extern (C) int clock_gettime(int clock, timespec* value) @system nothrow @nogc;
}
else
    import core.sys.posix.time : CLOCK_MONOTONIC, clock_gettime, timespec;
import flint.arena : Status;
import std.exception : enforce;

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

// SAFETY: getenv returns null or a NUL-terminated environment string, copied before returning.
private string sampleDirectory() @trusted
{
    import core.stdc.stdlib : getenv;
    import core.stdc.string : strlen;

    const value = getenv("FLINT_LOG_PROBE_SAMPLE_DIR");
    return value is null ? "" : value[0 .. strlen(value)].idup;
}

// SAFETY: Every path passed to mkdir is a NUL-terminated GC copy of a directory prefix.
private void makeDirectories(string directory) @trusted
{
    import core.stdc.errno : EEXIST, errno;
    import core.sys.posix.sys.stat : mkdir;

    foreach (end; 1 .. directory.length + 1)
    {
        if (end != directory.length && directory[end] != '/')
            continue;
        const path = directory[0 .. end] ~ '\0';
        enforce(mkdir(path.ptr, 0x1ff) == 0 || errno == EEXIST, "sample directory creation failed");
    }
}

// SAFETY: The path is a NUL-terminated GC copy; fwrite reads exactly the live timing slice.
private void writeSamples(string path, scope const(long)[] timings) @trusted
{
    import core.stdc.stdio : fclose, fopen, fwrite;

    auto target = fopen((path ~ '\0').ptr, "wb");
    enforce(target !is null, "sample file could not be opened");
    const written = fwrite(timings.ptr, long.sizeof, timings.length, target);
    enforce(fclose(target) == 0 && written == timings.length, "sample file write failed");
}

private void storeSamples(string name, scope const(long)[] timings)
{
    const directory = sampleDirectory();
    if (directory.length == 0)
        return;
    makeDirectories(directory);
    const separator = directory[$ - 1] == '/' ? "" : "/";
    writeSamples(directory ~ separator ~ name ~ "-ns.i64", timings);
}

// SAFETY: qsort passes this comparator two element addresses inside the slice given to sortTimings.
private extern (C) int compareTimings(const void* left, const void* right) @trusted nothrow @nogc
{
    const first = *cast(const(long)*) left;
    const second = *cast(const(long)*) right;
    return (first > second) - (first < second);
}

// SAFETY: The base pointer, element count and element size describe exactly the live slice.
private void sortTimings(scope long[] timings) @trusted nothrow @nogc
{
    qsort(timings.ptr, timings.length, long.sizeof, &compareTimings);
}

// SAFETY: Fixed NUL-terminated literal format; the name is printed with its explicit length and
// every scalar matches its conversion.
private void printCase(string name, size_t attempts, size_t dropped, long p99, long elapsed) @trusted nothrow @nogc
{
    printf("case=%.*s attempts=%zu dropped=%zu producer_p99_ns=%lld elapsed_ns=%lld\n",
            cast(int) name.length, name.ptr, attempts, dropped, p99, elapsed);
}

// SAFETY: Fixed NUL-terminated literal format with matching scalar arguments.
private void printDelivered(ulong delivered, ulong bytes, double rate, ulong checksum) @trusted nothrow @nogc
{
    printf("delivered=%llu bytes=%llu consumer_lines_per_second=%.2f checksum=%llu\n", delivered,
            bytes, rate, checksum);
}

private void report(string name, scope long[] timings, size_t dropped, long elapsed)
{
    storeSamples(name, timings);
    sortTimings(timings);
    const nearest = (timings.length * 99 + 99) / 100;
    printCase(name, timings.length, dropped, timings[nearest - 1], elapsed);
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
    printDelivered(capture.count, capture.bytes, 4096.0e9 / activeNanos, capture.checksum);
    return 0;
}
