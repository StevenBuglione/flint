/++
The program's default number of parallel mark threads: one for every CPU the process may run on except the one the
collecting thread marks on (gc-pools-ab, certified at ce87168d; docs/spring/phase1/gc.md).

druntime caps `gcopt=parallel` at the machine's hardware threads minus one, and ignores the process's CPU
affinity, so a server pinned to two CPUs of a 32-thread host starts 31 scan threads that compete for those two.
A C constructor here runs before druntime reads its options and puts `gcopt=parallel:<CPUs - 1>` first in
`rt_options`. druntime applies `gcopt` entries in order, the program's linked `rt_options` first, then `DRT_GCOPT`
(only where the program enables environment options), then `--DRT-gcopt`, so the program's own `rt_options` and an
operator's option both still override it.
A process allowed one CPU gets `parallel:0`, which marks on the collecting thread alone.

The CPUs counted are the affinity mask on Linux (`sched_getaffinity`) and Windows (`GetProcessAffinityMask`, the
process's processor group), and the online processors elsewhere on POSIX, which has no affinity call. When the count
is unavailable, or the program links more than `maxLinkedOptions` options, the program keeps druntime's default.
+/
module flint.arena.sys.gc.mark_threads;

@safe:

/// The parallel mark threads for a process allowed `cpus` CPUs: all but the collecting thread's own.
uint markThreadsFor(uint cpus) pure nothrow @nogc
{
    return cpus > 1 ? cpus - 1 : 0;
}

/// The mark threads this program's startup put first in `rt_options`, or -1 when it left the options unchanged.
// SAFETY: Reads one word that only the C constructor below writes, before any D code runs.
@trusted int defaultMarkThreads() nothrow @nogc
{
    return chosenThreads;
}

/// Most `rt_options` entries a program may link and still get the default prepended.
private enum maxLinkedOptions = 15;

private enum prefix = "gcopt=parallel:";

private __gshared string[maxLinkedOptions + 1] options;
private __gshared char[prefix.length + 10] text;
private __gshared int chosenThreads = -1;

/// druntime's options, or the program's own definition of them.
private extern (C) extern __gshared string[] rt_options;

/// The CPUs the process may run on, or 0 when the platform does not say.
// SAFETY: Each call writes only into the local out-parameters passed to it, sized by their own types.
private @trusted uint availableCpus() nothrow @nogc
{
    version (linux)
    {
        import core.sys.linux.sched : CPU_COUNT, cpu_set_t, sched_getaffinity;

        cpu_set_t set;
        if (sched_getaffinity(0, cpu_set_t.sizeof, &set) != 0)
            return 0; // more CPUs than a cpu_set_t holds: keep druntime's default
        return CPU_COUNT(&set);
    }
    else version (Windows)
    {
        import core.bitop : popcnt;
        import core.sys.windows.winbase : GetCurrentProcess, GetProcessAffinityMask;

        size_t process, system;
        if (!GetProcessAffinityMask(GetCurrentProcess(), &process, &system))
            return 0;
        return popcnt(process);
    }
    else version (Posix)
    {
        import core.sys.posix.unistd : _SC_NPROCESSORS_ONLN, sysconf;

        const online = sysconf(_SC_NPROCESSORS_ONLN);
        return online > 0 && online < uint.max ? cast(uint) online : 0;
    }
    else
        return 0;
}

/// Writes `value` in decimal at the start of `into` and returns its length.
private size_t decimal(uint value, scope char[] into) pure nothrow @nogc
{
    char[10] reversed;
    size_t length;
    do
    {
        reversed[length++] = cast(char)('0' + value % 10);
        value /= 10;
    }
    while (value != 0);
    foreach (i; 0 .. length)
        into[i] = reversed[length - 1 - i];
    return length;
}

// SAFETY: Runs once before druntime reads rt_options or any D thread exists; the module-owned buffers handed to
// druntime are never written again, so the immutable view of them holds, and the linked entries are copied as-is.
private pragma(crt_constructor) @trusted void setDefaultMarkThreads() nothrow @nogc
{
    const cpus = availableCpus();
    if (cpus == 0 || rt_options.length > maxLinkedOptions)
        return;
    const threads = markThreadsFor(cpus);
    text[0 .. prefix.length] = prefix;
    const length = prefix.length + decimal(threads, text[prefix.length .. $]);
    options[0] = cast(string) text[0 .. length];
    options[1 .. 1 + rt_options.length] = rt_options[];
    rt_options = options[0 .. 1 + rt_options.length];
    chosenThreads = threads;
}

@("the default leaves one CPU to the collecting thread and none below two CPUs")
unittest
{
    assert(markThreadsFor(0) == 0);
    assert(markThreadsFor(1) == 0);
    assert(markThreadsFor(2) == 1);
    assert(markThreadsFor(32) == 31);
}

@("decimal writes every digit, zero and the largest value included")
unittest
{
    char[10] buffer;
    assert(buffer[0 .. decimal(0, buffer[])] == "0");
    assert(buffer[0 .. decimal(31, buffer[])] == "31");
    assert(buffer[0 .. decimal(uint.max, buffer[])] == "4294967295");
}
