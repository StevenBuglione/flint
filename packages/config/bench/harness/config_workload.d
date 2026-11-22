module config_workload;

import core.memory : GC;
import core.stdc.stdio : printf;
import core.time : MonoTime, msecs;

@safe:

private string decimal(ulong value) pure nothrow
{
    char[20] digits;
    size_t start = digits.length;
    do
    {
        digits[--start] = cast(char)('0' + value % 10);
        value /= 10;
    }
    while (value != 0);
    return digits[start .. $].idup;
}

private string key(size_t index)
{
    return "field" ~ decimal(index);
}

private string fieldDeclarations()
{
    string output;
    foreach (index; 0 .. 16)
        output ~= "int " ~ key(index) ~ ";";
    return output;
}

/// Sixteen scalar fields per level, up to eight levels.
struct Layer(uint levels)
{
    mixin(fieldDeclarations());
    static if (levels > 1)
    {
        /// The remaining levels in the same workload.
        Layer!(levels - 1) child;
    }
}

private string document(uint levels, uint first = 1)
{
    string output = "{";
    foreach (index; 0 .. 16)
    {
        if (index != 0)
            output ~= ',';
        output ~= "\"" ~ key(index) ~ "\":" ~ decimal(first + index);
    }
    if (levels > 1)
        output ~= ",\"child\":" ~ document(levels - 1, first + 16);
    return output ~ "}";
}

private int observed(uint levels)(scope const ref Layer!levels bound)
{
    int total;
    static foreach (index; 0 .. 16)
        total += __traits(getMember, bound, key(index));
    static if (levels > 1)
        total += observed(bound.child);
    return total;
}

// SAFETY: getenv results are NUL-terminated and copied before use; the mkdtemp template is a
// NUL-terminated GC buffer that mkdtemp rewrites in place within its length.
private string fixtureDirectory() @trusted
{
    import core.stdc.stdlib : getenv;
    import core.stdc.string : strlen;
    import core.sys.posix.stdlib : mkdtemp;
    import core.sys.posix.sys.stat : stat, stat_t;

    string base;
    foreach (name; ["TMPDIR", "TEMP", "TMP"])
    {
        const value = getenv((name ~ '\0').ptr);
        stat_t status;
        if (base is null && value !is null && *value != '\0' && stat(value, &status) == 0)
            base = value[0 .. strlen(value)].idup;
    }
    foreach (fallback; ["/tmp", "/var/tmp", "/usr/tmp"])
    {
        stat_t status;
        if (base is null && stat((fallback ~ '\0').ptr, &status) == 0)
            base = fallback;
    }
    if (base is null)
        base = ".";
    const separator = base[$ - 1] == '/' ? "" : "/";
    auto path = (base ~ separator ~ "flint-config-probe-XXXXXX\0").dup;
    if (mkdtemp(path.ptr) is null)
        throw new Exception("could not create the config fixture directory");
    return path[0 .. $ - 1].idup;
}

// SAFETY: The path is a NUL-terminated GC copy; fwrite reads exactly the live document slice.
private void writeDocument(string directory, string text) @trusted
{
    import core.stdc.stdio : fclose, fopen, fwrite;

    auto target = fopen((directory ~ "/application.json\0").ptr, "wb");
    if (target is null)
        throw new Exception("could not open the config fixture document");
    const written = fwrite(text.ptr, 1, text.length, target);
    if (fclose(target) != 0 || written != text.length)
        throw new Exception("could not write the config fixture document");
}

// SAFETY: Both paths are NUL-terminated GC copies passed to synchronous libc calls.
private void removeFixture(string directory) @trusted
{
    import core.sys.posix.unistd : rmdir, unlink;

    unlink((directory ~ "/application.json\0").ptr);
    if (rmdir((directory ~ '\0').ptr) != 0)
        throw new Exception("could not remove the config fixture directory");
}

// SAFETY: Fixed NUL-terminated literal format with matching scalar arguments.
private void printRuns(uint fields, ulong runs, long elapsed, ulong allocated) @trusted nothrow @nogc
{
    printf("fields=%u runs=%llu elapsed_ns=%lld allocated_bytes=%llu\n", fields, runs, elapsed, allocated);
}

// SAFETY: Fixed NUL-terminated literal format with a matching scalar argument.
private void printChecksum(int checksum) @trusted nothrow @nogc
{
    printf("checksum=%d\n", checksum);
}

// SAFETY: This test-side counter reads druntime allocation bytes for the calling thread.
private ulong allocatedBytes() @trusted
{
    return GC.allocatedInCurrentThread();
}

private int execute(uint levels, alias loader)(string directory, bool measure)
{
    enum count = 16 * levels;
    enum expected = count * (count + 1) / 2;
    writeDocument(directory, document(levels));
    const allocated = allocatedBytes();
    const started = MonoTime.currTime;
    ulong iterations;
    int checksum;
    do
    {
        const result = loader!levels(directory);
        if (!result.ok)
            return -1;
        checksum = observed(result.value);
        if (checksum != expected)
            return -1;
        ++iterations;
    }
    while (measure && MonoTime.currTime - started < 150.msecs);
    if (measure)
    {
        const elapsed = MonoTime.currTime - started;
        printRuns(count, iterations, elapsed.total!"nsecs", allocatedBytes() - allocated);
    }
    return checksum;
}

/// Check both shapes and optionally measure time and allocations for repeated loads.
int runWorkload(alias loader)(bool measure)
{
    const directory = fixtureDirectory();
    scope (exit)
        removeFixture(directory);
    const shallow = execute!(1, loader)(directory, measure);
    const deep = execute!(8, loader)(directory, measure);
    if (shallow < 0 || deep < 0)
        return 1;
    printChecksum(shallow + deep);
    return 0;
}
