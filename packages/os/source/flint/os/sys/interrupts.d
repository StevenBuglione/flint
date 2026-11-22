module flint.os.sys.interrupts;

import core.atomic : atomicStore, cas;
import core.stdc.errno : errno;
import core.sys.posix.signal : SA_RESTART, SIGINT, SIG_DFL, SIG_IGN, sigaction, sigaction_t, sigemptyset;
import core.sys.posix.unistd : read;
import core.thread : Thread;
import flint.arena : Error, Result, Status;
import flint.os.sys.process : nativeStatus, waitForOutput;
import flint.os.sys.threads : joinThread;

@safe:

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

private alias Callback = void delegate() @safe;
private enum capacity = 32;

private struct Subscription
{
    ulong id;
    Callback callback;
    bool callbackFailed;
    bool inFlight;
    bool closing;
}

private struct Coordinator
{
    Subscription[capacity] subscriptions;
    size_t count;
    ulong lastId;
    ulong epoch;
    Thread worker;
    sigaction_t previous;
    int descriptor = -1;
    bool ownsAction;
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

// SAFETY: The daemon captures only its immutable descriptor and epoch, and uses a safe D entry.
private @trusted void startCoordinator(ref Coordinator state)
{
    if (state.worker !is null)
        return;

    const epoch = ++state.epoch;
    const descriptor = state.descriptor;
    auto worker = new Thread(() { dispatchLoop(descriptor, epoch); });
    worker.isDaemon = true;
    worker.start();
    state.worker = worker;
}

// SAFETY: The raw C action runs only the event notifier. The application callback stays in the D registry.
// This action only claims SIGINT when no independent custom handler currently owns it.
private Error install(ref Coordinator state) @trusted nothrow @nogc
{
    if (state.ownsAction)
        return Error.init;

    sigaction_t previous;
    if (sigaction(SIGINT, null, &previous) != 0)
        return Error(nativeStatus(errno), "could not inspect SIGINT disposition");
    if (previous.sa_handler != SIG_DFL && previous.sa_handler != SIG_IGN)
        return Error(Status.conflict, "SIGINT already has an application handler");

    cast(void) takeSignal(state.descriptor);
    sigaction_t action;
    if (sigemptyset(&action.sa_mask) != 0)
        return Error(nativeStatus(errno), "could not prepare SIGINT disposition");
    action.sa_handler = &flint_os_notify_interrupt;
    action.sa_flags = SA_RESTART;

    if (sigaction(SIGINT, &action, &state.previous) != 0)
        return Error(nativeStatus(errno), "could not install SIGINT notifier");
    state.ownsAction = true;
    return Error.init;
}

// SAFETY: Only the previously saved action is restored, and only while the current action is ours.
private Error restore(ref Coordinator state) @trusted nothrow @nogc
{
    if (!state.ownsAction)
        return Error.init;

    sigaction_t current;
    if (sigaction(SIGINT, null, &current) != 0)
        return Error(nativeStatus(errno), "could not inspect active SIGINT notifier");
    if (current.sa_handler != &flint_os_notify_interrupt)
    {
        state.ownsAction = false;
        return Error(Status.conflict, "SIGINT action changed while subscribed");
    }
    if (sigaction(SIGINT, &state.previous, null) != 0)
        return Error(nativeStatus(errno), "could not restore previous SIGINT action");
    state.ownsAction = false;
    return Error.init;
}

// SAFETY: eventfd writes at most eight bytes to the local counter and borrows no storage.
// On Darwin each read fills at most the local buffer from the nonblocking pipe.
private bool takeSignal(int fd) @trusted nothrow @nogc
{
    version (OSX)
    {
        ulong[8] counts;
        bool any;
        while (read(fd, counts.ptr, counts.sizeof) > 0)
            any = true;
        return any;
    }
    else
    {
        ulong count;
        return read(fd, &count, count.sizeof) == count.sizeof;
    }
}

package(flint.os) Result!ulong registerInterrupt(Callback callback)
{
    if (callback is null)
        return Result!ulong(0, Error(Status.invalidArgument, "interrupt callback required"));
    auto state = lock();
    scope (exit)
        unlock();

    if (state.count == capacity || state.lastId == ulong.max)
        return Result!ulong(0, Error(Status.resourceExhausted, "interrupt subscriptions exhausted"));
    const started = initializeLatch(*state);
    if (started.code != Status.ok)
        return Result!ulong(0, started);
    const installed = install(*state);
    if (installed.code != Status.ok)
        return Result!ulong(0, installed);

    scope (failure)
    {
        if (state.count == 0)
            restore(*state);
    }
    foreach (ref entry; state.subscriptions)
    {
        if (entry.id != 0)
            continue;
        startCoordinator(*state);
        const id = ++state.lastId;
        entry = Subscription(id, callback);
        ++state.count;
        return Result!ulong(id);
    }
    if (state.count == 0)
        restore(*state);
    return Result!ulong(0, Error(Status.resourceExhausted, "interrupt callbacks still retiring"));
}

package(flint.os) Error unregisterInterrupt(ulong id) nothrow
{
    auto state = lock();
    Error result;
    Thread retiredWorker;
    size_t removedSlot = state.subscriptions.length;

    foreach (slot, ref entry; state.subscriptions)
    {
        if (entry.id != id)
            continue;
        if (entry.callbackFailed)
            result = Error(Status.ioError, "interrupt callback failed");

        entry.callback = null;
        entry.closing = true;
        removedSlot = slot;
        if (!entry.inFlight)
            entry = Subscription.init;
        if (--state.count == 0)
        {
            const restored = restore(*state);
            if (restored.code != Status.ok)
                result = restored;

            retiredWorker = state.worker;
            state.worker = null;
        }
        break;
    }
    unlock();

    if (!onCoordinator)
    {
        if (retiredWorker !is null)
        {
            if (joinThread(retiredWorker) !is null && result.code == Status.ok)
                result = Error(Status.ioError, "interrupt coordinator could not join");
        }
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

private struct Notification
{
    bool terminating;
    ulong through;
}

private Notification notifications(int fd, ulong epoch) nothrow @nogc
{
    auto state = lock();
    scope (exit)
        unlock();
    if (state.worker is null || state.epoch != epoch)
        return Notification(true);
    if (!takeSignal(fd))
        return Notification.init;
    return Notification(false, state.lastId);
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
    return Subscription(entry.id, entry.callback);
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

private void dispatchLoop(int fd, ulong epoch) nothrow
{
    onCoordinator = true;
    for (;;)
    {
        waitForOutput(fd, -1, 20);
        const notification = notifications(fd, epoch);
        if (notification.terminating)
            return;
        if (notification.through == 0)
            continue;
        foreach (slot; 0 .. capacity)
        {
            auto active = beginCallback(slot, notification.through, epoch);
            if (active.callback is null)
                continue;
            bool failed;
            try
                active.callback();
            catch (Exception)
                failed = true;
            finishCallback(slot, active.id, failed);
        }
    }
}
