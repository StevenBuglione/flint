module app;

import os_workload : ProbeSink, runProbe;
import std.algorithm.sorting : sort;
import std.file : SpanMode, dirEntries;
import std.path : extension, relativePath;
import std.process : Redirect, pipeProcess, spawnProcess, wait;

private int subprocess(scope const(char[])[] argv, scope ProbeSink consume)
{
    if (consume is null)
        return wait(spawnProcess(argv));

    auto child = pipeProcess(argv, Redirect.stdout);
    ubyte[16_384] storage;
    while (true)
    {
        auto bytes = child.stdout.rawRead(storage[]);
        if (bytes.length == 0)
            break;
        consume(bytes);
    }
    child.stdout.close();
    return wait(child.pid);
}

private string[] matchEntries(string root, uint depth, uint limit)
{
    string[] matches;
    foreach (entry; dirEntries(root, SpanMode.depth, false))
    {
        if (entry.isDir || entry.name.extension() != ".txt")
            continue;
        const path = relativePath(entry.name, root);
        uint components = 1;
        foreach (value; path)
            if (value == '/')
                ++components;
        if (components > depth || matches.length == limit)
            return null;
        matches ~= path;
    }
    matches.sort;
    return matches;
}

/// Exercise the same fixture using the standard Linux process and directory library.
int main()
{
    return runProbe(&subprocess, &matchEntries);
}
