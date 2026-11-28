module flint.java.util.concurrent.scheduledexecutorservice_provider;

import core.atomic : atomicLoad, atomicStore, cas;
import core.sync.mutex : Mutex;
import flint.arena : Status;
import flint.conc : Background, Deadline, startManagedBackground;
import flint.conc.park : park, wakeAll;
import flint.java.lang : NullPointerException;
import flint.java.lang.runnable : Runnable;
import flint.java.util : ArrayList, List;
import flint.java.util.concurrent : TimeUnit, convert, toNanos;
import flint.java.util.concurrent.cancellationexception : CancellationException;
import flint.java.util.concurrent.delayed : Delayed;
import flint.java.util.concurrent.executionexception : ExecutionException;
import flint.java.util.concurrent.executorservice : ExecutorService;
import flint.java.util.concurrent.future : Future;
import flint.java.util.concurrent.futuretask : FutureTask;
import flint.java.util.concurrent.scheduledfuture : RunnableScheduledFuture;
import flint.java.util.concurrent.timeoutexception : TimeoutException;

@safe:

// Provider-equivalent control: the same deadline queue and managed worker, built directly on flint.conc, FutureTask
// and the existing ExecutorService interface, without the new leaf's schedule API or ScheduledTask.
private final class Pending
{
    Runnable command;
    long deadline;
    ulong order;

    this(Runnable command, long deadline, ulong order) pure nothrow @nogc
    {
        this.command = command;
        this.deadline = deadline;
        this.order = order;
    }
}

private final class Scheduler : ExecutorService
{
    private Mutex gate;
    private Pending[] pending;
    private Background worker;
    private shared uint wakeWord;
    private shared bool stopping;
    private shared bool finished;
    private ulong nextOrder;

    this()
    {
        gate = new Mutex;
        if (startManagedBackground(&workerMain, worker).code != Status.ok)
            assert(0);
    }

    override void execute(Runnable command)
    {
        if (command is null)
            return;
        enqueue(command, monotonicNow());
    }

    override void shutdown()
    {
        gate.lock_nothrow();
        scope (exit)
            gate.unlock_nothrow();
        if (atomicLoad(stopping))
            return;
        atomicStore(stopping, true);
        bumpVersion();
        wakeAll(wakeWord);
    }

    override List!Runnable shutdownNow()
    {
        gate.lock_nothrow();
        scope (exit)
            gate.unlock_nothrow();
        atomicStore(stopping, true);
        auto commands = new ArrayList!Runnable();
        foreach (ref entry; pending)
            commands.add(entry.command);
        pending = null;
        bumpVersion();
        wakeAll(wakeWord);
        return commands;
    }

    override bool isShutdown()
    {
        return atomicLoad(stopping);
    }

    override bool isTerminated()
    {
        return atomicLoad(finished);
    }

    void schedule(Runnable command, long delayNanos)
    {
        enqueue(command, saturatingAdd(monotonicNow(), delayNanos));
    }

    RunnableScheduledFuture!Object schedulePeriodic(Runnable body, long initialDelayNanos,
            long periodNanos, bool fixedRate)
    {
        auto repeat = new Periodic(body, periodNanos, fixedRate);
        const initial = saturatingAdd(monotonicNow(), initialDelayNanos);
        repeat.setDue(initial);
        repeat.reschedule = () { enqueue(repeat, repeat.dueNanos); };
        enqueue(repeat, initial);
        return repeat;
    }

    private void enqueue(Runnable command, long deadline)
    {
        gate.lock_nothrow();
        scope (exit)
            gate.unlock_nothrow();
        if (atomicLoad(stopping))
            return;
        auto entry = new Pending(command, deadline, nextOrder++);
        size_t index = pending.length;
        while (index > 0 && (pending[index - 1].deadline > entry.deadline
                || (pending[index - 1].deadline == entry.deadline && pending[index - 1].order > entry.order)))
            --index;
        pending ~= entry;
        size_t position = pending.length;
        while (position > index + 1)
        {
            --position;
            pending[position] = pending[position - 1];
        }
        pending[index] = entry;
        bumpVersion();
        wakeAll(wakeWord);
    }

    private void bumpVersion() nothrow @nogc
    {
        atomicStore(wakeWord, atomicLoad(wakeWord) + 1);
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
                const now = monotonicNow();
                if (pending.length != 0)
                {
                    if (pending[0].deadline <= now)
                    {
                        command = pending[0].command;
                        pending[0].command = null;
                        pending = pending[1 .. $];
                        if (pending.length == 0)
                            pending = null;
                    }
                    else
                        sleepNanos = pending[0].deadline - now;
                }
                if (command is null && atomicLoad(stopping) && pending.length == 0)
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
                return;
            park(wakeWord, seen, sleepNanos < 0 ? long.max : sleepNanos);
        }
    }

    private static void runTask(Runnable command) nothrow
    {
        try
            command.run();
        catch (Exception)
        {
        }
    }
}

// Provider-equivalent periodic future: the same observable contract as the leaf's task, built directly on the
// existing Future, Delayed and RunnableScheduledFuture leaves.
private final class Periodic : RunnableScheduledFuture!Object
{
    mixin Future!Object.Defaults;

    private enum long maxParkNanos = 86_400_000_000_000L;

    private Runnable body;
    private long period;
    private bool fixedRate;
    private shared uint cancelled;
    private shared uint failed;
    private shared long due;
    private shared uint wake;
    private Throwable failure;
    private void delegate() @safe reschedule;

    this(Runnable body, long period, bool fixedRate) pure nothrow @nogc
    {
        this.body = body;
        this.period = period;
        this.fixedRate = fixedRate;
    }

    void setDue(long nanos) nothrow @nogc
    {
        atomicStore(due, nanos);
    }

    long dueNanos() nothrow @nogc
    {
        return atomicLoad(due);
    }

    bool isDoneNow() nothrow @nogc
    {
        return atomicLoad(cancelled) != 0 || atomicLoad(failed) != 0;
    }

    bool cancelNow() nothrow @nogc
    {
        if (atomicLoad(failed) != 0)
            return false;
        if (!cas(&cancelled, 0u, 1u))
            return false;
        wakeAll(wake);
        return true;
    }

    override void run()
    {
        if (atomicLoad(cancelled) != 0 || atomicLoad(failed) != 0)
            return;
        scope (failure)
        {
            if (atomicLoad(cancelled) == 0 && cas(&failed, 0u, 1u))
                wakeAll(wake);
        }
        try
            body.run();
        catch (Exception thrown)
        {
            if (atomicLoad(cancelled) == 0)
            {
                failure = thrown;
                if (cas(&failed, 0u, 1u))
                    wakeAll(wake);
            }
            return;
        }
        if (atomicLoad(cancelled) == 0 && atomicLoad(failed) == 0 && reschedule !is null)
        {
            const next = fixedRate ? saturatingAdd(atomicLoad(due), period) : saturatingAdd(monotonicNow(), period);
            setDue(next);
            reschedule();
        }
    }

    override bool cancel(bool mayInterruptIfRunning)
    {
        return cancelNow();
    }

    override bool isCancelled()
    {
        return atomicLoad(cancelled) != 0;
    }

    override bool isDone()
    {
        return isDoneNow();
    }

    override Object get()
    {
        awaitDone(long.max, false);
        return report();
    }

    override Object get(long timeout, TimeUnit unit)
    {
        awaitDone(toNanos(unit, timeout), true);
        return report();
    }

    override long getDelay(TimeUnit unit)
    {
        return convert(unit, atomicLoad(due) - monotonicNow(), TimeUnit.NANOSECONDS);
    }

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

    override bool isPeriodic() pure nothrow @nogc
    {
        return true;
    }

    private Object report()
    {
        if (atomicLoad(cancelled) != 0)
            throw new CancellationException;
        throw new ExecutionException(failure);
    }

    private void awaitDone(long timeoutNanos, bool timed)
    {
        long deadline = long.max;
        if (timed)
        {
            if (timeoutNanos <= 0)
            {
                if (isDoneNow())
                    return;
                throw new TimeoutException;
            }
            const now = monotonicNow();
            const available = long.max - 1 - now;
            deadline = timeoutNanos >= available ? long.max - 1 : now + timeoutNanos;
        }

        for (;;)
        {
            const seen = atomicLoad(wake);
            if (isDoneNow())
                return;
            long sleep = maxParkNanos;
            if (deadline != long.max)
            {
                const now = monotonicNow();
                if (now >= deadline)
                {
                    if (isDoneNow())
                        return;
                    throw new TimeoutException;
                }
                const remaining = deadline - now;
                if (remaining < sleep)
                    sleep = remaining;
            }
            if (sleep < 1)
                sleep = 1;
            park(wake, seen, sleep);
        }
    }
}

private long saturatingAdd(long value, long delta) pure nothrow @nogc
{
    const sum = value + delta;
    if (delta > 0 && sum < value)
        return long.max - 1;
    if (delta < 0 && sum > value)
        return long.min;
    return sum;
}

private long monotonicNow() nothrow @nogc
{
    return Deadline.afterMillis(0).monotonicNanoseconds;
}

private final class Run : Runnable
{
    override void run()
    {
    }
}

private final class Counter : Runnable
{
    shared uint runs;

    override void run()
    {
        atomicStore(runs, atomicLoad(runs) + 1);
    }
}

int main(string[] args)
{
    auto scheduler = new Scheduler;
    auto counter = new Counter;
    auto periodic = scheduler.schedulePeriodic(counter, 0, 1_000_000, true);
    shared uint idle;
    park(idle, 0, 20_000_000L);
    periodic.cancel(false);
    scheduler.shutdownNow();
    if (periodic.isDone() != periodic.isCancelled() || atomicLoad(counter.runs) == 0)
        return 1;

    auto again = new Scheduler;
    auto task = new FutureTask!int(new Run, 7);
    again.schedule(task, args.length == 1 ? 1 : 0);

    if (args.length > 1)
    {
        auto commands = again.shutdownNow();
        return commands.size() == 1 && commands.get(0) is task ? 0 : 1;
    }

    int result;
    try
        result = task.get(5_000_000_000L, TimeUnit.NANOSECONDS);
    catch (Exception)
        return 1;
    again.shutdown();
    return result == 7 ? 0 : 1;
}
