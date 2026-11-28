module flint.java.util.concurrent.scheduledexecutorservice_provider;

import core.atomic : atomicLoad, atomicStore;
import core.sync.mutex : Mutex;
import flint.arena : Status;
import flint.conc : Background, Deadline, startManagedBackground;
import flint.conc.park : park, wakeAll;
import flint.java.lang.runnable : Runnable;
import flint.java.util : ArrayList, List;
import flint.java.util.concurrent : TimeUnit;
import flint.java.util.concurrent.executorservice : ExecutorService;
import flint.java.util.concurrent.futuretask : FutureTask;

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

int main(string[] args)
{
    auto scheduler = new Scheduler;
    auto task = new FutureTask!int(new Run, 7);
    scheduler.schedule(task, args.length == 1 ? 1 : 0);

    if (args.length > 1)
    {
        auto commands = scheduler.shutdownNow();
        return commands.size() == 1 && commands.get(0) is task ? 0 : 1;
    }

    int result;
    try
        result = task.get(5_000_000_000L, TimeUnit.NANOSECONDS);
    catch (Exception)
        return 1;
    scheduler.shutdown();
    return result == 7 ? 0 : 1;
}
