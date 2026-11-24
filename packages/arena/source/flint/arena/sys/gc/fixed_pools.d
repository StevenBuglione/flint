/++
The program's default collector pools: fixed 1 MiB pools (`gcopt=minPoolSize:1 incPoolSize:0`), the 1 MiB arm of
fast-path-pools-ab (certified at 5d7890bd; docs/spring/phase1/decisions.md, provisional for B2 at 236459b6).

druntime's pools start at `minPoolSize` (1 MB) and each new pool is `incPoolSize` (3 MB) larger than the last, so a
server whose live set outgrows the first pools maps a 7 MiB pool and fills it with garbage between collections. With
`incPoolSize:0` every pool is 1 MiB: the heap follows the live set in 1 MiB steps, for more frequent collections.
A C constructor here runs before druntime reads its options and puts the setting first in `rt_options`. druntime
applies `gcopt` entries in order, the program's linked `rt_options` first, then `DRT_GCOPT` (only where the program
enables environment options), then `--DRT-gcopt`, so the program's own `rt_options` and an operator's option both
override either field. When the program links more than `maxLinkedOptions` options, it keeps druntime's pools.
+/
module flint.arena.sys.gc.fixed_pools;

@safe:

/// The `gcopt` value this program's startup puts first in `rt_options`.
enum fixedPoolsOption = "minPoolSize:1 incPoolSize:0";

/// Whether this program's startup put `fixedPoolsOption` first in `rt_options`.
// SAFETY: Reads one word that only the C constructor below writes, before any D code runs.
@trusted bool fixedPoolsApplied() nothrow @nogc
{
    return applied;
}

/// Most `rt_options` entries a program may link and still get the default prepended.
private enum maxLinkedOptions = 15;

private __gshared string[maxLinkedOptions + 1] options;
private __gshared bool applied;

/// druntime's options, or the program's own definition of them.
private extern (C) extern __gshared string[] rt_options;

// SAFETY: Runs once before druntime reads rt_options or any D thread exists; the module-owned array handed to
// druntime is never written again, and its entries are a string literal and the linked entries copied as-is.
private pragma(crt_constructor) @trusted void setFixedPools() nothrow @nogc
{
    if (rt_options.length > maxLinkedOptions)
        return;
    options[0] = "gcopt=" ~ fixedPoolsOption;
    options[1 .. 1 + rt_options.length] = rt_options[];
    rt_options = options[0 .. 1 + rt_options.length];
    applied = true;
}
