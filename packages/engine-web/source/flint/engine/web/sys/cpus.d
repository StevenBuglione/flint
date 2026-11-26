module flint.engine.web.sys.cpus;

@safe:

/// The CPUs this process may run on: its affinity mask on Linux and Windows, the online CPUs on other POSIX
/// systems; 1 when the platform does not say.
// SAFETY: Each call writes only into the local out-parameters passed to it, sized by their own types.
package(flint.engine.web) @trusted uint availableCpuCount() nothrow @nogc
{
    uint count;
    version (linux)
    {
        import core.sys.linux.sched : CPU_COUNT, cpu_set_t, sched_getaffinity;

        cpu_set_t set;
        if (sched_getaffinity(0, cpu_set_t.sizeof, &set) == 0)
            count = CPU_COUNT(&set);
    }
    else version (Windows)
    {
        import core.bitop : popcnt;
        import core.sys.windows.winbase : GetCurrentProcess, GetProcessAffinityMask;

        size_t process, system;
        if (GetProcessAffinityMask(GetCurrentProcess(), &process, &system))
            count = popcnt(process);
    }
    else version (Posix)
    {
        import core.sys.posix.unistd : _SC_NPROCESSORS_ONLN, sysconf;

        const online = sysconf(_SC_NPROCESSORS_ONLN);
        count = online > 0 && online < uint.max ? cast(uint) online : 0;
    }
    return count == 0 ? 1 : count;
}
