/++
Opt-in counters that split a request's SQL time into lease wait, lease hold, statement drive and socket wait
(the owner-1 diagnostic, docs/spring/phase1/throughput-plan-astra.md change 2). Off by default: every hook then
costs one relaxed load. `FLINT_DIAG_COUNTERS=<file>` at the first pool open turns them on; at exit, and when a pool
closes, the counters replace `<file>` (written beside it, then renamed) as proof-harness's `flint.diag-counters/1`
JSON. The counters are process-wide atomics, so a diagnostic run measures slightly more contention than a scored
one; keep them out of scored runs.
+/
module flint.engine.sql.sys.diagnostics;

import core.atomic : MemoryOrder, atomicLoad, atomicOp, atomicStore, cas;
import flint.conc : Deadline;

@safe:

/// A snapshot of the counters. Times are monotonic nanoseconds summed over all events.
struct SqlDiagnostics
{
    /// Leases acquired, and those that queued behind other waiters first.
    ulong acquires, queuedAcquires;
    /// Time from entering `acquire` to holding a lease, summed and at most.
    ulong leaseWaitNanos, maxLeaseWaitNanos;
    /// Leases released, and their time from acquisition to release, summed and at most.
    ulong releases, leaseHoldNanos, maxLeaseHoldNanos;
    /// Releases made while waiters were queued, and the time from such a release until a queued waiter
    /// acquired: idle lease capacity behind a sleeping queue head shows up here.
    ulong releasesWithWaiters, handoffs, handoffNanos;
    /// Most waiters queued on one pool at once.
    ulong maxQueuedWaiters;
    /// Statements run, their time from start to completion (socket waits included) summed and at most, and rows
    /// produced.
    ulong statements, driveNanos, maxDriveNanos, rows;
    /// Fiber waits for socket readiness inside statements, and their time summed and at most.
    ulong socketWaits, socketWaitNanos, maxSocketWaitNanos;
}

private shared bool enabled;
private shared bool decided;

private shared ulong acquires, queuedAcquires, leaseWaitNanos, maxLeaseWaitNanos;
private shared ulong releases, leaseHoldNanos, maxLeaseHoldNanos, releasesWithWaiters, handoffs, handoffNanos;
private shared ulong maxQueuedWaiters, statements, driveNanos, maxDriveNanos, rows;
private shared ulong socketWaits, socketWaitNanos, maxSocketWaitNanos;
/// Acquisition time per lease slot, for hold times; slots beyond the table go uncounted.
private shared long[256] acquiredAt;
/// Per pool slot, when a release last left a lease for queued waiters; zero when none is pending.
private shared long[64] idleSince;

/// Whether the counters run.
bool diagnosticsOn() nothrow @nogc
{
    return atomicLoad!(MemoryOrder.raw)(enabled);
}

/// Turn the counters on or off for this process.
void enableDiagnostics(bool on) nothrow @nogc
{
    atomicStore(decided, true);
    atomicStore(enabled, on);
}

/// Read `FLINT_DIAG_COUNTERS` once, unless `enableDiagnostics` already decided. Turned on this way, the counters
/// are also written when the process exits, since an application may never close its pools.
void decideDiagnostics() nothrow @nogc
{
    if (!cas(&decided, false, true))
        return;
    const on = environmentAsksForDiagnostics();
    atomicStore(enabled, on);
    if (on)
        reportAtExit();
}

/// The monotonic time for a diagnostic event, or zero when the counters are off.
long diagnosticNow() nothrow @nogc
{
    return diagnosticsOn() ? Deadline.afterMillis(0).monotonicNanoseconds : 0;
}

private ulong since(long start) nothrow @nogc
{
    const now = Deadline.afterMillis(0).monotonicNanoseconds;
    return now > start ? cast(ulong)(now - start) : 0;
}

private void raiseTo(ref shared ulong maximum, ulong value) nothrow @nogc
{
    for (;;)
    {
        const seen = atomicLoad(maximum);
        if (value <= seen || cas(&maximum, seen, value))
            return;
    }
}

/// A lease was acquired on `pool` into `lease`, `started` from `diagnosticNow` when acquire began.
void noteAcquire(ulong pool, ulong lease, long started, bool queued) nothrow @nogc
{
    if (!diagnosticsOn() || started == 0)
        return;
    const waited = since(started);
    atomicOp!"+="(acquires, 1);
    atomicOp!"+="(leaseWaitNanos, waited);
    raiseTo(maxLeaseWaitNanos, waited);
    atomicStore(acquiredAt[lease % acquiredAt.length], Deadline.afterMillis(0).monotonicNanoseconds);
    if (!queued)
        return;
    atomicOp!"+="(queuedAcquires, 1);
    const idle = atomicLoad(idleSince[pool % idleSince.length]);
    if (idle != 0 && cas(&idleSince[pool % idleSince.length], idle, 0L))
    {
        atomicOp!"+="(handoffs, 1);
        atomicOp!"+="(handoffNanos, since(idle));
    }
}

/// A lease of `pool` was released while `waiters` were queued.
void noteRelease(ulong pool, ulong lease, uint waiters) nothrow @nogc
{
    if (!diagnosticsOn())
        return;
    atomicOp!"+="(releases, 1);
    const at = atomicLoad(acquiredAt[lease % acquiredAt.length]);
    if (at != 0)
    {
        const held = since(at);
        atomicOp!"+="(leaseHoldNanos, held);
        raiseTo(maxLeaseHoldNanos, held);
    }
    if (waiters == 0)
        return;
    atomicOp!"+="(releasesWithWaiters, 1);
    cas(&idleSince[pool % idleSince.length], 0L, Deadline.afterMillis(0).monotonicNanoseconds);
}

/// A waiter found `waiters` queued on its pool.
void noteQueue(uint waiters) nothrow @nogc
{
    if (diagnosticsOn())
        raiseTo(maxQueuedWaiters, waiters);
}

/// A statement produced a row.
void noteRow() nothrow @nogc
{
    if (diagnosticsOn())
        atomicOp!"+="(rows, 1);
}

/// A statement `started` (from `diagnosticNow`) completed.
void noteStatement(long started) nothrow @nogc
{
    if (!diagnosticsOn() || started == 0)
        return;
    const drove = since(started);
    atomicOp!"+="(statements, 1);
    atomicOp!"+="(driveNanos, drove);
    raiseTo(maxDriveNanos, drove);
}

/// A fiber's wait for socket readiness `started` (from `diagnosticNow`) ended.
void noteSocketWait(long started) nothrow @nogc
{
    if (!diagnosticsOn() || started == 0)
        return;
    const waited = since(started);
    atomicOp!"+="(socketWaits, 1);
    atomicOp!"+="(socketWaitNanos, waited);
    raiseTo(maxSocketWaitNanos, waited);
}

/// The counters so far.
SqlDiagnostics diagnosticsSnapshot() nothrow @nogc
{
    SqlDiagnostics snapshot;
    snapshot.acquires = atomicLoad(acquires);
    snapshot.queuedAcquires = atomicLoad(queuedAcquires);
    snapshot.leaseWaitNanos = atomicLoad(leaseWaitNanos);
    snapshot.maxLeaseWaitNanos = atomicLoad(maxLeaseWaitNanos);
    snapshot.releases = atomicLoad(releases);
    snapshot.leaseHoldNanos = atomicLoad(leaseHoldNanos);
    snapshot.maxLeaseHoldNanos = atomicLoad(maxLeaseHoldNanos);
    snapshot.releasesWithWaiters = atomicLoad(releasesWithWaiters);
    snapshot.handoffs = atomicLoad(handoffs);
    snapshot.handoffNanos = atomicLoad(handoffNanos);
    snapshot.maxQueuedWaiters = atomicLoad(maxQueuedWaiters);
    snapshot.statements = atomicLoad(statements);
    snapshot.driveNanos = atomicLoad(driveNanos);
    snapshot.maxDriveNanos = atomicLoad(maxDriveNanos);
    snapshot.rows = atomicLoad(rows);
    snapshot.socketWaits = atomicLoad(socketWaits);
    snapshot.socketWaitNanos = atomicLoad(socketWaitNanos);
    snapshot.maxSocketWaitNanos = atomicLoad(maxSocketWaitNanos);
    return snapshot;
}

/// Zero the counters.
void resetDiagnostics() nothrow @nogc
{
    atomicStore(acquires, 0UL);
    atomicStore(queuedAcquires, 0UL);
    atomicStore(leaseWaitNanos, 0UL);
    atomicStore(maxLeaseWaitNanos, 0UL);
    atomicStore(releases, 0UL);
    atomicStore(leaseHoldNanos, 0UL);
    atomicStore(maxLeaseHoldNanos, 0UL);
    atomicStore(releasesWithWaiters, 0UL);
    atomicStore(handoffs, 0UL);
    atomicStore(handoffNanos, 0UL);
    atomicStore(maxQueuedWaiters, 0UL);
    atomicStore(statements, 0UL);
    atomicStore(driveNanos, 0UL);
    atomicStore(maxDriveNanos, 0UL);
    atomicStore(rows, 0UL);
    atomicStore(socketWaits, 0UL);
    atomicStore(socketWaitNanos, 0UL);
    atomicStore(maxSocketWaitNanos, 0UL);
    foreach (ref slot; acquiredAt)
        atomicStore(slot, 0L);
    foreach (ref slot; idleSince)
        atomicStore(slot, 0L);
}

/// Write the counters to the `FLINT_DIAG_COUNTERS` file when they run there.
void reportDiagnostics() nothrow @nogc
{
    if (!diagnosticsOn())
        return;
    char[2048] text;
    const used = formatCounters(diagnosticsSnapshot(), text);
    writeCounters(text[0 .. used]);
}

/// Format `counters` as `flint.diag-counters/1` JSON into `text`; returns the length used.
private size_t formatCounters(const SqlDiagnostics counters, ref char[2048] text) nothrow @nogc
{
    size_t used;
    void append(scope const(char)[] piece) nothrow @nogc
    {
        const room = text.length - used;
        const taken = piece.length < room ? piece.length : room;
        text[used .. used + taken] = piece[0 .. taken];
        used += taken;
    }

    void number(ulong value) nothrow @nogc
    {
        char[20] digits;
        append(decimal(value, digits));
    }

    bool first = true;
    void timer(scope const(char)[] name, ulong count, ulong sum, ulong maximum) nothrow @nogc
    {
        append(first ? "\"" : ",\"");
        first = false;
        append(name);
        append("\":{\"count\":");
        number(count);
        append(",\"sum_ns\":");
        number(sum);
        append(",\"max_ns\":");
        number(maximum);
        append("}");
    }

    void gauge(scope const(char)[] name, ulong value) nothrow @nogc
    {
        append(first ? "\"" : ",\"");
        first = false;
        append(name);
        append("\":");
        number(value);
    }

    append("{\"schema\":\"flint.diag-counters/1\",\"timers\":{");
    timer("sql.lease_wait", counters.acquires, counters.leaseWaitNanos, counters.maxLeaseWaitNanos);
    timer("sql.lease_hold", counters.releases, counters.leaseHoldNanos, counters.maxLeaseHoldNanos);
    timer("sql.drive", counters.statements, counters.driveNanos, counters.maxDriveNanos);
    timer("sql.socket_wait", counters.socketWaits, counters.socketWaitNanos, counters.maxSocketWaitNanos);
    timer("sql.handoff", counters.handoffs, counters.handoffNanos, 0);
    append("},\"gauges\":{");
    first = true;
    gauge("sql.acquires", counters.acquires);
    gauge("sql.queued_acquires", counters.queuedAcquires);
    gauge("sql.releases_with_waiters", counters.releasesWithWaiters);
    gauge("sql.idle_with_waiters_ns", counters.handoffNanos);
    gauge("sql.max_queue_depth", counters.maxQueuedWaiters);
    gauge("sql.statements", counters.statements);
    gauge("sql.rows", counters.rows);
    append("}}\n");
    return used;
}

private const(char)[] decimal(ulong value, return ref char[20] digits) pure nothrow @nogc
{
    size_t start = digits.length;
    do
    {
        digits[--start] = cast(char)('0' + value % 10);
        value /= 10;
    }
    while (value != 0);
    return digits[start .. $];
}

/// Where `FLINT_DIAG_COUNTERS` asks the counters to go: the environment's own NUL-terminated string, or null.
private __gshared const(char)* countersFile;

// SAFETY: getenv returns null or a NUL-terminated string the environment owns for the life of the process; it is
// stored once, before any thread reads it.
private bool environmentAsksForDiagnostics() @trusted nothrow @nogc
{
    import core.stdc.stdlib : getenv;

    const value = getenv("FLINT_DIAG_COUNTERS");
    if (value is null || value[0] == 0)
        return false;
    countersFile = value;
    return true;
}

private extern (C) void reportOnExit() nothrow @nogc
{
    reportDiagnostics();
}

// SAFETY: atexit stores a pointer to a static function that lives as long as the program.
private void reportAtExit() @trusted nothrow @nogc
{
    import core.stdc.stdlib : atexit;

    cast(void) atexit(&reportOnExit);
}

// SAFETY: The paths are NUL-terminated: the environment's string and a bounded local copy with ".tmp" appended.
// fwrite reads exactly text.length bytes from the caller's live slice; rename replaces the file in one step.
private void writeCounters(scope const(char)[] text) @trusted nothrow @nogc
{
    import core.stdc.stdio : fclose, fopen, fwrite, rename;
    import core.stdc.string : strlen;

    if (countersFile is null)
        return;
    const length = strlen(countersFile);
    char[4096] temporary;
    if (length + 5 > temporary.length)
        return;
    temporary[0 .. length] = countersFile[0 .. length];
    temporary[length .. length + 5] = ".tmp\0";
    auto file = fopen(temporary.ptr, "w");
    if (file is null)
        return;
    const written = fwrite(text.ptr, 1, text.length, file);
    if (fclose(file) == 0 && written == text.length)
        cast(void) rename(temporary.ptr, countersFile);
}

@("the counters stay at zero while off and add up while on")
unittest
{
    enableDiagnostics(false);
    resetDiagnostics();
    noteStatement(1);
    noteRow();
    assert(diagnosticsSnapshot().statements == 0 && diagnosticsSnapshot().rows == 0);
    enableDiagnostics(true);
    scope (exit)
        enableDiagnostics(false);
    const started = diagnosticNow();
    assert(started != 0);
    noteAcquire(1, 2, started, true);
    noteRelease(1, 2, 1);
    noteAcquire(1, 3, diagnosticNow(), true);
    noteStatement(diagnosticNow());
    foreach (_; 0 .. 4)
        noteRow();
    noteQueue(7);
    noteQueue(5);
    const snapshot = diagnosticsSnapshot();
    assert(snapshot.acquires == 2 && snapshot.queuedAcquires == 2);
    assert(snapshot.releases == 1 && snapshot.releasesWithWaiters == 1 && snapshot.handoffs == 1);
    assert(snapshot.statements == 1 && snapshot.rows == 4);
    assert(snapshot.maxQueuedWaiters == 7);
    resetDiagnostics();
    assert(diagnosticsSnapshot().acquires == 0);
}

@("the counters format as flint.diag-counters/1 JSON")
unittest
{
    SqlDiagnostics counters;
    counters.acquires = 3;
    counters.leaseWaitNanos = 40;
    counters.maxLeaseWaitNanos = 20;
    counters.maxQueuedWaiters = 9;
    char[2048] text;
    const used = formatCounters(counters, text);
    const json = text[0 .. used];
    bool contains(scope const(char)[] piece)
    {
        foreach (start; 0 .. json.length + 1 - piece.length)
            if (json[start .. start + piece.length] == piece)
                return true;
        return false;
    }

    assert(json[0 .. 41] == `{"schema":"flint.diag-counters/1","timers`);
    assert(contains(`"sql.lease_wait":{"count":3,"sum_ns":40,"max_ns":20}`));
    assert(contains(`"sql.max_queue_depth":9`));
}

@("decimal writes zero and the largest value")
unittest
{
    char[20] digits;
    assert(decimal(0, digits) == "0");
    assert(decimal(ulong.max, digits) == "18446744073709551615");
}
