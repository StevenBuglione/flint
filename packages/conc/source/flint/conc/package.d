module flint.conc;

import flint.arena : Error, Result, Status;
import flint.conc.internal.transfer : TransferValue;
import flint.conc.sys.cancellation : cancelSource, closeSource, closedContextId, contextStatus,
    createSource, monotonicNanoseconds, noDeadline, releaseContext, retainContext, retainFromSource;

@safe:

/// Fill the supplied bytes from the operating system random source.
Error fillSecureRandom(scope ubyte[] output) nothrow @nogc
{
    import flint.conc.sys.random : secureRandom;

    return secureRandom(output);
}

package(flint) Error startBackground(void delegate() @safe nothrow @nogc run)
{
    import flint.conc.sys.background : startDaemon;

    return startDaemon(run);
}

package(flint) Error startManagedBackground(void delegate() @safe nothrow run)
{
    import flint.conc.sys.background : startDaemon;

    return startDaemon(run);
}

/// Absolute time on the process monotonic clock.
struct Deadline
{
    /// Absolute nanoseconds. long.max represents an absent deadline.
    long monotonicNanoseconds = noDeadline;

    /// Compute a finite deadline with saturating arithmetic.
    static Deadline afterMillis(ulong duration) nothrow @nogc
    {
        enum nanosPerMillis = 1_000_000;
        immutable now = .monotonicNanoseconds();
        immutable available = cast(ulong)(noDeadline - 1) - cast(ulong) now;
        if (duration > available / nanosPerMillis)
            return Deadline(noDeadline - 1);
        return Deadline(cast(long)(cast(ulong) now + duration * nanosPerMillis));
    }

    /// Create a deadline without a time limit.
    static Deadline none() pure nothrow @nogc
    {
        return Deadline.init;
    }
}

/// Copyable snapshot that retains cancellation state and its ancestors.
struct Context
{
    private ulong id;
    private Deadline deadlineValue;

    private this(ulong id, Deadline deadline) nothrow @nogc
    {
        this.id = id;
        deadlineValue = deadline;
    }

    /// Retain the same cancellation identity when copying a context.
    this(ref const Context other) nothrow @nogc
    {
        id = other.id;
        deadlineValue = other.deadlineValue;
        retainContext(id);
    }

    ~this() nothrow @nogc
    {
        releaseContext(id);
    }

    /// Whether an explicit cancellation or elapsed deadline precludes further work.
    bool cancelled() const nothrow @nogc
    {
        return check().code != Status.ok;
    }

    /// Return the earliest explicit deadline in this context and its ancestors.
    Deadline deadline() const nothrow @nogc
    {
        return deadlineValue;
    }

    /// Retain this cancellation identity and narrow its deadline without allocating another source.
    Context withDeadline(Deadline deadline) const nothrow @nogc
    {
        if (deadlineValue.monotonicNanoseconds < deadline.monotonicNanoseconds)
            deadline = deadlineValue;
        retainContext(id);
        return Context(id, deadline);
    }

    /// Report the earliest terminal status or success while work may proceed.
    Error check() const nothrow @nogc
    {
        switch (contextStatus(id, deadlineValue.monotonicNanoseconds))
        {
        case Status.cancelled:
            return Error(Status.cancelled, "context cancelled");
        case Status.timedOut:
            return Error(Status.timedOut, "context deadline elapsed");
        default:
            return Error.init;
        }
    }
}

/// Owner of an explicitly cancellable scope in a bounded process-wide slab.
struct CancelSource
{
    private ulong id;
    private Deadline deadlineValue;

    @disable this(this);

    private this(ulong id, Deadline deadline) nothrow @nogc
    {
        this.id = id;
        deadlineValue = deadline;
    }

    ~this() nothrow @nogc
    {
        close();
    }

    /// Allocate a cancellation source that inherits its parent deadline.
    static Result!CancelSource create(Context parent, Deadline deadline) nothrow @nogc
    {
        if (parent.deadlineValue.monotonicNanoseconds < deadline.monotonicNanoseconds)
            deadline = parent.deadlineValue;

        immutable id = createSource(parent.id, deadline.monotonicNanoseconds);
        if (id == 0)
            return Result!CancelSource(CancelSource.init, Error(Status.resourceExhausted, "cancellation slab full"));
        return Result!CancelSource(CancelSource(id, deadline));
    }

    /// Return a context that stays valid independently of the source owner.
    Context context() const nothrow @nogc
    {
        return retainFromSource(id) ? Context(id, deadlineValue) : Context(closedContextId, deadlineValue);
    }

    /// Mark this source and its descendants cancelled if their deadlines permit.
    void cancel() nothrow @nogc
    {
        cancelSource(id);
    }

    /// Retire the source. Existing contexts and children retain their state.
    void close() nothrow @nogc
    {
        closeSource(id);
    }
}

/// Select the allowed number of concurrent consumers.
enum QueueKind
{
    mpsc,
    mpmc
}

/// Bounded, noncopyable FIFO. The owner must join borrowers before destroying it.
struct Channel(T, QueueKind kind = QueueKind.mpsc)
        if (TransferValue!T && (kind == QueueKind.mpsc || kind == QueueKind.mpmc))
{
    import flint.conc.sys.ring : SequenceRing;

    private SequenceRing!(T, kind == QueueKind.mpmc) ring;

    @disable this(this);

    /// Allocate a power-of-two ring with 2 through 1,048,576 entries.
    static Result!Channel create(size_t capacity) nothrow @nogc
    {
        Result!Channel result;
        immutable status = result.value.ring.initialize(capacity);
        if (status != Status.ok)
            result.error = Error(status, "unable to create channel");
        return result;
    }

    /// Enqueue a transfer value, or return an error when the ring is full or closed.
    Status trySend(T value) nothrow @nogc
    {
        return ring.send(value);
    }

    /// Consume the oldest published item, or report an empty or exhausted ring.
    Result!T tryReceive() nothrow @nogc
    {
        return ring.receive();
    }

    /// Stop admissions and retain published items for the consumer to drain.
    void close() nothrow @nogc
    {
        ring.close();
    }
}

/// Bounds for a native pool and its live ticket slab.
struct WorkerOptions
{
    /// Number of druntime-managed workers, from 1 to 256.
    uint threads = 4;
    /// Maximum live tickets, from 1 to 4096.
    uint queueCapacity = 256;
}

/// Identity of a submitted job and its eventual completion.
struct WorkTicket
{
    /// Process-unique submission identity.
    ulong id;
}

/// Copy data between the pool-owned input and output spans.
alias WorkFn = Error function(scope const(ubyte)[] input, scope ubyte[] output, out size_t written) @safe nothrow @nogc;

/// Bounded blocking-work offload with one-shot completion consumption.
struct WorkerPool
{
    private WorkerState* state;

    @disable this(this);

    private this(WorkerState* state)
    {
        this.state = state;
    }

    ~this() scope nothrow
    {
        if (state !is null)
            state.shutdown();
    }

    /// Allocate the slot buffers and launch the configured number of workers.
    static Result!WorkerPool create(WorkerOptions options)
    {
        import flint.conc.sys.workers : maxTicketSlots;

        if (options.threads == 0 || options.threads > 256 || options.queueCapacity == 0
                || options.queueCapacity > maxTicketSlots)
            return Result!WorkerPool(WorkerPool.init, Error(Status.invalidArgument, "invalid worker pool capacity"));

        auto state = new WorkerState;
        state.prepare(options.queueCapacity);
        if (!state.workers.start(options.threads, ()@safe nothrow @nogc { state.run(); }))
        {
            state.shutdown();
            return Result!WorkerPool(WorkerPool.init, Error(Status.unavailable, "unable to start worker threads"));
        }
        return Result!WorkerPool(WorkerPool(state));
    }

    /// Copy up to 4 KiB into one of the pool's slots before returning.
    Result!WorkTicket submit(Context context, scope const(ubyte)[] ownedCopy, WorkFn job) nothrow @nogc
    {
        if (state is null)
            return Result!WorkTicket(WorkTicket.init, Error(Status.cancelled, "worker pool closed"));
        return state.submit(context, ownedCopy, job);
    }

    /// Poll for completion and consume it once. An undersized output may retry.
    Error join(WorkTicket ticket, scope ubyte[] output, out size_t written) nothrow @nogc
    {
        if (state is null)
            return Error(Status.cancelled, "worker pool closed");
        return state.join(ticket, output, written);
    }

    /// Stop admission, join running workers, and retire every outstanding ticket.
    void shutdown() nothrow
    {
        if (state !is null)
            state.shutdown();
    }
}

private enum WorkerPhase
{
    open,
    stopping,
    stopped
}

private enum JobPhase
{
    vacant,
    queued,
    running,
    finished
}

private enum maxWorkBytes = 4_096;

private struct Job
{
    ulong id;
    JobPhase phase;
    Context context;
    WorkFn task;
    Error error;
    size_t inputLength;
    size_t written;
    ubyte[maxWorkBytes] input;
    ubyte[maxWorkBytes] output;
}

private struct WorkerState
{
    import flint.conc.sys.atomics : SpinLock;
    import flint.conc.sys.workers : WorkerThreads, idleWorker, issueTicket, maxTicketSlots;

    private SpinLock lock;
    private WorkerThreads workers;
    private WorkerPhase phase;
    private Job[] jobs;
    private uint[] queued;
    private uint[] vacant;
    private size_t freeCount;
    private size_t queueHead;
    private size_t queuedCount;

    void prepare(uint capacity)
    {
        jobs = new Job[capacity];
        queued = new uint[capacity];
        vacant = new uint[capacity];
        freeCount = capacity;
        foreach (uint slot; 0 .. capacity)
            vacant[slot] = slot;
    }

    Result!WorkTicket submit(ref scope const Context context, scope const(ubyte)[] input, WorkFn task) nothrow @nogc
    {
        alias Reply = Result!WorkTicket;
        if (task is null)
            return Reply(WorkTicket.init, Error(Status.invalidArgument, "null worker callback"));
        if (input.length > maxWorkBytes)
            return Reply(WorkTicket.init, Error(Status.resourceExhausted, "worker input exceeds slot size"));
        immutable error = context.check();
        if (error.code != Status.ok)
            return Reply(WorkTicket.init, error);

        lock.lock();
        scope (exit)
            lock.unlock();

        if (phase != WorkerPhase.open)
            return Reply(WorkTicket.init, Error(Status.cancelled, "worker pool closed"));
        if (freeCount == 0)
            return Reply(WorkTicket.init, Error(Status.resourceExhausted, "worker pool full"));

        immutable slot = vacant[freeCount - 1];
        immutable id = issueTicket(slot);
        if (id == 0)
            return Reply(WorkTicket.init, Error(Status.resourceExhausted, "worker ticket IDs exhausted"));

        --freeCount;
        ref Job job = jobs[slot];
        job.id = id;
        job.context = context;
        job.task = task;
        job.inputLength = input.length;
        job.input[0 .. input.length] = input[];
        job.phase = JobPhase.queued;

        queued[(queueHead + queuedCount) % queued.length] = slot;
        ++queuedCount;
        return Reply(WorkTicket(id));
    }

    Error join(WorkTicket ticket, scope ubyte[] output, out size_t written) nothrow @nogc
    {
        lock.lock();
        scope (exit)
            lock.unlock();

        if (phase != WorkerPhase.open)
            return Error(Status.cancelled, "worker pool closed");

        immutable slot = cast(uint)(ticket.id & (maxTicketSlots - 1));
        if (ticket.id == 0 || slot >= jobs.length || ticket.id != jobs[slot].id)
            return Error(Status.notFound, "unknown worker ticket");
        ref Job job = jobs[slot];
        if (job.phase != JobPhase.finished)
            return Error(Status.unavailable, "worker job is still active");
        if (job.error.code == Status.ok)
        {
            if (output.length < job.written)
                return Error(Status.resourceExhausted, "worker output is too small");
            output[0 .. job.written] = job.output[0 .. job.written];
            written = job.written;
        }
        immutable error = job.error;
        recycle(slot, job);
        return error;
    }

    void shutdown() scope nothrow
    {
        for (;;)
        {
            lock.lock();
            if (phase == WorkerPhase.open)
            {
                phase = WorkerPhase.stopping;
                lock.unlock();
                break;
            }
            immutable stopped = phase == WorkerPhase.stopped;
            lock.unlock();
            if (stopped)
                return;
            idleWorker();
        }

        workers.join();
        lock.lock();
        foreach (slot, ref job; jobs)
        {
            if (job.phase != JobPhase.vacant)
                recycle(cast(uint) slot, job);
        }
        assert(freeCount == jobs.length);
        jobs = null;
        queued = null;
        vacant = null;
        queuedCount = 0;
        phase = WorkerPhase.stopped;
        lock.unlock();
    }

    private void run() nothrow @nogc
    {
        for (;;)
        {
            lock.lock();
            if (phase != WorkerPhase.open)
            {
                lock.unlock();
                return;
            }
            if (queuedCount == 0)
            {
                lock.unlock();
                idleWorker();
                continue;
            }
            immutable slot = queued[queueHead];
            queueHead = (queueHead + 1) % queued.length;
            --queuedCount;
            jobs[slot].phase = JobPhase.running;
            lock.unlock();

            execute(jobs[slot]);
        }
    }

    private void execute(ref Job job) nothrow @nogc
    {
        Error result = job.context.check();
        size_t written;
        if (result.code == Status.ok)
        {
            job.output[] = 0;
            result = job.task(job.input[0 .. job.inputLength], job.output[], written);
            if (result.code == Status.ok && written > job.output.length)
                result = Error(Status.invalidArgument, "worker reported too many output bytes");
        }

        lock.lock();
        scope (exit)
            lock.unlock();

        // Checking cancellation under the publication gate orders completion
        // against cancellation. Retain the slot until both work and join finish.
        immutable cancelled = job.context.check();
        if (cancelled.code != Status.ok)
            result = cancelled;
        job.error = result;
        job.written = result.code == Status.ok ? written : 0;
        job.phase = JobPhase.finished;
    }

    private void recycle(uint slot, ref scope Job job) scope nothrow @nogc
    {
        job.context = Context.init;
        job.task = null;
        job.id = 0;
        job.phase = JobPhase.vacant;
        vacant[freeCount++] = slot;
    }
}
