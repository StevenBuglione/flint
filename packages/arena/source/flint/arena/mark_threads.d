/++
Importing this module gives the program druntime's affinity-aware default for parallel marking: one mark thread
for every CPU the process may run on except the collecting thread's own (`gcopt=parallel:<CPUs - 1>`), set before
`main`. The program's own `rt_options` and an operator's `--DRT-gcopt` still override it. Flint Boot imports it;
the measurement behind the default is gc-pools-ab (ce87168d, docs/spring/phase1/gc.md and performance-playbook R-26).
+/
module flint.arena.mark_threads;

@safe:

static import flint.arena.sys.gc.mark_threads;

/// The parallel mark threads for a process allowed `cpus` CPUs: all but the collecting thread's own.
alias markThreadsFor = flint.arena.sys.gc.mark_threads.markThreadsFor;

/// The mark threads this program's startup put first in `rt_options`, or -1 when it left the options unchanged
/// (the platform did not report its CPUs, or the program links too many options of its own).
alias defaultMarkThreads = flint.arena.sys.gc.mark_threads.defaultMarkThreads;

// A module constructor puts this module in its importers' ModuleInfo chains, which the linker follows into an
// archive, and the call below then links the module holding the C constructor. A module with only a C constructor is
// never pulled out of a library by an import (boot, 2026-11-24; checked on DMD and LDC).
shared static this() nothrow @nogc
{
    cast(void) defaultMarkThreads();
}
