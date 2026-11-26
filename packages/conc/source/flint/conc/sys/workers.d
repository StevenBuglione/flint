module flint.conc.sys.workers;

import core.atomic : MemoryOrder, atomicLoad, casWeak;
import core.stdc.stdlib : abort;
import core.thread.osthread : Thread;
import core.thread.threadbase : ThreadError;

@safe:

package(flint.conc) enum ticketSlotBits = 12;
package(flint.conc) enum maxTicketSlots = 1U << ticketSlotBits;

private shared ulong ticketCounter;

package(flint.conc) ulong issueTicket(uint slot) nothrow @nogc
{
    for (;;)
    {
        immutable counter = atomicLoad!(MemoryOrder.raw)(ticketCounter);
        if (counter == ulong.max >> ticketSlotBits)
            return 0;
        if (casWeak!(MemoryOrder.raw, MemoryOrder.raw)(&ticketCounter, counter, counter + 1))
            return ((counter + 1) << ticketSlotBits) | slot;
    }
}

/// How long an idle worker sleeps before it looks for work again. A compile-time constant: a run-time core.time
/// `dur` call would make the link take that instance from the first Phobos object defining it, socket.o, and with
/// it std.string, std.uni and curl.o (playbook S-9).
private enum idlePause = imported!"core.time".usecs(50);

static assert(idlePause == imported!"core.time".usecs(50), "an idle worker pauses 50 us");

package(flint.conc) void idleWorker() nothrow @nogc
{
    Thread.sleep(idlePause);
}

package(flint.conc) struct WorkerThreads
{
    private Thread[] started;
    private uint count;

    bool start(uint threads, void delegate() @safe nothrow run)
    {
        started = new Thread[threads];
        while (count < threads)
        {
            auto thread = new Thread(run);
            // Retain the thread object before launch can fail. Joining an
            // unstarted druntime thread is a no-op.
            started[count++] = thread;
            if (!launch(thread))
                return false;
        }
        return true;
    }

    void join() scope nothrow
    {
        foreach (thread; started[0 .. count])
            retire(thread);
        started = null;
        count = 0;
    }
}

// SAFETY: The managed thread and delegate are rooted by druntime. The pool
// publishes stable storage before startup, then joins before discarding it.
private bool launch(Thread thread) @trusted nothrow
{
    try
    {
        thread.start();
        return true;
    }
    catch (ThreadError)
    {
        return false;
    }
}

// SAFETY: Shutdown has one join owner and runs on a caller, outside worker
// callbacks. On a failed native join, continuing could retire live storage.
private void retire(Thread thread) @trusted nothrow
{
    try
    {
        thread.join();
    }
    catch (Exception)
    {
        abort();
    }
}
