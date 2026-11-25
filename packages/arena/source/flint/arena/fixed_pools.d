/++
Importing this module gives the program fixed 1 MiB collector pools and a heap size factor of 3
(`gcopt=minPoolSize:1 incPoolSize:0 heapSizeFactor:3`), set before `main`: the heap grows in 1 MiB pools rather than
druntime's 1, 4, 7 MB sequence, and to 3 times the live set rather than 2 before the next collection. The program's
own `rt_options` and an operator's `--DRT-gcopt` still override either. Flint Boot imports it. The pools are the 1 MiB
arm of fast-path-pools-ab (docs/spring/phase1/decisions.md, performance-playbook R-18); the factor is the owner's
decision dc0ca836.
+/
module flint.arena.fixed_pools;

@safe:

static import flint.arena.sys.gc.fixed_pools;

/// The `gcopt` value the default puts first in `rt_options`.
alias fixedPoolsOption = flint.arena.sys.gc.fixed_pools.fixedPoolsOption;

/// Whether this program's startup put the default first in `rt_options` (false when the program links too many
/// options of its own).
alias fixedPoolsApplied = flint.arena.sys.gc.fixed_pools.fixedPoolsApplied;

// A module constructor puts this module in its importers' ModuleInfo chains, which the linker follows into an
// archive, and the call below then links the module holding the C constructor (as flint.arena.mark_threads).
shared static this() nothrow @nogc
{
    cast(void) fixedPoolsApplied();
}
