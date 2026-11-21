module os_workload;

import core.sys.posix.stdlib : mkdtemp;
import core.sys.posix.sys.resource : RUSAGE_SELF, getrusage, rusage;
import core.time : MonoTime;
import std.algorithm.sorting : sort;
import std.exception : enforce;
import std.file : mkdirRecurse, rmdirRecurse, tempDir, write;
import std.format : format;
import std.path : buildPath;
import std.stdio : writefln;

/// A probe decoder can consume the data synchronously without retaining storage.
alias ProbeSink = void delegate(scope const(ubyte)[]) @safe;
/// An implementation or reference child executor.
alias ExecuteProbe = int function(scope const(char[])[], scope ProbeSink);
/// An implementation or reference glob with the benchmark pattern and limits.
alias GlobProbe = string[]function(string, uint, uint);

private enum commandCount = 1000;
private enum streamBytes = 100UL * 1024 * 1024;
private enum globResults = 100_000;
private enum streamTrials = 6;
private enum globTrials = 4;

// SAFETY: This records only a numeric identity for comparison and never dereferences a retained pointer.
private size_t storageIdentity(scope const(ubyte)[] bytes) @trusted pure nothrow @nogc
{
    return cast(size_t) bytes.ptr;
}

private ulong spawnWorkload(ExecuteProbe execute)
{
    long[commandCount] times;
    uint exits;
    foreach (ref elapsed; times)
    {
        const started = MonoTime.currTime;
        enforce(execute(["/bin/sh", "-c", "exit 0"], null) == 0, "empty command did not exit successfully");
        elapsed = (MonoTime.currTime - started).total!"nsecs";
        ++exits;
    }
    times[].sort;
    writefln("empty_commands=%s startup_p50_ns=%s startup_p99_ns=%s", exits, times[499], times[989]);
    return exits;
}

private ulong streamingTrial(ExecuteProbe execute, out size_t changes)
{
    ulong consumed;
    size_t storage;
    ubyte nonzero;
    const result = execute(["/bin/sh", "-c", "head -c 104857600 /dev/zero"], (scope const(ubyte)[] bytes) @safe {
        const identity = storageIdentity(bytes);
        if (storage == 0)
            storage = identity;
        else if (storage != identity)
            ++changes;
        consumed += bytes.length;
        foreach (value; bytes)
            nonzero |= value;
    });
    enforce(result == 0 && consumed == streamBytes && nonzero == 0, "stream content did not match");
    enforce(storage != 0 && changes == 0, "stream did not reuse its read buffer");
    return consumed;
}

private ulong streamingWorkload(ExecuteProbe execute)
{
    ulong totalBytes;
    size_t storageChanges;
    const started = MonoTime.currTime;
    foreach (_; 0 .. streamTrials)
    {
        size_t changes;
        totalBytes += streamingTrial(execute, changes);
        storageChanges += changes;
    }
    const elapsed = (MonoTime.currTime - started).total!"nsecs";
    writefln("stream_trials=%s bytes_per_trial=%s stream_elapsed_ns=%s read_buffer_changes=%s",
            streamTrials, streamBytes, elapsed, storageChanges);
    return totalBytes;
}

private string temporaryRoot()
{
    auto path = buildPath(tempDir(), "flint-os-probe-XXXXXX").dup ~ '\0';
    enforce(mkdtemp(path.ptr) !is null, "could not create probe fixture");
    return path[0 .. $ - 1].idup;
}

private void createEntries(string root)
{
    foreach (bucket; 0 .. 100)
    {
        const directory = buildPath(root, format("bucket-%02d", bucket));
        mkdirRecurse(directory);
        foreach (index; 0 .. 1000)
            write(buildPath(directory, format("entry-%03d.txt", index)), "");
    }
}

private ulong globWorkload(GlobProbe glob)
{
    const root = temporaryRoot();
    scope (exit)
        rmdirRecurse(root);
    createEntries(root);

    const started = MonoTime.currTime;
    string[] entries;
    foreach (_; 0 .. globTrials)
    {
        entries = glob(root, 64, globResults);
        enforce(entries.length == globResults, "glob result count differs");
    }
    const elapsed = (MonoTime.currTime - started).total!"nsecs";
    enforce(entries[0] == "bucket-00/entry-000.txt", "unexpected first path");
    enforce(entries[$ - 1] == "bucket-99/entry-999.txt", "unexpected last path");
    enforce(glob(root, 64, globResults - 1) is null, "glob accepted too many results");
    enforce(glob(root, 1, globResults) is null, "glob exceeded its depth limit");

    ulong checksum;
    foreach (entry; entries)
    {
        foreach (byteValue; entry)
            checksum = checksum * 33 + cast(ubyte) byteValue;
    }
    writefln("glob_trials=%s results_per_trial=%s glob_elapsed_ns=%s", globTrials, entries.length, elapsed);
    return checksum;
}

/// Drive startup, streamed output, and 100,000 directory matches against both implementations.
int runProbe(ExecuteProbe execute, GlobProbe glob)
{
    const checksum = spawnWorkload(execute) + streamingWorkload(execute) + globWorkload(glob);
    rusage use;
    enforce(getrusage(RUSAGE_SELF, &use) == 0, "peak RSS unavailable");
    writefln("checksum=%s peak_rss_kib=%s", checksum, use.ru_maxrss);
    return 0;
}
