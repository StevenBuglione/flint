module config_workload;

import core.memory : GC;
import core.time : MonoTime, msecs;
import std.conv : to;
import std.file : mkdir, rmdirRecurse, tempDir, write;
import std.path : buildPath;
import std.stdio : writeln;
import std.uuid : randomUUID;

@safe:

private string key(size_t index)
{
    return "field" ~ to!string(index);
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
        output ~= "\"" ~ key(index) ~ "\":" ~ to!string(first + index);
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

// SAFETY: This test-side counter reads druntime allocation bytes for the calling thread.
private ulong allocatedBytes() @trusted
{
    return GC.allocatedInCurrentThread();
}

private int execute(uint levels, alias loader)(string directory, bool measure)
{
    enum count = 16 * levels;
    enum expected = count * (count + 1) / 2;
    write(buildPath(directory, "application.json"), document(levels));
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
        writeln("fields=", count, " runs=", iterations, " elapsed_ns=", elapsed.total!"nsecs",
                " allocated_bytes=", allocatedBytes() - allocated);
    }
    return checksum;
}

/// Check both shapes and optionally measure time and allocations for repeated loads.
int runWorkload(alias loader)(bool measure)
{
    const directory = buildPath(tempDir(), "flint-config-probe-" ~ randomUUID().toString());
    mkdir(directory);
    scope (exit)
        rmdirRecurse(directory);
    const shallow = execute!(1, loader)(directory, measure);
    const deep = execute!(8, loader)(directory, measure);
    if (shallow < 0 || deep < 0)
        return 1;
    writeln("checksum=", shallow + deep);
    return 0;
}
