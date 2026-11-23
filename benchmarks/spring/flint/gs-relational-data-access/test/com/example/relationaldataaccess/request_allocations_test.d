/++
The allocation gate for gs-relational-data-access (work-queue item 28, decisions 9a9aefa0;
policy/request-allocations.json). The app is a command-line runner with no requests, so its budget is one run: the
application starts, its `CommandLineRunner` creates the table, inserts the customers and queries them on the calling
thread, and the context closes. The allocations of every thread, the caller's included, are counted on druntime's
collector behind flint.arena's allocation counter. After a warm-up run, the smallest of three runs is compared with
the budget; the counts are deterministic. Set FLINT_REQUEST_ALLOCATIONS=record to print the cost instead of failing.
+/
module com.example.relationaldataaccess.request_allocations_test;

import com.example.relationaldataaccess : RelationalDataAccessApplication;
import core.memory : GC;
import flint.arena.gc : Allocations, installAllocationCounter, otherThreadsAllocations,
    recordAllocationSites, thisThreadAllocations, topAllocationSites, uninstallAllocationCounter;
import flint.boot : FlintApplication;
import std.json : JSONValue, parseJSON;

@safe:

private enum app = "gs-relational-data-access";
private enum budgetsPath = "../../../../policy/request-allocations.json";

/// Every thread's totals, the caller's included.
private Allocations everyThread()
{
    Allocations mine, others;
    assert(thisThreadAllocations(mine) && otherThreadsAllocations(others));
    return Allocations(mine.count + others.count, mine.bytes + others.bytes);
}

/// One run of the application, to its close.
private Allocations run()
{
    const before = everyThread();
    auto context = FlintApplication.run!RelationalDataAccessApplication([]);
    context.close();
    const after = everyThread();
    return Allocations(after.count - before.count, after.bytes - before.bytes);
}

@("gs-relational-data-access: GC allocations and bytes per run stay within policy/request-allocations.json")
unittest
{
    import std.conv : to;
    import std.file : readText;
    import std.process : environment;

    const recording = environment.get("FLINT_REQUEST_ALLOCATIONS") == "record";
    assert(installAllocationCounter(), "the counter wraps druntime's collector");
    scope (exit)
        uninstallAllocationCounter();
    Allocations clientBefore;
    assert(thisThreadAllocations(clientBefore));
    const druntimeBefore = GC.stats().allocatedInCurrentThread;

    cast(void) run(); // warm-up
    auto cost = Allocations(ulong.max, ulong.max);
    foreach (_; 0 .. 3)
    {
        const one = run();
        cost = Allocations(one.count < cost.count ? one.count : cost.count, one.bytes < cost.bytes
                ? one.bytes : cost.bytes);
    }

    // The counter's bytes are druntime's own: on this thread both counted the same allocations.
    Allocations clientAfter;
    assert(thisThreadAllocations(clientAfter));
    assert(clientAfter.bytes - clientBefore.bytes == GC.stats().allocatedInCurrentThread - druntimeBefore,
            "the counter's bytes differ from druntime's allocatedInCurrentThread");

    if (recording)
    {
        import std.stdio : writeln;

        writeln("FLINT_REQUEST_ALLOCATIONS ", app, "\n{\n \"run\": {\"allocations\": ", cost.count,
                ", \"bytes\": ", cost.bytes, "}\n}");
        return;
    }
    const budget = parseJSON(readText(budgetsPath))["apps"][app]["requests"]["run"];
    if (cost.count <= budget["allocations"].integer && cost.bytes <= budget["bytes"].integer)
        return;
    recordAllocationSites(true);
    cast(void) run();
    recordAllocationSites(false);
    string failure = "a run: " ~ cost.count.to!string ~ " allocations and " ~ cost.bytes.to!string
        ~ " bytes, over the budget of " ~ budget["allocations"].integer.to!string ~ " and "
        ~ budget["bytes"].integer.to!string ~ "; top sites:";
    foreach (site; topAllocationSites(10, true))
        failure ~= "\n    " ~ site;
    assert(false, failure);
}
