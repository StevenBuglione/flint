/++
Flint's garbage collector (ADR-030 section 4, owner decision b515505b).

When flint:arena is compiled with `-version=FlintCollector`, importing this module links the collector into the
program, registered with druntime under the name `flint`; without that version (the default until the collector is
measured to beat druntime's, gc.md) the program carries no second collector. The allocation counter below
works over whichever collector runs, druntime's by default.
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
static import flint.arena.sys.gc.counting;

/// The name to select with `--DRT-gcopt=gc:<name>` or `rt_options`.
enum collectorName = "flint";

/// The name of the Flint collector with mostly-concurrent marking (D3, docs/spring/phase1/gc.md section 3a).
enum concurrentCollectorName = "flint-concurrent";

/++
Switch the running Flint collector's mostly-concurrent marking on or off (D3, docs/spring/phase1/gc.md section 3a):
a collection marks from the static data and the registered roots and ranges while the program's threads keep
running, and stops them only for their stacks and the pages they wrote meanwhile. False when the Flint collector is
not running or the platform tracks no written pages (Linux only); collections then stop the world throughout.
+/
bool setConcurrentMarking(bool on) nothrow
{
    version (FlintCollector)
        return flint.arena.sys.gc.collector.setConcurrentMarking(on);
    else
        return false;
}

/// Collections the Flint collector began marking with the program running (`setConcurrentMarking`); zero otherwise.
size_t concurrentCollections() nothrow @nogc
{
    version (FlintCollector)
        return flint.arena.sys.gc.collector.concurrentCollections();
    else
        return 0;
}

/// GC allocations and their total bytes.
struct Allocations
{
    /// Allocations made.
    ulong count;
    /// Bytes the collector counted for them (`GC.stats().allocatedInCurrentThread`), block sizes included.
    ulong bytes;
}

/++
Put a counting proxy in front of the running collector (druntime's own in shipped programs), for the per-request
allocation gate (policy/request-allocations.json). Every call is forwarded unchanged; each thread counts its
allocations, and the bytes the collector itself counts for them. Call it before starting the threads to count.
False when it is installed already.
+/
bool installAllocationCounter() nothrow
{
    return flint.arena.sys.gc.counting.install();
}

/// Remove the counting proxy.
void uninstallAllocationCounter() nothrow
{
    flint.arena.sys.gc.counting.uninstall();
}

/// The allocations every thread but the caller has made since it first allocated under the counting proxy; false
/// when the proxy is not installed. A thread counts an allocation before returning it.
bool otherThreadsAllocations(out Allocations totals) nothrow @nogc
{
    if (!flint.arena.sys.gc.counting.isInstalled())
        return false;
    flint.arena.sys.gc.counting.otherThreads(totals.count, totals.bytes);
    return true;
}

/// The calling thread's allocations under the counting proxy; false when it is not installed.
bool thisThreadAllocations(out Allocations totals) nothrow @nogc
{
    if (!flint.arena.sys.gc.counting.isInstalled())
        return false;
    flint.arena.sys.gc.counting.thisThread(totals.count, totals.bytes);
    return true;
}

/// Record the call site of every counted allocation (Linux), up to `capacity` per thread, clearing earlier
/// records; or stop recording.
void recordAllocationSites(bool on, size_t capacity = 4_096) nothrow @nogc
{
    flint.arena.sys.gc.counting.recordCallSites(on, capacity);
}

/// The live set by allocation site, after a collection: the recorded allocations still allocated, as
/// "bytes B  count  scanned-bytes B  function" lines, largest first. Record from start-up with enough capacity.
string[] liveAllocationSites(size_t limit, bool includeCaller = true)
{
    return flint.arena.sys.gc.counting.liveSites(limit, includeCaller);
}

/// The `limit` functions that made the most recorded allocations on other threads (and the caller's, with
/// `includeCaller`), as "count  bytes B  function" lines. Stop recording first.
string[] topAllocationSites(size_t limit, bool includeCaller = false)
{
    return flint.arena.sys.gc.counting.topSites(limit, includeCaller);
}

/// The same, ordered by the bytes they allocated, as "bytes B  count  function" lines.
string[] topAllocationSitesByBytes(size_t limit, bool includeCaller = false)
{
    return flint.arena.sys.gc.counting.topSitesByBytes(limit, includeCaller);
}
