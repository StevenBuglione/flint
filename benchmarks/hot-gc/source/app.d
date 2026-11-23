module app;

import core.lifetime : move;
import core.memory : GC;
import flint.arena : Status;
import flint.conc : Context, Deadline;
import flint.engine.web : Method, Server, registerController;
import flint_bench_gc.barrier : Barrier, Counter, Stage, ownerCount;
import flint_bench_gc.client : Client, choosePort;
import flint_bench_rest.profile : Application, minimalRestOptions;
import flint_bench_gc.sys.loopback : diagnostic;
import std.json : JSONValue;
import std.stdio : writeln;

@safe:

private enum warmupRequests = 10_000;
private enum measuredRequests = 100_000;
private enum probeAttempts = 128;

private alias Clients = Client[ownerCount];
private alias Counters = Counter[ownerCount];

private struct Observation
{
    Counters before;
    Counters after;
    ulong collectionsBefore;
    ulong collectionsAfter;
    uint requests;
}

private bool connectOwners(ushort port, ref Clients peers)
{
    bool[ownerCount] ready;
    size_t matched;
    foreach (attempt; 0 .. probeAttempts)
    {
        Client probe;
        scope (exit)
            probe.close();
        probe.open(port);
        const worker = probe.barrier();
        if (worker >= ownerCount)
            return false;
        if (ready[worker])
            continue;
        move(probe, peers[worker]);
        ready[worker] = true;
        if (++matched == ownerCount)
            return true;
    }
    return false;
}

private bool requests(ref Clients peers, uint count) nothrow @nogc
{
    const deadline = Deadline.afterMillis(60_000);
    foreach (index; 0 .. count)
    {
        if (Deadline.afterMillis(0).monotonicNanoseconds >= deadline.monotonicNanoseconds)
            return false;
        if (!peers[index % ownerCount].json())
            return false;
    }
    return true;
}

private bool sample(Barrier barrier, Stage phase, ref Clients peers, ref Counters counters) nothrow @nogc
{
    barrier.select(phase);
    foreach (worker, ref peer; peers)
    {
        if (peer.barrier() != worker)
            return false;
        counters[worker] = barrier.sample(phase, worker);
        if (counters[worker].threadId <= 0)
            return false;
    }
    return counters[0].threadId != counters[1].threadId;
}

private bool observe(Barrier barrier, ref Clients peers, uint count, ref Observation result) nothrow @nogc
{
    if (!sample(barrier, Stage.before, peers, result.before))
        return false;
    result.collectionsBefore = GC.profileStats().numCollections;
    barrier.select(Stage.measured);
    if (!requests(peers, count))
        return false;
    // Each owner has a single sequential channel. The after control runs behind its final response retirement.
    if (!sample(barrier, Stage.after, peers, result.after))
        return false;
    result.collectionsAfter = GC.profileStats().numCollections;
    result.requests = count;
    return true;
}

private bool report(scope const ref Observation observed, bool smoke)
{
    ulong[ownerCount] before;
    ulong[ownerCount] after;
    ulong[ownerCount] deltas;
    uint[ownerCount] workers;
    if (observed.collectionsAfter < observed.collectionsBefore)
        return false;
    foreach (worker; 0 .. ownerCount)
    {
        const opening = observed.before[worker];
        const closing = observed.after[worker];
        if (opening.threadId != closing.threadId || closing.allocatedBytes < opening.allocatedBytes)
            return false;
        workers[worker] = cast(uint) opening.threadId;
        before[worker] = opening.allocatedBytes;
        after[worker] = closing.allocatedBytes;
        deltas[worker] = after[worker] - before[worker];
    }
    JSONValue counters = [
        "phase": JSONValue(smoke ? "smoke" : "steady_state"),
        "requests_completed": JSONValue(observed.requests), "worker_count": JSONValue(ownerCount),
        "worker_ids": JSONValue(workers[]), "before_barrier_workers": JSONValue(ownerCount),
        "after_barrier_workers": JSONValue(ownerCount),
        "allocated_before_per_worker": JSONValue(before[]),
        "allocated_after_per_worker": JSONValue(after[]),
        "allocated_bytes_per_worker": JSONValue(deltas[]),
        "collections_before": JSONValue(observed.collectionsBefore),
        "collections_after": JSONValue(observed.collectionsAfter),
        "collection_delta": JSONValue(observed.collectionsAfter - observed.collectionsBefore),
    ];
    writeln(JSONValue(["gc": counters]).toString());
    return true;
}

private int failed(string detail)
{
    diagnostic(detail);
    return 1;
}

private int measure(ref Server server, Barrier barrier, ushort port, bool smoke, out Observation observed)
{
    Application application;
    if (registerController(server, application.controller).code != Status.ok)
        return failed("cannot register the canonical REST routes");
    if (server.route(Method.get, "/_flint_hot_gc_barrier", &barrier.control).code != Status.ok)
        return failed("cannot register the worker barrier");
    Context context;
    if (server.poll(context).code != Status.ok)
        return failed("cannot start serving the hot-GC fixture");

    Clients peers;
    scope (exit)
        foreach (ref peer; peers)
            peer.close();
    if (!connectOwners(port, peers))
        return failed("cannot establish one connection per reactor owner");
    if (!requests(peers, smoke ? 20 : warmupRequests))
        return failed("hot-GC warmup request failed correctness or deadline");
    if (!observe(barrier, peers, smoke ? 100 : measuredRequests, observed))
        return failed("hot-GC request correctness or full-worker barrier failed");
    return 0;
}

private int run(bool smoke)
{
    auto options = minimalRestOptions();
    options.port = choosePort();
    auto barrier = new Barrier;
    Server server;
    const started = server.start(options);
    if (started.code != Status.ok)
        return failed(started.message);
    scope (failure)
        server.shutdown(Deadline.afterMillis(5_000).monotonicNanoseconds);

    Observation observed;
    const status = measure(server, barrier, options.port, smoke, observed);
    const stopped = server.shutdown(Deadline.afterMillis(5_000).monotonicNanoseconds);
    if (stopped.code != Status.ok)
        return failed(stopped.message);
    if (status != 0)
        return status;
    if (!report(observed, smoke))
        return failed("hot-GC owner identity or monotonic counter changed");
    return 0;
}

int main(string[] args)
{
    const smoke = args.length == 2 && args[1] == "--smoke";
    if (args.length != 1 && !smoke)
        return failed("usage: bench-hot-gc [--smoke]");
    try
        return run(smoke);
    catch (Exception error)
        return failed(error.msg);
}
