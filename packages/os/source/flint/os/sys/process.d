module flint.os.sys.process;

import core.stdc.stdlib : free, malloc;
import core.stdc.string : memcpy;
import core.stdc.errno : EACCES, EAGAIN, ECHILD, EINVAL, EINTR, EMFILE, ENFILE, ENOENT, ENOMEM,
    ENOSYS, ENOTDIR, EPERM, ESRCH, errno;
import core.sys.posix.fcntl : F_GETFL, F_SETFL, O_NONBLOCK, O_RDONLY, fcntl, open;
import core.sys.posix.poll : POLLIN, POLLNVAL, poll, pollfd;
import core.sys.posix.signal : SA_NOCLDWAIT, SIGCHLD, SIGINT, SIGKILL, SIGPIPE, SIGTERM, SIG_DFL,
    SIG_IGN, SIG_SETMASK, kill, sigaction, sigaction_t, sigemptyset, siginfo_t, sigprocmask, sigset_t;
import core.sys.posix.sys.wait : idtype_t, WEXITED, WEXITSTATUS, WIFEXITED, WNOHANG, WNOWAIT,
    WTERMSIG, waitid, waitpid;
import core.sys.posix.unistd : _exit, chdir, close, dup2, execve, fork, getpgrp, read, setpgid, write;
import flint.arena : Error, Result, Status;
import flint.os.types : ExitStatus;

@safe:

version (OSX)
{
    // <sys/fcntl.h> values druntime omits for Darwin.
    private enum int O_CLOEXEC = 0x0100_0000;
    private enum int searchDirectory = 0x4010_0000; // O_SEARCH: O_EXEC | O_DIRECTORY
}
else
{
    import core.sys.linux.unistd : syscall;
    import core.sys.posix.fcntl : O_CLOEXEC;
    import core.sys.posix.unistd : pipe2;
}

package(flint.os):

struct Child
{
    int pid;
    int stdoutFd = -1;
    int stderrFd = -1;
    int startupFd = -1;
}

private struct Pipe
{
    int reader = -1;
    int writer = -1;
}

private struct Descriptors
{
    Pipe stdoutPipe;
    Pipe stderrPipe;
    Pipe startup;
    int input = -1;
}

version (OSX)
    private enum int duplicateCloexec = 67; // F_DUPFD_CLOEXEC in <sys/fcntl.h>
else
{
    private enum int duplicateCloexec = 1030;
    private enum long closeRangeNumber = 436;
    private enum uint closeRangeCloexec = 4;
}

Status nativeStatus(int code) pure nothrow @nogc
{
    switch (code)
    {
    case ENOENT:
    case ENOTDIR:
        return Status.notFound;
    case EACCES:
    case EPERM:
        return Status.permissionDenied;
    case ENOMEM:
        return Status.outOfMemory;
    case EMFILE:
    case ENFILE:
    case EAGAIN:
        return Status.resourceExhausted;
    case EINVAL:
        return Status.invalidArgument;
    case ENOSYS:
        return Status.unsupported;
    default:
        return Status.ioError;
    }
}

// SAFETY: Positive descriptors are owned by this call's child or parent scope.
void closeFd(ref int descriptor) @trusted nothrow @nogc
{
    if (descriptor < 0)
        return;
    const owned = descriptor;
    descriptor = -1;
    close(owned);
}

private void closePipe(ref Pipe pipe) nothrow @nogc
{
    closeFd(pipe.reader);
    closeFd(pipe.writer);
}

private void closeDescriptors(ref Descriptors descriptors) nothrow @nogc
{
    closePipe(descriptors.stdoutPipe);
    closePipe(descriptors.stderrPipe);
    closePipe(descriptors.startup);
    closeFd(descriptors.input);
}

void closeChildPipes(ref Child child) nothrow @nogc
{
    closeFd(child.stdoutFd);
    closeFd(child.stderrFd);
    closeFd(child.startupFd);
}

// SAFETY: The incoming fd is already owned. A successful duplication moves the owner above stdio.
private bool moveAboveStdio(ref int fd) @trusted nothrow @nogc
{
    if (fd > 2)
        return true;
    const duplicate = fcntl(fd, duplicateCloexec, 3);
    if (duplicate < 0)
        return false;
    closeFd(fd);
    fd = duplicate;
    return true;
}

version (OSX)
{
    // Darwin has no pipe2. A concurrent fork and exec elsewhere could inherit both ends until
    // FD_CLOEXEC is set; children this package starts never do (POSIX_SPAWN_CLOEXEC_DEFAULT).
    // SAFETY: pipe initializes both local slots, and each is closed if it cannot be marked.
    private int closeOnExecPipe(ref int[2] fds) @trusted nothrow @nogc
    {
        import core.sys.posix.fcntl : FD_CLOEXEC, F_SETFD;
        import core.sys.posix.unistd : pipe;

        if (pipe(fds) < 0)
            return -1;
        if (fcntl(fds[0], F_SETFD, FD_CLOEXEC) == 0 && fcntl(fds[1], F_SETFD, FD_CLOEXEC) == 0)
            return 0;
        const code = errno;
        close(fds[0]);
        close(fds[1]);
        errno = code;
        return -1;
    }
}

// SAFETY: pipe2 initializes both local slots before ownership transfer and both are closed on failure.
private Result!Pipe createPipe() @trusted nothrow @nogc
{
    int[2] fds;
    version (OSX)
        const created = closeOnExecPipe(fds);
    else
        const created = pipe2(fds, O_CLOEXEC);
    if (created < 0)
        return Result!Pipe(Pipe.init, Error(nativeStatus(errno), "could not create child pipe"));

    auto pipe = Pipe(fds[0], fds[1]);
    if (moveAboveStdio(pipe.reader) && moveAboveStdio(pipe.writer))
    {
        const flags = fcntl(pipe.reader, F_GETFL);
        if (flags >= 0 && fcntl(pipe.reader, F_SETFL, flags | O_NONBLOCK) == 0)
            return Result!Pipe(pipe);
    }
    const status = nativeStatus(errno);
    closePipe(pipe);
    return Result!Pipe(Pipe.init, Error(status, "could not configure child pipe"));
}

// SAFETY: Child setup passes a literal NUL-terminated device path and owns the returned descriptor.
private Result!int openChildInput() @trusted nothrow @nogc
{
    int fd = open("/dev/null", O_RDONLY | O_CLOEXEC);
    scope (exit)
        closeFd(fd);
    if (fd < 0 || !moveAboveStdio(fd))
    {
        return Result!int(-1, Error(nativeStatus(errno), "could not open child input"));
    }
    const owned = fd;
    fd = -1;
    return Result!int(owned);
}

// SAFETY: Reading the current SIGCHLD disposition only writes one local structure.
private bool canWait() @trusted nothrow @nogc
{
    sigaction_t current;
    return sigaction(SIGCHLD, null, &current) == 0 && current.sa_handler != SIG_IGN
        && !(current.sa_flags & SA_NOCLDWAIT);
}

Error validateWaitPolicy() nothrow @nogc
{
    return canWait() ? Error.init : Error(Status.unsupported, "child wait disposition prevents supervision");
}

private Result!Descriptors prepareDescriptors() nothrow @nogc
{
    Descriptors descriptors;
    const output = createPipe();
    if (!output.ok)
        return Result!Descriptors(Descriptors.init, output.error);
    descriptors.stdoutPipe = output.value;

    const errors = createPipe();
    if (!errors.ok)
    {
        closeDescriptors(descriptors);
        return Result!Descriptors(Descriptors.init, errors.error);
    }
    descriptors.stderrPipe = errors.value;

    const startup = createPipe();
    if (!startup.ok)
    {
        closeDescriptors(descriptors);
        return Result!Descriptors(Descriptors.init, startup.error);
    }
    descriptors.startup = startup.value;

    const input = openChildInput();
    if (!input.ok)
    {
        closeDescriptors(descriptors);
        return Result!Descriptors(Descriptors.init, input.error);
    }
    descriptors.input = input.value;
    return Result!Descriptors(descriptors);
}

// These child-side functions touch only the stack and async-signal-safe libc entry points.
// Their pointer arguments refer to the inherited copy of the validated parent's argv/env vectors.
private extern (C) void reportFailure(int fd, int code) @system nothrow @nogc
{
    while (write(fd, &code, code.sizeof) < 0 && errno == EINTR)
    {
    }
    _exit(127);
}

private extern (C) bool initializeSignals() @system nothrow @nogc
{
    sigset_t empty;
    sigaction_t defaults;
    if (sigemptyset(&empty) != 0 || sigemptyset(&defaults.sa_mask) != 0)
        return false;
    defaults.sa_handler = SIG_DFL;
    return sigaction(SIGINT, &defaults, null) == 0 && sigaction(SIGPIPE, &defaults, null) == 0
        && sigaction(SIGTERM, &defaults, null) == 0 && sigprocmask(SIG_SETMASK, &empty, null) == 0;
}

private extern (C) void enterChild(Descriptors fds, const(char)* directory,
        const(char)** candidates, const(char)** argv, const(char)** envp) @system nothrow @nogc
{
    if (setpgid(0, 0) != 0 || !initializeSignals())
        reportFailure(fds.startup.writer, errno);
    if (dup2(fds.input, 0) < 0 || dup2(fds.stdoutPipe.writer, 1) < 0 || dup2(fds.stderrPipe.writer, 2) < 0)
        reportFailure(fds.startup.writer, errno);
    if (directory !is null && chdir(directory) != 0)
        reportFailure(fds.startup.writer, errno);
    version (linux)
    {
        if (syscall(closeRangeNumber, 3U, uint.max, closeRangeCloexec) != 0)
            reportFailure(fds.startup.writer, errno);
    }

    int lastError = ENOENT;
    while (*candidates !is null)
    {
        execve(*candidates, argv, envp);
        const failure = errno;
        if (failure == EACCES)
            lastError = EACCES;
        else if (failure != ENOENT && failure != ENOTDIR)
            reportFailure(fds.startup.writer, failure);
        ++candidates;
    }
    reportFailure(fds.startup.writer, lastError);
}

// SAFETY: The native argv, environment and cwd copies are private to this call and outlive the
// fork or spawn that borrows them. The parent releases only its own copy.
@trusted Result!Child launch(scope string[] paths, scope string[] args, scope string[] env, string directory)
{
    auto candidates = copyVector(paths);
    scope (exit)
        free(candidates);
    auto argv = copyVector(args);
    scope (exit)
        free(argv);
    auto envp = copyVector(env);
    scope (exit)
        free(envp);

    const(char)* cwd;
    scope (exit)
        free(cast(void*) cwd);
    if (directory.length != 0)
    {
        cwd = cast(const(char)*) malloc(directory.length);
        if (cwd is null)
            return Result!Child(Child.init, Error(Status.outOfMemory, "could not allocate child working directory"));
        memcpy(cast(void*) cwd, directory.ptr, directory.length);
    }
    if (candidates is null || argv is null || envp is null)
        return Result!Child(Child.init, Error(Status.outOfMemory, "could not allocate child argv or environment"));
    auto prepared = prepareDescriptors();
    if (!prepared.ok)
        return Result!Child(Child.init, prepared.error);

    auto fds = prepared.value;
    version (OSX)
        return spawnChild(fds, cwd, candidates, argv, envp);
    else
        return forkChild(fds, cwd, candidates, argv, envp);
}

version (OSX)
{
    import core.sys.posix.spawn : posix_spawn, posix_spawn_file_actions_adddup2,
        posix_spawn_file_actions_destroy,
        posix_spawn_file_actions_init, posix_spawn_file_actions_t, posix_spawnattr_destroy,
        posix_spawnattr_init,
        posix_spawnattr_setflags,
        posix_spawnattr_setpgroup,
        posix_spawnattr_setsigdefault, posix_spawnattr_setsigmask, posix_spawnattr_t,
        POSIX_SPAWN_SETPGROUP, POSIX_SPAWN_SETSIGDEF, POSIX_SPAWN_SETSIGMASK;

    // <spawn.h> Apple extensions. CLOEXEC_DEFAULT closes every descriptor that is not a file
    // action's target, which close_range gives the forked child on Linux.
    private enum short spawnCloexecDefault = 0x4000; // POSIX_SPAWN_CLOEXEC_DEFAULT
    private alias SpawnActions = posix_spawn_file_actions_t;
    private extern (C) @system nothrow @nogc int posix_spawn_file_actions_addfchdir_np(
            posix_spawn_file_actions_t*, int);

    // Darwin reports a failed exec synchronously, so no child exists to send a startup receipt.
    // The parent closes the receipt pipe's writer, and the supervisor reads a successful start.
    // SAFETY: Only the parent's owned descriptors are closed; the readers move to the Child.
    private Result!Child spawnChild(ref Descriptors fds, const(char)* directory,
            const(char)** candidates, const(char)** argv, const(char)** envp) @trusted nothrow @nogc
    {
        int directoryFd = -1;
        scope (exit)
            closeFd(directoryFd);
        // Opening first gives the chdir failure the Linux child reports; fchdir then cannot miss.
        if (directory !is null && (directoryFd = open(directory, searchDirectory | O_CLOEXEC)) < 0)
        {
            const status = nativeStatus(errno);
            closeDescriptors(fds);
            return Result!Child(Child.init, Error(status, "could not start requested child"));
        }
        const spawned = spawnCandidates(fds, directoryFd, candidates, argv, envp);
        closeFd(fds.stdoutPipe.writer);
        closeFd(fds.stderrPipe.writer);
        closeFd(fds.startup.writer);
        closeFd(fds.input);
        if (!spawned.ok)
        {
            closeDescriptors(fds);
            return Result!Child(Child.init, spawned.error);
        }
        return Result!Child(Child(spawned.value, fds.stdoutPipe.reader, fds.stderrPipe.reader, fds.startup.reader));
    }

    // SAFETY: The signal sets are local and every call only stores them in the caller's live attributes.
    private int configureAttributes(ref posix_spawnattr_t attributes) @trusted nothrow @nogc
    {
        import core.sys.posix.signal : sigaddset;

        enum short flags = POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK | spawnCloexecDefault;
        sigset_t empty, defaults;
        if (sigemptyset(&empty) != 0 || sigemptyset(&defaults) != 0 || sigaddset(&defaults,
                SIGINT) != 0 || sigaddset(&defaults, SIGPIPE) != 0 || sigaddset(&defaults, SIGTERM) != 0)
            return EINVAL;
        int code = posix_spawnattr_setflags(&attributes, flags);
        if (code == 0)
            code = posix_spawnattr_setpgroup(&attributes, 0);
        if (code == 0)
            code = posix_spawnattr_setsigdefault(&attributes, &defaults);
        return code == 0 ? posix_spawnattr_setsigmask(&attributes, &empty) : code;
    }

    // SAFETY: Each action records descriptor numbers in the caller's live action list.
    @trusted private int configureActions(ref SpawnActions list, ref const Descriptors fds, int cwd) nothrow @nogc
    {
        int code = posix_spawn_file_actions_adddup2(&list, fds.input, 0);
        if (code == 0)
            code = posix_spawn_file_actions_adddup2(&list, fds.stdoutPipe.writer, 1);
        if (code == 0)
            code = posix_spawn_file_actions_adddup2(&list, fds.stderrPipe.writer, 2);
        if (code == 0 && cwd >= 0)
            code = posix_spawn_file_actions_addfchdir_np(&list, cwd);
        return code;
    }

    // posix_spawn borrows the terminated candidate, argv and environment vectors only during each call.
    // SAFETY: The attribute and action objects are local and destroyed on every path.
    private Result!int spawnCandidates(ref const Descriptors fds, int directoryFd,
            const(char)** candidates, const(char)** argv, const(char)** envp) @trusted nothrow @nogc
    {
        import core.sys.posix.sys.types : pid_t;

        posix_spawnattr_t attributes;
        posix_spawn_file_actions_t actions;
        if (posix_spawnattr_init(&attributes) != 0)
            return Result!int(-1, Error(Status.outOfMemory, "could not prepare child attributes"));
        scope (exit)
            posix_spawnattr_destroy(&attributes);
        if (posix_spawn_file_actions_init(&actions) != 0)
            return Result!int(-1, Error(Status.outOfMemory, "could not prepare child descriptors"));
        scope (exit)
            posix_spawn_file_actions_destroy(&actions);
        int code = configureAttributes(attributes);
        if (code == 0)
            code = configureActions(actions, fds, directoryFd);
        if (code != 0)
            return Result!int(-1, Error(nativeStatus(code), "could not prepare child process"));

        int lastError = ENOENT;
        for (; *candidates !is null; ++candidates)
        {
            pid_t pid;
            const failure = posix_spawn(&pid, *candidates, &actions, &attributes,
                    cast(char**) argv, cast(char**) envp);
            if (failure == 0)
                return Result!int(pid);
            if (failure == EACCES)
                lastError = EACCES;
            else if (failure != ENOENT && failure != ENOTDIR)
            {
                lastError = failure;
                break;
            }
        }
        return Result!int(-1, Error(nativeStatus(lastError), "could not start requested child"));
    }
}

// The parent keeps only the three reader descriptors.
// SAFETY: The child inherits privately owned native argv, environment, and cwd allocations via fork.
private Result!Child forkChild(ref Descriptors fds, const(char)* cwd, const(char)** candidates,
        const(char)** argv, const(char)** envp) @trusted nothrow @nogc
{
    const pid = fork();
    if (pid < 0)
    {
        const status = nativeStatus(errno);
        closeDescriptors(fds);
        return Result!Child(Child.init, Error(status, "could not fork child process"));
    }
    if (pid == 0)
        enterChild(fds, cwd, candidates, argv, envp);

    // Both ends attempt setpgid. The child must have set it before a successful exec.
    setpgid(pid, pid);
    closeFd(fds.stdoutPipe.writer);
    closeFd(fds.stderrPipe.writer);
    closeFd(fds.startup.writer);
    closeFd(fds.input);
    return Result!Child(Child(pid, fds.stdoutPipe.reader, fds.stderrPipe.reader, fds.startup.reader));
}

// Copy both the pointer table and every terminated string into one native-owned allocation.
private const(char)** copyVector(scope string[] strings) @system nothrow @nogc
{
    if (strings.length >= size_t.max / (const(char)*).sizeof)
        return null;
    const tableBytes = (strings.length + 1) * (const(char)*).sizeof;
    size_t bytes = tableBytes;
    foreach (value; strings)
    {
        if (value.length > size_t.max - bytes)
            return null;
        bytes += value.length;
    }

    auto memory = cast(ubyte*) malloc(bytes);
    if (memory is null)
        return null;
    auto table = cast(const(char)**) memory;
    auto cursor = memory + tableBytes;
    foreach (index, value; strings)
    {
        table[index] = cast(const(char)*) cursor;
        memcpy(cursor, value.ptr, value.length);
        cursor += value.length;
    }
    table[strings.length] = null;
    return table;
}

/// The group belongs to an unreaped child. Never signal the caller's group.
// SAFETY: The supervisor has exclusive wait ownership of the process identified by pid.
Error signalGroup(int pid, bool force) @trusted nothrow @nogc
{
    if (pid <= 1 || pid == getpgrp())
        return Error(Status.invalidArgument, "invalid owned process group");
    const signal = force ? SIGKILL : SIGTERM;
    if (kill(-pid, signal) == 0 || errno == ESRCH)
        return Error.init;
    version (OSX)
    {
        // Darwin reports EPERM, not ESRCH, for a group whose only members are zombies, such as
        // the exited but unreaped leader. Any live member it may signal would have succeeded.
        if (errno == EPERM)
        {
            const exited = childExited(pid);
            if (exited.ok && exited.value)
                return Error.init;
            errno = EPERM;
        }
    }
    return Error(nativeStatus(errno), "could not signal child process group");
}

version (OSX)
{
    // <sys/signal.h> siginfo_t is 104 bytes on Darwin; druntime's declaration has only 72, so
    // waitid would write past it. This layout matches the C structure.
    private struct DarwinSigInfo
    {
        int si_signo;
        int si_errno;
        int si_code;
        int si_pid;
        uint si_uid;
        int si_status;
        void* si_addr;
        void* si_value;
        long si_band;
        ulong[7] padding;
    }

    static assert(DarwinSigInfo.sizeof == 104);
    private extern (C) int waitid(idtype_t type, uint id, DarwinSigInfo* info, int options) @system nothrow @nogc;
}

// SAFETY: waitid borrows one local struct and observes only this child without releasing its PID.
Result!bool childExited(int pid) @trusted nothrow @nogc
{
    version (OSX)
        DarwinSigInfo info;
    else
        siginfo_t info;
    if (waitid(idtype_t.P_PID, pid, &info, WEXITED | WNOHANG | WNOWAIT) != 0)
    {
        if (errno == EINTR)
            return Result!bool(false);
        if (errno == ECHILD)
            return Result!bool(false, Error(Status.unavailable, "child wait ownership lost"));
        return Result!bool(false, Error(nativeStatus(errno), "could not observe child status"));
    }
    return Result!bool(info.si_pid != 0);
}

// SAFETY: Called only by the owner after the child's terminal state was observed or a forced kill.
Result!ExitStatus reap(int pid) @trusted nothrow @nogc
{
    int status;
    while (waitpid(pid, &status, 0) < 0)
    {
        if (errno == EINTR)
            continue;
        return Result!ExitStatus(ExitStatus.init, Error(nativeStatus(errno), "could not reap child process"));
    }
    if (WIFEXITED(status))
        return Result!ExitStatus(ExitStatus(WEXITSTATUS(status)));
    return Result!ExitStatus(ExitStatus(WTERMSIG(status), true));
}

// SAFETY: poll recognizes only the two owned reader descriptors and retains no output storage.
Result!uint waitForOutput(int first, int second, int milliseconds) @trusted nothrow @nogc
{
    pollfd[2] fds = [pollfd(first, POLLIN), pollfd(second, POLLIN)];
    const status = poll(fds.ptr, fds.length, milliseconds);
    if (status < 0)
        return errno == EINTR ? Result!uint(0) : Result!uint(0, Error(nativeStatus(errno),
                "could not monitor child pipes"));

    uint ready;
    foreach (index, ref fd; fds)
    {
        if (fd.revents & POLLNVAL)
            return Result!uint(0, Error(Status.ioError, "child pipe closed unexpectedly"));
        if (fd.revents != 0)
            ready |= 1U << index;
    }
    return Result!uint(ready);
}

version (OSX)
{
    import core.sys.darwin.sys.event : EVFILT_PROC, EVFILT_USER, EV_ADD, EV_CLEAR, NOTE_EXIT,
        NOTE_TRIGGER, kevent, kevent_t, kqueue;
    import core.sys.posix.time : timespec;

    // A kqueue descriptor is readable while it holds a pending event and is never inherited by a
    // child, so one kqueue stands in for Linux's pidfd and eventfd.
    // SAFETY: kevent reads one local change record and writes no event list.
    private int kqueueWith(ref kevent_t change) @trusted nothrow @nogc
    {
        const descriptor = kqueue();
        if (descriptor < 0)
            return -1;
        if (kevent(descriptor, &change, 1, null, 0, null) == 0)
            return descriptor;
        close(descriptor);
        return -1;
    }

    /// A descriptor that becomes readable when the unreaped child exits, or -1 when unavailable.
    int openExitNotifier(int pid) nothrow @nogc
    {
        auto change = kevent_t(cast(size_t) pid, EVFILT_PROC, EV_ADD, NOTE_EXIT);
        return pid > 0 ? kqueueWith(change) : -1;
    }

    /// A user event that wakes the supervisor's poll until drained, or -1 when unavailable.
    int openWake() nothrow @nogc
    {
        auto change = kevent_t(1, EVFILT_USER, EV_ADD | EV_CLEAR);
        return kqueueWith(change);
    }

    // SAFETY: kevent reads one local trigger record on the caller's live kqueue.
    void signalWake(int descriptor) @trusted nothrow @nogc
    {
        if (descriptor < 0)
            return;
        auto trigger = kevent_t(1, EVFILT_USER, 0, NOTE_TRIGGER);
        while (kevent(descriptor, &trigger, 1, null, 0, null) < 0 && errno == EINTR)
        {
        }
    }

    // SAFETY: kevent writes at most one local event record and never blocks with a zero timeout.
    void drainWake(int descriptor) @trusted nothrow @nogc
    {
        if (descriptor < 0)
            return;
        kevent_t event;
        timespec immediately;
        while (kevent(descriptor, null, 0, &event, 1, &immediately) < 0 && errno == EINTR)
        {
        }
    }
}
else
{
    private enum long pidfdOpenNumber = 434;

    /// A descriptor that becomes readable when the unreaped child exits, or -1 when the kernel lacks pidfd.
    // SAFETY: pidfd_open takes two integers and returns a new close-on-exec descriptor owned by the caller.
    int openExitNotifier(int pid) @trusted nothrow @nogc
    {
        const descriptor = syscall(pidfdOpenNumber, pid, 0U);
        return descriptor >= 0 && descriptor <= int.max ? cast(int) descriptor : -1;
    }

    /// A nonblocking counter that wakes the supervisor's poll, or -1 when unavailable.
    // SAFETY: eventfd takes only integers and returns a new descriptor owned by the caller.
    int openWake() @trusted nothrow @nogc
    {
        import core.sys.linux.sys.eventfd : EFD_CLOEXEC, EFD_NONBLOCK, eventfd;

        const descriptor = eventfd(0, EFD_CLOEXEC | EFD_NONBLOCK);
        return descriptor >= 0 ? descriptor : -1;
    }

    // SAFETY: write copies one local counter value into the caller's live eventfd and retains nothing.
    void signalWake(int descriptor) @trusted nothrow @nogc
    {
        if (descriptor < 0)
            return;
        const ulong one = 1;
        while (write(descriptor, &one, one.sizeof) < 0 && errno == EINTR)
        {
        }
    }

    // SAFETY: read writes one local counter value from the caller's live nonblocking eventfd.
    void drainWake(int descriptor) @trusted nothrow @nogc
    {
        if (descriptor < 0)
            return;
        ulong count;
        while (read(descriptor, &count, count.sizeof) < 0 && errno == EINTR)
        {
        }
    }
}

// SAFETY: read accesses only the bounded slice within this call and does not retain its pointer.
Result!size_t pull(int descriptor, scope ubyte[] buffer) @trusted nothrow @nogc
{
    const amount = read(descriptor, buffer.ptr, buffer.length);
    if (amount >= 0)
        return Result!size_t(cast(size_t) amount);
    const code = errno;
    if (code == EAGAIN || code == EINTR)
        return Result!size_t(0, Error(Status.unavailable, "child pipe is not ready"));
    return Result!size_t(0, Error(nativeStatus(code), "child pipe read failed"));
}

// SAFETY: The child writes either a single full integer before exiting or closes on successful exec.
Result!int setupResult(int descriptor) @trusted nothrow @nogc
{
    int code;
    const amount = read(descriptor, &code, code.sizeof);
    if (amount == 0 || amount == code.sizeof)
        return Result!int(code);
    if (amount < 0 && (errno == EAGAIN || errno == EINTR))
        return Result!int(0, Error(Status.unavailable, "child setup pending"));
    return Result!int(0, Error(Status.ioError, "invalid child setup receipt"));
}
