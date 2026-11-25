/++
The default parallel mark threads reach druntime before `main` and keep the program's own `rt_options`
(flint.arena.mark_threads). This test binary links `rt_options = ["gcopt=gc:flint"]` (tests/gc_selected.d).
+/
module flint.arena.mark_threads_test;

import flint.arena.mark_threads : defaultMarkThreads, markThreadsFor;

@safe:

private extern (C) extern __gshared string[] rt_options;

@("the default mark threads come ahead of the program's own rt_options, and druntime applied them")
@system unittest
{
    import core.gc.config : config;
    import flint.arena.gc : collectorName;

    version (linux)
    {
        import core.sys.linux.sched : CPU_COUNT, cpu_set_t, sched_getaffinity;

        cpu_set_t set;
        assert(sched_getaffinity(0, cpu_set_t.sizeof, &set) == 0);
        const expected = markThreadsFor(CPU_COUNT(&set));
        assert(defaultMarkThreads == expected);
    }
    const threads = defaultMarkThreads;
    assert(threads >= 0, "every supported target reports its CPUs");

    char[24] text;
    import core.stdc.stdio : snprintf;

    const length = snprintf(text.ptr, text.length, "gcopt=parallel:%d", threads);
    // Other C constructors (flint.arena.fixed_pools) may prepend their own entries, in link order.
    bool found;
    foreach (option; rt_options[0 .. $ - 1])
        found = found || option == text[0 .. length];
    assert(found, "the default is ahead of the program's own options");
    assert(rt_options[$ - 1] == "gcopt=gc:" ~ collectorName ~ " heapSizeFactor:4",
            "the program's own options follow, so they override");
    assert(config.parallel == threads, "druntime parsed the default before the collector started");
}
