module os_workload;

import core.stdc.stdio : printf, snprintf;
import core.stdc.stdlib : getenv, qsort;
import core.stdc.string : strlen;
import core.sys.posix.dirent : DIR, closedir, dirent, opendir, readdir;
import core.sys.posix.fcntl : O_CREAT, O_TRUNC, O_WRONLY, open;
import core.sys.posix.stdlib : mkdtemp;
import core.sys.posix.sys.resource : RUSAGE_SELF, getrusage, rusage;
import core.sys.posix.sys.stat : S_IFDIR, S_IFMT, lstat, mkdir, stat, stat_t;
import core.sys.posix.unistd : close, getcwd, rmdir, unlink;
import core.time : MonoTime;
import std.exception : enforce;

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
    qsort(times.ptr, times.length, long.sizeof, &compareTimes);
    printf("empty_commands=%u startup_p50_ns=%lld startup_p99_ns=%lld\n", exits, times[499], times[989]);
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
    printf("stream_trials=%d bytes_per_trial=%llu stream_elapsed_ns=%lld read_buffer_changes=%zu\n",
            streamTrials, streamBytes, elapsed, storageChanges);
    return totalBytes;
}

private extern (C) int compareTimes(const void* left, const void* right) nothrow @nogc
{
    const first = *cast(const(long)*) left;
    const second = *cast(const(long)*) right;
    return (first > second) - (first < second);
}

private bool pathExists(scope const(char)[] path)
{
    stat_t status;
    return stat((path ~ '\0').ptr, &status) == 0;
}

/// The same directory search order as the standard temporary directory lookup.
private string temporaryBase()
{
    foreach (name; ["TMPDIR", "TEMP", "TMP"])
    {
        const value = getenv((name ~ '\0').ptr);
        if (value !is null && *value != '\0' && pathExists(value[0 .. strlen(value)]))
            return value[0 .. strlen(value)].idup;
    }
    foreach (fallback; ["/tmp", "/var/tmp", "/usr/tmp"])
        if (pathExists(fallback))
            return fallback;
    char[4096] current;
    enforce(getcwd(current.ptr, current.length) !is null, "no temporary directory");
    return current[0 .. strlen(current.ptr)].idup;
}

private string join(string directory, scope const(char)[] name)
{
    const separator = directory.length && directory[$ - 1] == '/' ? "" : "/";
    return (directory ~ separator ~ name).idup;
}

private string temporaryRoot()
{
    auto path = join(temporaryBase(), "flint-os-probe-XXXXXX").dup ~ '\0';
    enforce(mkdtemp(path.ptr) !is null, "could not create probe fixture");
    return path[0 .. $ - 1].idup;
}

private const(char)[] formatted(return ref char[32] buffer, int length)
{
    enforce(length > 0 && length < buffer.length, "fixture name did not fit");
    return buffer[0 .. length];
}

private void createEntries(string root)
{
    foreach (bucket; 0 .. 100)
    {
        char[32] name;
        const directory = join(root, formatted(name, snprintf(name.ptr, name.length, "bucket-%02d", bucket)));
        enforce(mkdir((directory ~ '\0').ptr, 0x1ff) == 0, "could not create fixture bucket");
        foreach (index; 0 .. 1000)
        {
            const file = join(directory, formatted(name, snprintf(name.ptr, name.length, "entry-%03d.txt", index)));
            const descriptor = open((file ~ '\0').ptr, O_WRONLY | O_CREAT | O_TRUNC, 0x1b6);
            enforce(descriptor >= 0 && close(descriptor) == 0, "could not create fixture entry");
        }
    }
}

private void removeTree(string path)
{
    stat_t status;
    enforce(lstat((path ~ '\0').ptr, &status) == 0, "fixture entry vanished");
    if ((status.st_mode & S_IFMT) != S_IFDIR)
    {
        enforce(unlink((path ~ '\0').ptr) == 0, "could not remove fixture entry");
        return;
    }
    string[] children;
    DIR* directory = opendir((path ~ '\0').ptr);
    enforce(directory !is null, "could not open fixture directory");
    for (dirent* entry = readdir(directory); entry !is null; entry = readdir(directory))
    {
        const name = entry.d_name.ptr[0 .. strlen(entry.d_name.ptr)];
        if (name != "." && name != "..")
            children ~= join(path, name);
    }
    enforce(closedir(directory) == 0, "could not close fixture directory");
    foreach (child; children)
        removeTree(child);
    enforce(rmdir((path ~ '\0').ptr) == 0, "could not remove fixture directory");
}

private ulong globWorkload(GlobProbe glob)
{
    const root = temporaryRoot();
    scope (exit)
        removeTree(root);
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
    printf("glob_trials=%d results_per_trial=%zu glob_elapsed_ns=%lld\n", globTrials, entries.length, elapsed);
    return checksum;
}

/// Drive startup, streamed output, and 100,000 directory matches against both implementations.
int runProbe(ExecuteProbe execute, GlobProbe glob)
{
    const checksum = spawnWorkload(execute) + streamingWorkload(execute) + globWorkload(glob);
    rusage use;
    enforce(getrusage(RUSAGE_SELF, &use) == 0, "peak RSS unavailable");
    version (OSX)
    {
        // druntime names only the times of Darwin's rusage; ru_maxrss is the first opaque word, in bytes.
        printf("checksum=%llu peak_rss_kib=%ld\n", checksum, use.ru_opaque[0] / 1024);
    }
    else
        printf("checksum=%llu peak_rss_kib=%ld\n", checksum, use.ru_maxrss);
    return 0;
}
