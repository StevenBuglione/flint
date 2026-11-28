// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
/// Java SE 21 ScheduledExecutorService and a one-shot scheduling engine, implemented from the public contract.
module flint.java.util.concurrent.scheduledexecutorservice;

import core.atomic : atomicLoad, atomicStore;
import core.sync.mutex : Mutex;
import flint.arena : Status;
import flint.conc : Background, Deadline, startManagedBackground;
import flint.conc.park : park, wakeAll;
import flint.java.lang : IllegalArgumentException, NullPointerException, RuntimeException;
import flint.java.lang.runnable : Runnable;
import flint.java.util : ArrayList, List;
import flint.java.util.concurrent : TimeUnit, convert, toNanos;
import flint.java.util.concurrent.callable : Callable;
import flint.java.util.concurrent.delayed : Delayed;
import flint.java.util.concurrent.executorservice : ExecutorService;
import flint.java.util.concurrent.internal.periodictask : PeriodicControl, PeriodicHost, PeriodicTask;
import flint.java.util.concurrent.future : Future;
import flint.java.util.concurrent.futuretask : FutureTask;
import flint.java.util.concurrent.rejectedexecutionexception : RejectedExecutionException;
import flint.java.util.concurrent.scheduledfuture : RunnableScheduledFuture, ScheduledFuture;

@safe:

// A leaf probe may import only its own leaf, so it names the inherited `TimeUnit` parameter through this alias
// instead of importing the TimeUnit leaf (docs/spring/phase2/jdk-port.md, "A fixture may declare its own module in
// the JDK namespace to exercise package access").
package(flint.java.util.concurrent) alias ScheduledTimeUnit = TimeUnit;

/// Java's `ScheduledExecutorService` (R1, R3).
///
/// The one-shot `schedule` forms complete with their task's result. The repeating forms keep their future open for
/// the service's lifetime: it completes only when the task is cancelled or throws, and `shutdown` cancels a periodic
/// task as Java's default `continueExistingPeriodicTasksAfterShutdown` does.
interface ScheduledExecutorService : ExecutorService
{
    /// Run `callable` after `delay` of `unit` and return its future (R3, R9).
    ScheduledFuture!T schedule(T)(Callable!T callable, long delay, TimeUnit unit)
    {
        if (callable is null)
            throw new NullPointerException;
        const deadline = deadlineAfter(delay, unit);
        auto task = new ScheduledTask!T(new FutureTask!T(callable), deadline);
        enqueueScheduled(task, deadline, &task.cancelNow, &task.isCancelledNow);
        return task;
    }

    /// Run `command` after `delay` of `unit`; its future completes with `result` (R3, R9, R23).
    ///
    /// Java's `Future<?>` erases to `Future!Object`, so the default type parameter keeps this form a template.
    ScheduledFuture!T schedule(T = Object)(Runnable command, long delay, TimeUnit unit)
            if (is(T == Object))
    {
        if (command is null)
            throw new NullPointerException;
        const deadline = deadlineAfter(delay, unit);
        auto task = new ScheduledTask!T(new FutureTask!T(command, T.init), deadline);
        enqueueScheduled(task, deadline, &task.cancelNow, &task.isCancelledNow);
        return task;
    }

    /// Admit an already-built scheduled future (D-only hook; applications call `schedule`). The delegates carry the
    /// task's cancellation state without exposing its generic type to the queue.
    void enqueueScheduled(Runnable command, long deadlineNanos, bool delegate() @safe nothrow cancel,
            bool delegate() @safe nothrow cancelled);

    /// Run `command` repeatedly at a fixed rate: runs start at `initialDelay + n * period` (R1, R3, R20).
    ///
    /// A run that falls behind starts as soon as the worker is free, as Java's fixed-rate trigger does. Java's
    /// `Future<?>` erases to `Future!Object`, so the default type parameter keeps this form a template.
    ScheduledFuture!T scheduleAtFixedRate(T = Object)(Runnable command, long initialDelay, long period, TimeUnit unit)
            if (is(T == Object))
    {
        if (command is null)
            throw new NullPointerException;
        if (period <= 0)
            throw new IllegalArgumentException("period must be positive");
        const initial = deadlineAfter(initialDelay, unit);
        const periodNanos = toNanos(unit, period);
        auto task = new PeriodicTask(command);
        task.setDue(initial);
        enqueuePeriodic(task, initial, periodNanos, true, &task.cancelNow, &task.isDoneNow);
        return task;
    }

    /// Run `command` repeatedly with `delay` between the end of one run and the start of the next (R1, R3, R20).
    ScheduledFuture!T scheduleWithFixedDelay(T = Object)(Runnable command, long initialDelay, long delay, TimeUnit unit)
            if (is(T == Object))
    {
        if (command is null)
            throw new NullPointerException;
        if (delay <= 0)
            throw new IllegalArgumentException("delay must be positive");
        const initial = deadlineAfter(initialDelay, unit);
        const periodNanos = toNanos(unit, delay);
        auto task = new PeriodicTask(command);
        task.setDue(initial);
        enqueuePeriodic(task, initial, periodNanos, false, &task.cancelNow, &task.isDoneNow);
        return task;
    }

    /// Admit a periodic future (D-only hook; applications call the `scheduleAtFixedRate`/`scheduleWithFixedDelay`
    /// forms). The run publishes its next deadline for `getDelay` and `compareTo`.
    void enqueuePeriodic(PeriodicControl task, long initialNanos, long periodNanos, bool fixedRate,
            bool delegate() @safe nothrow cancel, bool delegate() @safe nothrow stopped);
}

/// A future for one run, ordered by its absolute deadline (R1, R3).
private final class ScheduledTask(V) : RunnableScheduledFuture!V
{
    mixin Future!V.Defaults;

    private FutureTask!V task;
    private long deadline;

    this(FutureTask!V task, long deadline) pure nothrow @nogc
    {
        this.task = task;
        this.deadline = deadline;
    }

    /// Whether the task was cancelled before it ran.
    bool isCancelledNow() nothrow
    {
        try
            return task.isCancelled();
        catch (Exception)
            return false;
    }

    /// Cancel the task without interrupting its runner.
    bool cancelNow() nothrow
    {
        try
            return task.cancel(false);
        catch (Exception)
            return false;
    }

    override void run()
    {
        task.run();
    }

    override bool cancel(bool mayInterruptIfRunning)
    {
        return task.cancel(mayInterruptIfRunning);
    }

    override bool isCancelled()
    {
        return task.isCancelled();
    }

    override bool isDone()
    {
        return task.isDone();
    }

    override V get()
    {
        return task.get();
    }

    override V get(long timeout, TimeUnit unit)
    {
        return task.get(timeout, unit);
    }

    /// Java's delay in `unit`: the deadline minus the current monotonic time, truncated toward zero (R20).
    override long getDelay(TimeUnit unit)
    {
        return convert(unit, deadline - monotonicNow(), TimeUnit.NANOSECONDS);
    }

    /// Order by remaining delay, as Java's `RunnableScheduledFuture` does (R1, R3).
    override int compareTo(Delayed other)
    {
        if (other is this)
            return 0;
        if (other is null)
            throw new NullPointerException;
        const mine = getDelay(TimeUnit.NANOSECONDS);
        const theirs = other.getDelay(TimeUnit.NANOSECONDS);
        return mine < theirs ? -1 : mine > theirs ? 1 : 0;
    }

    /// A one-shot schedule is never periodic.
    override bool isPeriodic() pure nothrow @nogc
    {
        return false;
    }
}

/// A one-shot scheduled service driven by its own managed background thread.
///
/// The default deadline queue holds the pending commands sorted by deadline and start order, guarded by the object
/// monitor. The worker parks on a version word outside the monitor, so a reactor fiber that schedules a task yields
/// rather than spinning [R-10]. `execute` admits a task with a zero delay, and the future-returning `submit` forms
/// inherited from `ExecutorService` therefore run at once.
final class OffloadScheduledExecutorService : ScheduledExecutorService, PeriodicHost
{
    private Mutex gate;
    private Runnable[] commands;
    private long[] deadlines;
    private ulong[] orders;
    private long[] periods;
    private bool delegate() @safe nothrow[] cancelHooks;
    private bool delegate() @safe nothrow[] cancellationChecks;
    private Background worker;
    private shared uint wakeWord;
    private shared bool stopping;
    private shared bool finished;
    private ulong nextOrder;

    /// Start the scheduling worker. The owner calls `shutdown` or `shutdownNow` when it is done.
    this()
    {
        gate = new Mutex;
        const started = startManagedBackground(&workerMain, worker);
        if (started.code != Status.ok)
            throw new RuntimeException("could not start the scheduled executor");
    }

    override void execute(Runnable command)
    {
        if (command is null)
            throw new NullPointerException;
        enqueue(command, monotonicNow(), null, null);
    }

    override void enqueueScheduled(Runnable command, long deadlineNanos,
            bool delegate() @safe nothrow cancel, bool delegate() @safe nothrow cancelled)
    {
        enqueue(command, deadlineNanos, cancel, cancelled);
    }

    override void enqueuePeriodic(PeriodicControl task, long initialNanos, long periodNanos,
            bool fixedRate, bool delegate() @safe nothrow cancel, bool delegate() @safe nothrow stopped)
    {
        task.attach(this, periodNanos, fixedRate);
        enqueue(task, initialNanos, cancel, stopped, periodNanos);
    }

    override void reschedule(PeriodicControl task)
    {
        const next = task.fixedRate ? saturatingAdd(task.dueNanos,
                task.periodNanos) : saturatingAdd(monotonicNow(), task.periodNanos);
        task.setDue(next);
        if (!tryEnqueue(task, next, &task.cancelNow, &task.isDoneNow, task.periodNanos))
            task.cancelNow();
    }

    override void shutdown()
    {
        gate.lock_nothrow();
        scope (exit)
            gate.unlock_nothrow();
        if (atomicLoad(stopping))
            return;
        atomicStore(stopping, true);
        cancelPeriodic();
        bumpVersion();
        wakeAll(wakeWord);
    }

    override List!Runnable shutdownNow()
    {
        gate.lock_nothrow();
        scope (exit)
            gate.unlock_nothrow();
        atomicStore(stopping, true);
        auto released = new ArrayList!Runnable();
        foreach (index; 0 .. commands.length)
        {
            if (cancelHooks[index]!is null)
                cancelHooks[index]();
            released.add(commands[index]);
        }
        clear();
        bumpVersion();
        wakeAll(wakeWord);
        return released;
    }

    override bool isShutdown()
    {
        return atomicLoad(stopping);
    }

    override bool isTerminated()
    {
        return atomicLoad(finished);
    }

    private void enqueue(Runnable command, long deadline, bool delegate() @safe nothrow cancel,
            bool delegate() @safe nothrow cancelled, long periodNanos = 0)
    {
        gate.lock_nothrow();
        scope (exit)
            gate.unlock_nothrow();
        if (atomicLoad(stopping))
            throw new RejectedExecutionException("executor rejected the task");
        insert(command, deadline, cancel, cancelled, periodNanos);
    }

    // Insert at a deadline, refusing once stopping. A periodic run calls this after a successful execution; a false
    // result means the task must be cancelled instead of admitted again.
    private bool tryEnqueue(Runnable command, long deadline, bool delegate() @safe nothrow cancel,
            bool delegate() @safe nothrow stopped, long periodNanos)
    {
        gate.lock_nothrow();
        scope (exit)
            gate.unlock_nothrow();
        if (atomicLoad(stopping))
            return false;
        insert(command, deadline, cancel, stopped, periodNanos);
        return true;
    }

    private void insert(Runnable command, long deadline, bool delegate() @safe nothrow cancel,
            bool delegate() @safe nothrow stopped, long periodNanos)
    {
        const order = nextOrder++;
        size_t index = commands.length;
        while (index > 0 && (deadlines[index - 1] > deadline || (deadlines[index - 1] == deadline
                && orders[index - 1] > order)))
            --index;
        commands ~= command;
        deadlines ~= deadline;
        orders ~= order;
        periods ~= periodNanos;
        cancelHooks ~= cancel;
        cancellationChecks ~= stopped;
        size_t position = commands.length;
        while (position > index + 1)
        {
            --position;
            move(position, position - 1);
        }
        commands[index] = command;
        deadlines[index] = deadline;
        orders[index] = order;
        periods[index] = periodNanos;
        cancelHooks[index] = cancel;
        cancellationChecks[index] = stopped;
        bumpVersion();
        wakeAll(wakeWord);
    }

    private void move(size_t to, size_t from) pure nothrow @nogc
    {
        commands[to] = commands[from];
        deadlines[to] = deadlines[from];
        orders[to] = orders[from];
        periods[to] = periods[from];
        cancelHooks[to] = cancelHooks[from];
        cancellationChecks[to] = cancellationChecks[from];
    }

    private void removeHead() nothrow @nogc
    {
        commands[0] = null;
        cancelHooks[0] = null;
        cancellationChecks[0] = null;
        commands = commands[1 .. $];
        deadlines = deadlines[1 .. $];
        orders = orders[1 .. $];
        periods = periods[1 .. $];
        cancelHooks = cancelHooks[1 .. $];
        cancellationChecks = cancellationChecks[1 .. $];
        if (commands.length == 0)
            clear();
    }

    private void clear() nothrow @nogc
    {
        commands = null;
        deadlines = null;
        orders = null;
        periods = null;
        cancelHooks = null;
        cancellationChecks = null;
    }

    private void shrink(size_t kept) nothrow
    {
        commands.length = kept;
        deadlines.length = kept;
        orders.length = kept;
        periods.length = kept;
        cancelHooks.length = kept;
        cancellationChecks.length = kept;
        if (kept == 0)
            clear();
    }

    // Java's default `continueExistingPeriodicTasksAfterShutdown` is false: shutdown cancels periodic tasks while
    // leaving the one-shot deadlines to drain. Caller holds the gate.
    private void cancelPeriodic() nothrow
    {
        if (commands.length == 0)
            return;
        size_t kept;
        foreach (index; 0 .. commands.length)
        {
            if (periods[index] != 0)
            {
                if (cancelHooks[index]!is null)
                    cancelHooks[index]();
                continue;
            }
            if (kept != index)
                move(kept, index);
            ++kept;
        }
        if (kept != commands.length)
            shrink(kept);
    }

    private void bumpVersion() nothrow @nogc
    {
        atomicStore(wakeWord, atomicLoad(wakeWord) + 1);
    }

    // Drop cancelled tasks so a stopped service never waits for a deadline that no longer runs anything. The worker
    // owns the compaction; the queue is small, so a full pass is cheaper than an index and a tombstone.
    private void dropCancelled() nothrow
    {
        if (commands.length == 0)
            return;
        size_t kept;
        foreach (index; 0 .. commands.length)
        {
            if (cancellationChecks[index]!is null && cancellationChecks[index]())
                continue;
            if (kept != index)
                move(kept, index);
            ++kept;
        }
        if (kept != commands.length)
            shrink(kept);
    }

    private void workerMain() nothrow
    {
        for (;;)
        {
            Runnable command;
            long sleepNanos = -1;
            bool done;
            uint seen;
            gate.lock_nothrow();
            {
                scope (exit)
                    gate.unlock_nothrow();
                seen = atomicLoad(wakeWord);
                dropCancelled();
                const now = monotonicNow();
                if (commands.length != 0)
                {
                    if (deadlines[0] <= now)
                    {
                        command = commands[0];
                        removeHead();
                    }
                    else
                        sleepNanos = deadlines[0] - now;
                }
                if (command is null && atomicLoad(stopping) && commands.length == 0)
                {
                    atomicStore(finished, true);
                    done = true;
                }
            }
            if (command !is null)
            {
                runTask(command);
                continue;
            }
            if (done)
            {
                wakeAll(wakeWord);
                return;
            }
            park(wakeWord, seen, sleepNanos < 0 ? long.max : sleepNanos);
        }
    }

    private static void runTask(Runnable command) nothrow
    {
        try
            command.run();
        catch (Exception)
        {
            // A plain `execute` command does not own a future, so nobody else can report its failure. Keep the worker
            // alive; the future-backed scheduled tasks publish their own result or failure.
        }
    }
}

private long saturatingAdd(long value, long delta) pure nothrow @nogc
{
    const sum = value + delta;
    if (delta > 0 && sum < value)
        return long.max;
    if (delta < 0 && sum > value)
        return long.min;
    return sum;
}

private long deadlineAfter(long delay, TimeUnit unit)
{
    const nanos = toNanos(unit, delay);
    const now = monotonicNow();
    const sum = now + nanos;
    if (nanos > 0 && sum < now)
        return long.max - 1;
    if (nanos < 0 && sum > now)
        return long.min;
    return sum;
}

private long monotonicNow() nothrow @nogc
{
    return Deadline.afterMillis(0).monotonicNanoseconds;
}

unittest
{
    // The Java contract check lives in tests/scheduled_executor_service_test.d; this keeps the module's own unit
    // build honest about the helpers.
    assert(deadlineAfter(0, TimeUnit.NANOSECONDS) >= monotonicNow() - 1_000_000);
}
