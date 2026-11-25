module flint.os.sys.interrupts;

import core.atomic : atomicExchange, atomicLoad, atomicOp, atomicStore, cas;
import core.thread.osthread : Thread;
import core.thread.types : ThreadID;
import flint.arena : Error, Result, Status;
import flint.os.sys.process : nativeStatus, waitForOutput;
import flint.os.sys.threads : CoordinatorLaunch, attachForCallbacks, detachAfterCallbacks,
    joinLowLevel, orphanLowLevel, startLowLevel;
import flint.os.types : ShutdownSignal;

@safe:

// The latch carries one counter per signal: SIGINT adds 1 and SIGTERM adds 1 << 32, so one eventfd read
// (or one drain of the Darwin pipe) reports both counts. interrupt_latch.c writes the same encoding.
private enum ulong interruptUnit = 1;
private enum ulong terminateUnit = 1UL << 32;
private enum uint signalKinds = 2;

private uint maskOf(ShutdownSignal signal) pure nothrow @nogc
{
    return 1U << signal;
}

private ulong countOf(ulong counts, ShutdownSignal signal) pure nothrow @nogc
{
    return signal == ShutdownSignal.interrupt ? counts & uint.max : counts >> 32;
}

version (Windows)
{
    import core.sys.windows.windef : BOOL, DWORD;
    import flint.os.sys.process : openWake, takeWake, wakeHandle;

    private alias ControlHandler = extern (Windows) BOOL function(DWORD) nothrow @nogc @system;
    private extern (Windows) BOOL SetConsoleCtrlHandler(ControlHandler handler, BOOL add) nothrow @nogc @system;

    // The console runs control handlers on a thread of its own; this one only counts the event and sets the
    // latch event, which lives for the process once created, exactly like the POSIX notifier descriptor.
    private __gshared void* interruptEvent;
    // The latch encoding of the events not yet taken, and which kinds a subscription currently claims.
    private shared ulong pendingEvents;
    private shared uint claimedKinds;

    private extern (Windows) BOOL onConsoleControl(DWORD kind) nothrow @nogc @system
    {
        import core.sys.windows.winbase : SetEvent;

        // Ctrl+C is SIGINT and Ctrl+Break is SIGTERM. Close, logoff and shutdown keep their default
        // handling: Windows ends the process as soon as a handler for them returns.
        enum DWORD ctrlCEvent = 0;
        enum DWORD ctrlBreakEvent = 1;
        auto event = interruptEvent;
        const signal = kind == ctrlCEvent ? ShutdownSignal.interrupt : ShutdownSignal.terminate;
        if ((kind != ctrlCEvent && kind != ctrlBreakEvent) || event is null
                || (atomicLoad(claimedKinds) & maskOf(signal)) == 0)
            return 0;
        atomicOp!"+="(pendingEvents, signal == ShutdownSignal.interrupt ? interruptUnit : terminateUnit);
        SetEvent(event);
        return 1;
    }
}
else
{
    import core.stdc.errno : errno;
    import core.sys.posix.signal : SA_RESTART, SIGINT, SIGTERM, SIG_DFL, SIG_IGN, sigaction, sigaction_t, sigemptyset;
    import core.sys.posix.unistd : read;

    version (OSX)
    {
    }
    else
        import core.sys.linux.sys.eventfd : EFD_CLOEXEC, EFD_NONBLOCK, eventfd;

    private extern (C) @system nothrow @nogc
    {
        void flint_os_set_interrupt_fd(int descriptor);
        void flint_os_notify_interrupt(int number);
    }
}

private alias Callback = void delegate(ShutdownSignal) @safe;
private enum capacity = 32;

private struct Subscription
{
    ulong id;
    Callback callback;
    uint signals;
    bool callbackFailed;
    bool inFlight;
    bool closing;
}

/// The process disposition of one signal: claimed while any subscription wants that signal.
private struct Disposition
{
    uint users;
    version (Posix) sigaction_t previous;
    bool owned;
}

private struct Coordinator
{
    Subscription[capacity] subscriptions;
    size_t count;
    ulong lastId;
    ulong epoch;
    /// The coordinator: a thread druntime does not know until it first has callbacks to run, so a stop-the-world
    /// collection neither signals nor scans it while it waits (docs/spring/phase1/gc.md, section 3c).
    ThreadID worker;
    bool running;
    /// The epoch of a coordinator that retired itself from one of its own callbacks: nobody joins it.
    ulong orphanEpoch;
    Disposition[signalKinds] actions;
    int descriptor = -1;
    version (Windows) bool ownsHandler;
}

private __gshared Coordinator coordinator;
private shared bool locked;
private bool onCoordinator;

// SAFETY: This module accesses coordinator only between lock and unlock.
private Coordinator* lock() @trusted nothrow @nogc
{
    while (!cas(&locked, false, true))
        Thread.yield();
    return &coordinator;
}

private void unlock() nothrow @nogc
{
    atomicStore(locked, false);
}

version (Windows)
{
    // SAFETY: The wake descriptor and its event live for the process once created; the control handler only
    // signals that event, so it is never repurposed.
    private Error initializeLatch(ref Coordinator state) @trusted nothrow @nogc
    {
        if (state.descriptor >= 0)
            return Error.init;
        const descriptor = openWake();
        if (descriptor < 0)
            return Error(Status.resourceExhausted, "could not create interrupt notifier");
        state.descriptor = descriptor;
        interruptEvent = wakeHandle(descriptor);
        return Error.init;
    }
}
else
{
    // SAFETY: This fd is assigned to the native notifier once and lives for the process.
    // A signal frame may have captured the action before restoration, so the fd is never repurposed.
    private Error initializeLatch(ref Coordinator state) @trusted nothrow @nogc
    {
        if (state.descriptor >= 0)
            return Error.init;
        version (OSX)
        {
            // Darwin has no eventfd: the handler writes into a nonblocking pipe whose ends both live
            // for the process. takeSignal drains every pending notification at once, as eventfd does.
            import core.sys.posix.fcntl : FD_CLOEXEC, F_SETFD, F_SETFL, O_NONBLOCK, fcntl;
            import core.sys.posix.unistd : close, pipe;

            int[2] ends;
            if (pipe(ends) != 0)
                return Error(nativeStatus(errno), "could not create interrupt notifier");
            foreach (end; ends)
            {
                if (fcntl(end, F_SETFD, FD_CLOEXEC) != 0 || fcntl(end, F_SETFL, O_NONBLOCK) != 0)
                {
                    const status = nativeStatus(errno);
                    close(ends[0]);
                    close(ends[1]);
                    return Error(status, "could not configure interrupt notifier");
                }
            }
            state.descriptor = ends[0];
            flint_os_set_interrupt_fd(ends[1]);
        }
        else
        {
            const descriptor = eventfd(0, EFD_CLOEXEC | EFD_NONBLOCK);
            if (descriptor < 0)
                return Error(nativeStatus(errno), "could not create interrupt notifier");
            state.descriptor = descriptor;
            flint_os_set_interrupt_fd(descriptor);
        }
        return Error.init;
    }
}

private Error startCoordinator(ref Coordinator state) nothrow @nogc
{
    if (state.running)
        return Error.init;

    const epoch = ++state.epoch;
    const started = startLowLevel(CoordinatorLaunch(state.descriptor, epoch, &dispatchLoop));
    if (!started.ok)
    {
        --state.epoch;
        return started.error;
    }
    state.worker = started.value;
    state.running = true;
    return Error.init;
}

version (Windows)
{
    // Windows cannot list other control handlers, so one an application registers later runs first and may claim
    // the event; Flint's handler then never sees it.
    // SAFETY: Registers the handler above, which only signals the process-lifetime latch event.
    private Error install(ref Coordinator state, ShutdownSignal signal) @trusted nothrow @nogc
    {
        import core.sys.windows.winbase : GetLastError;

        if (state.actions[signal].owned)
            return Error.init;
        if (!state.ownsHandler)
        {
            cast(void) takeSignal(state.descriptor);
            if (!SetConsoleCtrlHandler(&onConsoleControl, 1))
                return Error(nativeStatus(GetLastError()), "could not install the Ctrl+C notifier");
            state.ownsHandler = true;
        }
        state.actions[signal].owned = true;
        atomicOp!"|="(claimedKinds, maskOf(signal));
        return Error.init;
    }

    // SAFETY: Removes only Flint's own handler, once neither kind is claimed.
    private Error restore(ref Coordinator state, ShutdownSignal signal) @trusted nothrow @nogc
    {
        import core.sys.windows.winbase : GetLastError;

        if (!state.actions[signal].owned)
            return Error.init;
        state.actions[signal].owned = false;
        atomicOp!"&="(claimedKinds, ~maskOf(signal));
        if (!state.ownsHandler || atomicLoad(claimedKinds) != 0)
            return Error.init;
        state.ownsHandler = false;
        if (!SetConsoleCtrlHandler(&onConsoleControl, 0))
            return Error(nativeStatus(GetLastError()), "could not remove the Ctrl+C notifier");
        return Error.init;
    }

    private ulong takeSignal(int fd) nothrow @nogc
    {
        if (!takeWake(fd))
            return 0;
        return atomicExchange(&pendingEvents, 0UL);
    }
}
else
{
    private int numberOf(ShutdownSignal signal) pure nothrow @nogc
    {
        return signal == ShutdownSignal.interrupt ? SIGINT : SIGTERM;
    }

    // SAFETY: The raw C action runs only the event notifier. The application callback stays in the D registry.
    // This action only claims the signal when no independent custom handler currently owns it.
    private Error install(ref Coordinator state, ShutdownSignal signal) @trusted nothrow @nogc
    {
        auto disposition = &state.actions[signal];
        if (disposition.owned)
            return Error.init;

        const number = numberOf(signal);
        sigaction_t previous;
        if (sigaction(number, null, &previous) != 0)
            return Error(nativeStatus(errno), "could not inspect the signal disposition");
        if (previous.sa_handler != SIG_DFL && previous.sa_handler != SIG_IGN)
            return Error(Status.conflict, signal == ShutdownSignal.interrupt
                    ? "SIGINT already has an application handler" : "SIGTERM already has an application handler");

        if (state.actions[0].users + state.actions[1].users == 0)
            cast(void) takeSignal(state.descriptor);
        sigaction_t action;
        if (sigemptyset(&action.sa_mask) != 0)
            return Error(nativeStatus(errno), "could not prepare the signal disposition");
        action.sa_handler = &flint_os_notify_interrupt;
        action.sa_flags = SA_RESTART;

        if (sigaction(number, &action, &disposition.previous) != 0)
            return Error(nativeStatus(errno), "could not install the signal notifier");
        disposition.owned = true;
        return Error.init;
    }

    // SAFETY: Only the previously saved action is restored, and only while the current action is ours.
    private Error restore(ref Coordinator state, ShutdownSignal signal) @trusted nothrow @nogc
    {
        auto disposition = &state.actions[signal];
        if (!disposition.owned)
            return Error.init;

        const number = numberOf(signal);
        sigaction_t current;
        if (sigaction(number, null, &current) != 0)
            return Error(nativeStatus(errno), "could not inspect the active signal notifier");
        disposition.owned = false;
        if (current.sa_handler != &flint_os_notify_interrupt)
            return Error(Status.conflict, "a signal action changed while subscribed");
        if (sigaction(number, &disposition.previous, null) != 0)
            return Error(nativeStatus(errno), "could not restore the previous signal action");
        return Error.init;
    }

    // Darwin's pipe carries whole eight-byte records that sum to what one eventfd read returns.
    // SAFETY: eventfd writes at most eight bytes to the local counter and borrows no storage.
    // On Darwin each read fills at most the local buffer from the nonblocking pipe.
    private ulong takeSignal(int fd) @trusted nothrow @nogc
    {
        version (OSX)
        {
            ulong[8] records;
            ulong total;
            for (;;)
            {
                const count = read(fd, records.ptr, records.sizeof);
                if (count <= 0)
                    return total;
                foreach (record; records[0 .. cast(size_t) count / ulong.sizeof])
                    total += record;
            }
        }
        else
        {
            ulong count;
            return read(fd, &count, count.sizeof) == count.sizeof ? count : 0;
        }
    }
}

/// Claim each signal in `signals` for one more subscription, rolling back on failure.
private Error claim(ref Coordinator state, uint signals) nothrow @nogc
{
    foreach (kind; 0 .. signalKinds)
    {
        const signal = cast(ShutdownSignal) kind;
        if ((signals & maskOf(signal)) == 0)
            continue;
        if (state.actions[kind].users == 0)
        {
            const installed = install(state, signal);
            if (installed.code != Status.ok)
            {
                release(state, signals & (maskOf(signal) - 1));
                return installed;
            }
        }
        ++state.actions[kind].users;
    }
    return Error.init;
}

/// Give back each signal in `signals`, restoring a disposition its last user held.
private Error release(ref Coordinator state, uint signals) nothrow @nogc
{
    Error result;
    foreach (kind; 0 .. signalKinds)
    {
        const signal = cast(ShutdownSignal) kind;
        if ((signals & maskOf(signal)) == 0 || state.actions[kind].users == 0)
            continue;
        if (--state.actions[kind].users != 0)
            continue;
        const restored = restore(state, signal);
        if (restored.code != Status.ok && result.code == Status.ok)
            result = restored;
    }
    return result;
}

/// Subscribe `callback` to the signals in `signals`, a mask of `1 << ShutdownSignal`.
package(flint.os) Result!ulong registerInterrupt(Callback callback, uint signals)
{
    if (callback is null || signals == 0 || signals >= 1U << signalKinds)
        return Result!ulong(0, Error(Status.invalidArgument, "interrupt callback and signals required"));
    auto state = lock();
    scope (exit)
        unlock();

    if (state.count == capacity || state.lastId == ulong.max)
        return Result!ulong(0, Error(Status.resourceExhausted, "interrupt subscriptions exhausted"));
    const started = initializeLatch(*state);
    if (started.code != Status.ok)
        return Result!ulong(0, started);
    size_t free = capacity;
    foreach (slot, ref entry; state.subscriptions)
    {
        if (entry.id == 0)
        {
            free = slot;
            break;
        }
    }
    if (free == capacity)
        return Result!ulong(0, Error(Status.resourceExhausted, "interrupt callbacks still retiring"));
    const claimed = claim(*state, signals);
    if (claimed.code != Status.ok)
        return Result!ulong(0, claimed);

    const coordinatorStarted = startCoordinator(*state);
    if (coordinatorStarted.code != Status.ok)
    {
        release(*state, signals);
        return Result!ulong(0, coordinatorStarted);
    }
    const id = ++state.lastId;
    state.subscriptions[free] = Subscription(id, callback, signals);
    ++state.count;
    return Result!ulong(id);
}

package(flint.os) Error unregisterInterrupt(ulong id) nothrow
{
    auto state = lock();
    Error result;
    ThreadID retiredWorker;
    bool retired;
    size_t removedSlot = state.subscriptions.length;

    foreach (slot, ref entry; state.subscriptions)
    {
        if (entry.id != id)
            continue;
        if (entry.callbackFailed)
            result = Error(Status.ioError, "interrupt callback failed");

        const restored = release(*state, entry.signals);
        if (restored.code != Status.ok)
            result = restored;
        entry.callback = null;
        entry.closing = true;
        removedSlot = slot;
        if (!entry.inFlight)
            entry = Subscription.init;
        if (--state.count == 0)
        {
            retiredWorker = state.worker;
            retired = state.running;
            state.worker = ThreadID.init;
            state.running = false;
            // A coordinator retiring itself from its own callback cannot be joined: it detaches as it ends.
            if (retired && onCoordinator)
                state.orphanEpoch = state.epoch;
        }
        break;
    }
    unlock();

    if (!onCoordinator)
    {
        if (retired)
            joinLowLevel(retiredWorker);
        else if (removedSlot < capacity)
            waitForCallback(removedSlot, id);
    }
    return result;
}

private void waitForCallback(size_t slot, ulong id) nothrow @nogc
{
    for (;;)
    {
        auto state = lock();
        const finished = state.subscriptions[slot].id != id || !state.subscriptions[slot].inFlight;
        unlock();
        if (finished)
            return;
        waitForOutput(-1, -1, 1);
    }
}

private bool orphaned(ulong epoch) nothrow @nogc
{
    auto state = lock();
    scope (exit)
        unlock();
    return state.orphanEpoch == epoch;
}

private struct Notification
{
    bool terminating;
    ulong through;
    ulong counts;
}

private Notification notifications(int fd, ulong epoch) nothrow @nogc
{
    auto state = lock();
    scope (exit)
        unlock();
    if (!state.running || state.epoch != epoch)
        return Notification(true);
    const counts = takeSignal(fd);
    if (counts == 0)
        return Notification.init;
    return Notification(false, state.lastId, counts);
}

private Subscription beginCallback(size_t slot, ulong through, ulong epoch) nothrow @nogc
{
    auto state = lock();
    scope (exit)
        unlock();
    auto entry = &state.subscriptions[slot];
    if (state.epoch != epoch || entry.id > through || entry.callback is null)
        return Subscription.init;
    entry.inFlight = true;
    return Subscription(entry.id, entry.callback, entry.signals);
}

private void finishCallback(size_t slot, ulong id, bool failed) nothrow @nogc
{
    auto state = lock();
    scope (exit)
        unlock();
    auto entry = &state.subscriptions[slot];
    assert(entry.id == id);
    entry.inFlight = false;
    if (entry.closing)
        *entry = Subscription.init;
    else if (failed)
    {
        entry.callback = null;
        entry.callbackFailed = true;
    }
}

/// Run one subscription's callback once per signal it wants: two signals of one kind that arrived together
/// are two calls, so a second signal is never lost, and any beyond the second are coalesced.
private bool deliver(ref Subscription active, ulong counts) nothrow
{
    foreach (kind; 0 .. signalKinds)
    {
        const signal = cast(ShutdownSignal) kind;
        if ((active.signals & maskOf(signal)) == 0)
            continue;
        const count = countOf(counts, signal);
        foreach (_; 0 .. count < 2 ? count : 2)
        {
            try
                active.callback(signal);
            catch (Exception)
                return false;
        }
    }
    return true;
}

/// The coordinator's loop. It waits unregistered: druntime neither signals nor scans it, and it touches no GC memory.
/// The first notification with callbacks to run attaches it to druntime (with this thread's module constructors),
/// for good: druntime cannot attach a thread a second time once it detached, and a shutdown signal is rare, so the
/// coordinator stays registered until it retires.
private void dispatchLoop(int fd, ulong epoch) nothrow
{
    onCoordinator = true;
    bool attached;
    scope (exit)
    {
        if (attached)
            detachAfterCallbacks();
        if (orphaned(epoch))
            orphanLowLevel();
    }
    for (;;)
    {
        waitForOutput(fd, -1, 20);
        const notification = notifications(fd, epoch);
        if (notification.terminating)
            return;
        if (notification.through == 0)
            continue;
        if (!attached)
        {
            attachForCallbacks();
            attached = true;
        }
        foreach (slot; 0 .. capacity)
        {
            auto active = beginCallback(slot, notification.through, epoch);
            if (active.callback is null)
                continue;
            finishCallback(slot, active.id, !deliver(active, notification.counts));
        }
    }
}
