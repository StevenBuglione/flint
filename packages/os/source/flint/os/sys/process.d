module flint.os.sys.process;

import core.stdc.stdlib : free, malloc;
import core.stdc.string : memcpy;
import core.stdc.errno : EACCES, EAGAIN, ECHILD, EINVAL, EINTR, EMFILE, ENFILE, ENOENT, ENOMEM,
    ENOSYS, ENOTDIR, EPERM, ESRCH, errno;
import core.sys.linux.unistd : syscall;
import core.sys.posix.fcntl : F_GETFL, F_SETFL, O_CLOEXEC, O_NONBLOCK, O_RDONLY, fcntl, open;
import core.sys.posix.poll : POLLIN, POLLNVAL, poll, pollfd;
import core.sys.posix.signal : SA_NOCLDWAIT, SIGCHLD, SIGINT, SIGKILL, SIGPIPE, SIGTERM, SIG_DFL,
    SIG_IGN, SIG_SETMASK, kill, sigaction, sigaction_t, sigemptyset, siginfo_t, sigprocmask, sigset_t;
import core.sys.posix.sys.wait : idtype_t, WEXITED, WEXITSTATUS, WIFEXITED, WNOHANG, WNOWAIT,
    WTERMSIG, waitid, waitpid;
import core.sys.posix.unistd : _exit, chdir, close, dup2, execve, fork, getpgrp, pipe2, read, setpgid, write;
import flint.arena : Error, Result, Status;
import flint.os.types : ExitStatus;

@safe:

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

private enum int duplicateCloexec = 1030;
private enum long closeRangeNumber = 436;
private enum uint closeRangeCloexec = 4;

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

// SAFETY: pipe2 initializes both local slots before ownership transfer and both are closed on failure.
private Result!Pipe createPipe() @trusted nothrow @nogc
{
    int[2] fds;
    if (pipe2(fds, O_CLOEXEC) < 0)
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
    if (syscall(closeRangeNumber, 3U, uint.max, closeRangeCloexec) != 0)
        reportFailure(fds.startup.writer, errno);

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

// SAFETY: The child inherits privately owned native argv, environment, and cwd allocations via fork.
// The parent releases only its own copy and keeps only the three reader descriptors.
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
    return Error(nativeStatus(errno), "could not signal child process group");
}

// SAFETY: waitid borrows one local struct and observes only this child without releasing its PID.
Result!bool childExited(int pid) @trusted nothrow @nogc
{
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
