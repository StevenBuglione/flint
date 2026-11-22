module app;

import flint.arena : Status;
import flint.conc : Context;
import flint.os : GlobOptions, glob, run, stream;
import os_workload : ProbeSink, runProbe;
import std.exception : enforce;

private int subprocess(scope const(char[])[] argv, scope ProbeSink consume)
{
    Context context;
    const result = consume is null ? run(context, argv) : stream(context, argv, consume, null);
    enforce(result.ok, result.error.message);
    return result.value.code;
}

private string[] matchEntries(string root, uint depth, uint limit)
{
    auto result = glob(root, "**/*.txt", GlobOptions(false, depth, limit));
    if (result.error.code == Status.resourceExhausted)
        return null;
    enforce(result.ok, result.error.message);
    return result.value;
}

/// Exercise the Flint subprocess and root-relative glob paths.
int main()
{
    return runProbe(&subprocess, &matchEntries);
}
