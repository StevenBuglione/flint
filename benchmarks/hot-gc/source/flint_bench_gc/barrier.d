/// Per-owner counter slots sampled by actual HTTP request workers.
module flint_bench_gc.barrier;

import core.atomic : atomicLoad, atomicStore;
import core.memory : GC;
import flint.arena : Error, Result, Status;
import flint.reactor : Reactor;
import flint.web : Request, RequestContext, Response;
import flint_bench_gc.sys.loopback : linuxThreadId;

@safe:

/// The canonical server creates exactly two workers.
enum ownerCount = 2;

/// Controls which barrier the owner records in its own slot.
enum Stage : ubyte
{
    probe,
    before,
    measured,
    after,
}

/// Raw per-thread values at either side of the measured requests.
struct Counter
{
    /// Numeric identity of the worker that recorded the sample.
    int threadId;
    /// Monotonic D GC allocation counter on that worker.
    ulong allocatedBytes;
}

/// Startup-owned numeric slots. The coordinator publishes the phase and only the matching owner writes a slot.
final class Barrier
{
    private shared Stage stage;
    private shared Counter[ownerCount] opening;
    private shared Counter[ownerCount] closing;

    /// Select a phase before sending the control request to every owner.
    void select(Stage phase) nothrow @nogc
    {
        atomicStore(stage, phase);
    }

    /// Read a sample after the reply verifies the barrier reached this owner.
    Counter sample(Stage phase, size_t worker) nothrow @nogc
    {
        ref stored = phase == Stage.before ? opening[worker] : closing[worker];
        const threadId = atomicLoad(stored.threadId);
        return Counter(threadId, atomicLoad(stored.allocatedBytes));
    }

    /// Handle private loopback control traffic outside the measured request sequence.
    Result!Response control(ref scope Request request, ref scope RequestContext context) nothrow @nogc
    {
        auto reactor = Reactor.current();
        const worker = reactor.currentCore();
        auto phase = atomicLoad(stage);
        if (worker >= ownerCount || phase == Stage.measured)
            return failed();
        if (phase != Stage.probe && !save(phase, worker))
            return failed();
        const label = worker == 0 ? "0" : "1";
        const payload = context.arena.copyIn(cast(const(ubyte)[]) label);
        return Result!Response(Response(200, "text/plain", payload.value), payload.error);
    }

    private bool save(Stage phase, uint worker) nothrow @nogc
    {
        ref slot = phase == Stage.before ? opening[worker] : closing[worker];
        if (atomicLoad(slot.threadId) != 0)
            return false;
        const identity = linuxThreadId();
        if (identity <= 0)
            return false;
        atomicStore(slot.allocatedBytes, cast(ulong) GC.stats().allocatedInCurrentThread);
        atomicStore(slot.threadId, identity);
        return true;
    }
}

private Result!Response failed() nothrow @nogc
{
    return Result!Response(Response.init, Error(Status.conflict, "invalid hot-GC barrier phase or owner"));
}
