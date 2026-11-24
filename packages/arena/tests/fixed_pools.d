/++
The fixed 1 MiB pools reach druntime before `main` and keep the program's own `rt_options`
(flint.arena.fixed_pools). This test binary links `rt_options = ["gcopt=gc:flint"]` (tests/gc_selected.d) and
flint.arena.mark_threads, whose C constructor also prepends an entry.
+/
module flint.arena.fixed_pools_test;

import flint.arena.fixed_pools : fixedPoolsApplied, fixedPoolsOption;

@safe:

private extern (C) extern __gshared string[] rt_options;

@("the fixed pools come ahead of the program's own rt_options, and druntime applied them")
@system unittest
{
    import core.gc.config : config;
    import flint.arena.gc : collectorName;

    assert(fixedPoolsApplied());
    bool found;
    foreach (option; rt_options[0 .. $ - 1])
        found = found || option == "gcopt=" ~ fixedPoolsOption;
    assert(found, "the default is ahead of the program's own options");
    assert(rt_options[$ - 1] == "gcopt=gc:" ~ collectorName, "the program's own options come last, so they override");
    assert(config.minPoolSize == 1 << 20, "druntime parsed minPoolSize:1 before the collector started");
    assert(config.incPoolSize == 0, "druntime parsed incPoolSize:0 before the collector started");
}
