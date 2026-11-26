module available_cores;

import flint.engine.web : availableCores;

@("availableCores counts the affinity mask: every CPU allowed, then one")
@trusted unittest
{
    const all = availableCores();
    assert(all >= 1);
    version (linux)
    {
        import core.sys.linux.sched : CPU_COUNT, CPU_ISSET, CPU_SET, cpu_set_t, sched_getaffinity, sched_setaffinity;
        import core.thread : Thread;

        cpu_set_t allowed;
        assert(sched_getaffinity(0, allowed.sizeof, &allowed) == 0);
        assert(all == CPU_COUNT(&allowed));
        // Narrowed to one CPU on a thread of its own, so the test's own affinity is untouched.
        uint narrowed;
        auto thread = new Thread({
            cpu_set_t one;
            foreach (cpu; 0 .. cpu_set_t.sizeof * 8)
                if (CPU_COUNT(&one) == 0 && CPU_ISSET(cpu, &allowed))
                    CPU_SET(cpu, &one);
            assert(sched_setaffinity(0, one.sizeof, &one) == 0);
            narrowed = availableCores();
        });
        thread.start();
        thread.join();
        assert(narrowed == 1, "one allowed CPU");
    }
}
