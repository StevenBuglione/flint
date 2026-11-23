/++
Flint's garbage collector (ADR-030 section 4, owner decision b515505b).

When flint:arena is compiled with `-version=FlintCollector`, importing this module links the collector into the
program, registered with druntime under the name `flint`; without that version (the default until the collector is
measured to beat druntime's, gc.md) the program carries no second collector, and the functions below report it.
druntime still starts its own collector unless the program selects this one, either at run time with
`--DRT-gcopt=gc:flint` or in the binary with `extern (C) __gshared string[] rt_options = ["gcopt=gc:flint"];`.
Selecting `gc:conservative` switches back.

The collector lives in `flint.arena.sys.gc`. It starts as a port of druntime's conservative collector, which
behaves the same. Per-thread allocation caches and page release follow as separately measured steps
(docs/spring/phase1/gc.md). This module is not part of the BetterC surface of `flint.arena`, which never imports it.
+/
module flint.arena.gc;

@safe:

static import flint.arena.sys.gc.collector;

/// The name to select with `--DRT-gcopt=gc:<name>` or `rt_options`.
enum collectorName = "flint";

/// GC allocations and their total bytes.
struct Allocations
{
    /// Allocations made.
    ulong count;
    /// Bytes they took, rounded up to the collector's block sizes.
    ulong bytes;
}

/++
The allocations every thread but the caller has made so far, as the Flint collector counts them; false when another
collector runs. The per-request allocation gate (policy/request-allocations.json) reads it before and after a test
client's requests, which a server answers on its own threads. A thread counts an allocation before returning it.
+/
bool otherThreadsAllocations(out Allocations totals) nothrow @nogc
{
    version (FlintCollector)
        return flint.arena.sys.gc.collector.otherThreadsAllocations(totals.count, totals.bytes);
    else
        return false;
}
