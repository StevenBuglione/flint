/// Windows child processes behind the descriptor-shaped interface of flint.os.sys.process.
///
/// The supervisor and the output pump wait on small integer descriptors. Here each descriptor names a slot in a
/// process-wide table: an overlapped named-pipe reader with its own buffer, a child process handle, or a
/// manual-reset event. A pipe reader keeps one read outstanding; `waitForOutput` waits on its event and `pull`
/// hands out the bytes that read delivered. A child runs in its own job object, the Windows counterpart of the
/// owned process group, and in its own console process group, which receives CTRL_BREAK as the graceful stop.
module flint.os.sys.windows_process;

@safe:

version (Windows)
{
    import core.atomic : atomicOp, atomicStore, cas;
    import core.stdc.stdlib : free, malloc;
    import core.sys.windows.basetsd : SIZE_T;
    import core.sys.windows.winbase : CloseHandle, CreateEventW, CreateFileW, CreateNamedPipeW,
        CreateProcessW, DuplicateHandle, FILE_FLAG_FIRST_PIPE_INSTANCE,
        FILE_FLAG_OVERLAPPED, GetCurrentProcess,
        GetCurrentProcessId, GetExitCodeProcess, GetLastError, GetOverlappedResult, INFINITE,
        INVALID_HANDLE_VALUE, OPEN_EXISTING, OVERLAPPED, PIPE_ACCESS_INBOUND,
        PIPE_READMODE_BYTE, PIPE_TYPE_BYTE,
        PIPE_WAIT, PROCESS_INFORMATION, ReadFile, ResetEvent, ResumeThread, STARTF_USESTDHANDLES, STARTUPINFOW,
        SetEvent, Sleep, TerminateProcess, WAIT_OBJECT_0, WaitForMultipleObjects, WaitForSingleObject;
    import core.sys.windows.windef : BOOL, DWORD, HANDLE;
    import core.sys.windows.winerror : ERROR_ACCESS_DENIED, ERROR_BAD_PATHNAME, ERROR_BROKEN_PIPE,
        ERROR_DIRECTORY, ERROR_FILE_NOT_FOUND, ERROR_HANDLE_EOF,
        ERROR_INVALID_NAME,
        ERROR_INVALID_PARAMETER, ERROR_IO_INCOMPLETE,
        ERROR_IO_PENDING, ERROR_NOT_ENOUGH_MEMORY, ERROR_NOT_SUPPORTED, ERROR_OUTOFMEMORY,
        ERROR_PATH_NOT_FOUND, ERROR_TOO_MANY_OPEN_FILES;
    import core.sys.windows.winnt : SECURITY_ATTRIBUTES, DUPLICATE_SAME_ACCESS,
        FILE_ATTRIBUTE_NORMAL, FILE_SHARE_READ, FILE_SHARE_WRITE, GENERIC_READ, GENERIC_WRITE;
    import flint.arena : Error, Result, Status;
    import flint.os.types : ExitStatus;

    pragma(lib, "kernel32");

    private enum DWORD createSuspended = 0x0000_0004;
    private enum DWORD createNewProcessGroup = 0x0000_0200;
    private enum DWORD createUnicodeEnvironment = 0x0000_0400;
    private enum DWORD createNoWindow = 0x0800_0000;
    private enum DWORD extendedStartupInfoPresent = 0x0008_0000;
    private enum size_t handleListAttribute = 0x0002_0002; // PROC_THREAD_ATTRIBUTE_HANDLE_LIST
    private enum DWORD pipeRejectRemoteClients = 0x0000_0008;
    private enum DWORD ctrlBreakEvent = 1;
    private enum DWORD statusControlCExit = 0xC000_013A;
    private enum DWORD killedExitCode = 0x0000_0009;
    private enum int sigkill = 9;
    private enum int sigterm = 15;

    // Job object limits: kill every member when the last job handle closes, and let a deliberate daemon
    // started with CREATE_BREAKAWAY_FROM_JOB leave, as setsid leaves a POSIX process group.
    private enum DWORD jobKillOnClose = 0x0000_2000;
    private enum DWORD jobBreakawayOk = 0x0000_0800;
    private enum int jobExtendedLimitInformation = 9;

    private struct JobBasicLimits
    {
        long perProcessUserTimeLimit;
        long perJobUserTimeLimit;
        DWORD limitFlags;
        SIZE_T minimumWorkingSetSize;
        SIZE_T maximumWorkingSetSize;
        DWORD activeProcessLimit;
        size_t affinity;
        DWORD priorityClass;
        DWORD schedulingClass;
    }

    private struct IoCounters
    {
        ulong[6] values;
    }

    private struct JobExtendedLimits
    {
        JobBasicLimits basic;
        IoCounters io;
        SIZE_T processMemoryLimit;
        SIZE_T jobMemoryLimit;
        SIZE_T peakProcessMemoryUsed;
        SIZE_T peakJobMemoryUsed;
    }

    private struct StartupInfoEx
    {
        STARTUPINFOW startup;
        void* attributes;
    }

    private extern (Windows) @system nothrow @nogc
    {
        HANDLE CreateJobObjectW(void* attributes, const(wchar)* name);
        BOOL SetInformationJobObject(HANDLE job, int informationClass, void* information, DWORD length);
        BOOL AssignProcessToJobObject(HANDLE job, HANDLE process);
        BOOL TerminateJobObject(HANDLE job, uint exitCode);
        BOOL InitializeProcThreadAttributeList(void* list, DWORD count, DWORD flags, SIZE_T* size);
        BOOL UpdateProcThreadAttribute(void* list, DWORD flags, size_t attribute, void* value,
                SIZE_T size, void* previous, SIZE_T* returned);
        void DeleteProcThreadAttributeList(void* list);
        BOOL GenerateConsoleCtrlEvent(DWORD event, DWORD processGroup);
        BOOL CancelIoEx(HANDLE file, OVERLAPPED* overlapped);
        uint GetConsoleCP();
    }

package(flint.os):

    /// A launched child: its process id and the descriptors of its two output readers. Windows reports a
    /// failed start from CreateProcessW itself, so there is no startup receipt descriptor.
    struct Child
    {
        int pid;
        int stdoutFd = -1;
        int stderrFd = -1;
        int startupFd = -1;
    }

    private enum SlotKind : ubyte
    {
        free,
        pipe,
        process,
        event
    }

    private enum size_t slotCount = 512;
    private enum int firstDescriptor = 3;
    private enum uint readBytes = 16_384;

    private struct Slot
    {
        SlotKind kind;
        HANDLE handle;
        // Pipe readers only: the overlapped read, its event and buffer, and what the last read delivered.
        OVERLAPPED overlapped;
        ubyte* buffer;
        uint delivered;
        uint taken;
        bool pending;
        bool ended;
    }

    private struct Owned
    {
        int pid;
        HANDLE process;
        HANDLE job;
        bool killed;
    }

    private enum size_t childCount = 256;

    // The table is static so that every OVERLAPPED keeps its address while the kernel may write it.
    private __gshared Slot[slotCount] slots;
    private __gshared Owned[childCount] children;
    private shared bool tableLock;
    private shared uint pipeSerial;

    // SAFETY: Spins on one shared flag; Sleep(0) only yields the calling thread.
    private void lockTable() @trusted nothrow @nogc
    {
        while (!cas(&tableLock, false, true))
            Sleep(0);
    }

    private void unlockTable() nothrow @nogc
    {
        atomicStore(tableLock, false);
    }

    Status nativeStatus(int code) pure nothrow @nogc
    {
        switch (code)
        {
        case ERROR_FILE_NOT_FOUND:
        case ERROR_PATH_NOT_FOUND:
        case ERROR_DIRECTORY:
        case ERROR_INVALID_NAME:
        case ERROR_BAD_PATHNAME:
            return Status.notFound;
        case ERROR_ACCESS_DENIED:
            return Status.permissionDenied;
        case ERROR_NOT_ENOUGH_MEMORY:
        case ERROR_OUTOFMEMORY:
            return Status.outOfMemory;
        case ERROR_TOO_MANY_OPEN_FILES:
        case 1450: // ERROR_NO_SYSTEM_RESOURCES
            return Status.resourceExhausted;
        case ERROR_INVALID_PARAMETER:
            return Status.invalidArgument;
        case ERROR_NOT_SUPPORTED:
            return Status.unsupported;
        default:
            return Status.ioError;
        }
    }

    // SAFETY: Slot storage is static; the lock admits one claimant, and the returned slot is owned by the caller
    // until closeFd releases it.
    private int claim(SlotKind kind, HANDLE handle) @trusted nothrow @nogc
    {
        lockTable();
        scope (exit)
            unlockTable();
        foreach (index, ref slot; slots)
        {
            if (slot.kind != SlotKind.free)
                continue;
            slot = Slot.init;
            slot.kind = kind;
            slot.handle = handle;
            return cast(int) index + firstDescriptor;
        }
        return -1;
    }

    // SAFETY: Only descriptors returned by claim index the static table; anything else yields null.
    private Slot* slotOf(int descriptor) @trusted nothrow @nogc
    {
        if (descriptor < firstDescriptor || descriptor >= firstDescriptor + cast(int) slotCount)
            return null;
        auto slot = &slots[descriptor - firstDescriptor];
        return slot.kind == SlotKind.free ? null : slot;
    }

    // SAFETY: The owner releases its slot once. An outstanding read is cancelled and its final completion is
    // observed before the buffer and OVERLAPPED are released, so the kernel never writes freed memory.
    void closeFd(ref int descriptor) @trusted nothrow @nogc
    {
        auto slot = slotOf(descriptor);
        descriptor = -1;
        if (slot is null)
            return;
        if (slot.kind == SlotKind.pipe)
        {
            if (slot.pending)
            {
                DWORD ignored;
                CancelIoEx(slot.handle, &slot.overlapped);
                GetOverlappedResult(slot.handle, &slot.overlapped, &ignored, 1);
            }
            CloseHandle(slot.overlapped.hEvent);
            free(slot.buffer);
        }
        CloseHandle(slot.handle);
        lockTable();
        *slot = Slot.init;
        unlockTable();
    }

    void closeChildPipes(ref Child child) nothrow @nogc
    {
        closeFd(child.stdoutFd);
        closeFd(child.stderrFd);
        closeFd(child.startupFd);
    }

    /// Windows has no child wait disposition that could steal a child's exit status.
    Error validateWaitPolicy() nothrow @nogc
    {
        return Error.init;
    }

    // Post the slot's next overlapped read unless one is outstanding or delivered bytes remain.
    // SAFETY: The read writes only the slot's own buffer through its static OVERLAPPED, both retained until
    // closeFd observes the final completion.
    private void postRead(Slot* slot) @trusted nothrow @nogc
    {
        if (slot.pending || slot.ended || slot.taken < slot.delivered)
            return;
        slot.delivered = slot.taken = 0;
        ResetEvent(slot.overlapped.hEvent);
        DWORD count;
        if (ReadFile(slot.handle, slot.buffer, readBytes, &count, &slot.overlapped))
        {
            // Completed at once; the event is also set, and GetOverlappedResult reports the same count.
            slot.pending = true;
            return;
        }
        // Pending, or ended: a broken pipe is end of output, and any other failure ends it too.
        if (GetLastError() == ERROR_IO_PENDING)
            slot.pending = true;
        else
            slot.ended = true;
    }

    // Collect a finished read without waiting. Returns false while the read is still outstanding.
    // SAFETY: GetOverlappedResult reads the slot's own OVERLAPPED and writes only the local count.
    private bool collect(Slot* slot) @trusted nothrow @nogc
    {
        if (!slot.pending)
            return true;
        DWORD count;
        if (!GetOverlappedResult(slot.handle, &slot.overlapped, &count, 0))
        {
            const code = GetLastError();
            if (code == ERROR_IO_INCOMPLETE)
                return false;
            slot.pending = false;
            slot.ended = true; // A broken pipe is end of output; any other failure ends it too.
            return true;
        }
        slot.pending = false;
        slot.delivered = count;
        slot.taken = 0;
        return true;
    }

    private bool readable(Slot* slot) nothrow @nogc
    {
        postRead(slot);
        return collect(slot) && (slot.ended || slot.taken < slot.delivered);
    }

    /// Wait at most `milliseconds` until either descriptor is ready; bit 0 reports `first` and bit 1 `second`.
    /// A pipe is ready with bytes or at end of output, a process once it exited, an event while it is set.
    // SAFETY: Only live slot handles are passed to the wait, which retains none of them.
    Result!uint waitForOutput(int first, int second, int milliseconds) @trusted nothrow @nogc
    {
        HANDLE[2] handles;
        uint[2] bits;
        DWORD count;
        uint ready;
        const int[2] descriptors = [first, second];
        foreach (index, descriptor; descriptors)
        {
            if (descriptor < 0)
                continue;
            auto slot = slotOf(descriptor);
            if (slot is null)
                return Result!uint(0, Error(Status.ioError, "child pipe closed unexpectedly"));
            if (slot.kind == SlotKind.pipe)
            {
                if (readable(slot))
                {
                    ready |= 1U << index;
                    continue;
                }
                handles[count] = slot.overlapped.hEvent;
            }
            else
                handles[count] = slot.handle;
            bits[count++] = 1U << index;
        }
        if (ready != 0)
            return Result!uint(ready);
        if (count == 0)
        {
            Sleep(milliseconds < 0 ? INFINITE : milliseconds);
            return Result!uint(0);
        }
        const status = WaitForMultipleObjects(count, handles.ptr, 0, milliseconds < 0 ? INFINITE : milliseconds);
        if (status == 0xFFFF_FFFF) // WAIT_FAILED
            return Result!uint(0, Error(nativeStatus(GetLastError()), "could not monitor child pipes"));
        foreach (index; 0 .. count)
            if (WaitForSingleObject(handles[index], 0) == WAIT_OBJECT_0)
                ready |= bits[index];
        return Result!uint(ready);
    }

    /// Copy delivered bytes; 0 at end of output, or `unavailable` while the read is outstanding.
    // SAFETY: Copies at most buffer.length bytes from the slot's delivered window into the caller's slice.
    Result!size_t pull(int descriptor, scope ubyte[] buffer) @trusted nothrow @nogc
    {
        auto slot = slotOf(descriptor);
        if (slot is null || slot.kind != SlotKind.pipe)
            return Result!size_t(0, Error(Status.ioError, "child pipe read failed"));
        if (!readable(slot))
            return Result!size_t(0, Error(Status.unavailable, "child pipe is not ready"));
        if (slot.taken == slot.delivered)
            return slot.ended ? Result!size_t(0) : Result!size_t(0, Error(Status.unavailable,
                    "child pipe is not ready"));
        const available = slot.delivered - slot.taken;
        const count = available < buffer.length ? available : buffer.length;
        buffer[0 .. count] = slot.buffer[slot.taken .. slot.taken + count];
        slot.taken += cast(uint) count;
        return Result!size_t(count);
    }

    /// Never called: Windows reports a failed start synchronously, so `Child.startupFd` stays -1.
    Result!int setupResult(int) nothrow @nogc
    {
        return Result!int(0);
    }

    /// A manual-reset event that wakes the supervisor's wait, or -1 when unavailable.
    // SAFETY: CreateEventW returns a new handle owned by the claimed slot.
    int openWake() @trusted nothrow @nogc
    {
        auto event = CreateEventW(null, 1, 0, null);
        if (event is null)
            return -1;
        const descriptor = claim(SlotKind.event, event);
        if (descriptor < 0)
            CloseHandle(event);
        return descriptor;
    }

    // SAFETY: SetEvent only signals the slot's live event.
    void signalWake(int descriptor) @trusted nothrow @nogc
    {
        if (auto slot = slotOf(descriptor))
            SetEvent(slot.handle);
    }

    // SAFETY: ResetEvent only clears the slot's live event.
    void drainWake(int descriptor) @trusted nothrow @nogc
    {
        if (auto slot = slotOf(descriptor))
            ResetEvent(slot.handle);
    }

    /// Consume one wake: whether the event was set, clearing it.
    // SAFETY: Waits zero milliseconds on the slot's live event and clears it.
    bool takeWake(int descriptor) @trusted nothrow @nogc
    {
        auto slot = slotOf(descriptor);
        if (slot is null || WaitForSingleObject(slot.handle, 0) != WAIT_OBJECT_0)
            return false;
        ResetEvent(slot.handle);
        return true;
    }

    /// The raw event handle of a wake descriptor, for a console control handler that must not take locks.
    // SAFETY: Reads the handle of a live slot owned by the caller.
    void* wakeHandle(int descriptor) @trusted nothrow @nogc
    {
        auto slot = slotOf(descriptor);
        return slot is null ? null : slot.handle;
    }

    // SAFETY: The child table is static and guarded by the table lock; the returned record stays owned by the
    // supervising caller until reap clears it.
    private Owned* ownedChild(int pid) @trusted nothrow @nogc
    {
        lockTable();
        scope (exit)
            unlockTable();
        foreach (ref child; children)
            if (child.process !is null && child.pid == pid)
                return &child;
        return null;
    }

    /// A descriptor that becomes ready when the child exits, or -1.
    // SAFETY: The duplicate process handle is owned by the claimed slot and closed by closeFd.
    int openExitNotifier(int pid) @trusted nothrow @nogc
    {
        auto child = ownedChild(pid);
        if (child is null)
            return -1;
        HANDLE copy;
        if (!DuplicateHandle(GetCurrentProcess(), child.process, GetCurrentProcess(), &copy, 0,
                0, DUPLICATE_SAME_ACCESS))
            return -1;
        const descriptor = claim(SlotKind.process, copy);
        if (descriptor < 0)
            CloseHandle(copy);
        return descriptor;
    }

    // SAFETY: Waits zero milliseconds on the supervised child's own process handle.
    Result!bool childExited(int pid) @trusted nothrow @nogc
    {
        auto child = ownedChild(pid);
        if (child is null)
            return Result!bool(false, Error(Status.unavailable, "child wait ownership lost"));
        return Result!bool(WaitForSingleObject(child.process, 0) == WAIT_OBJECT_0);
    }

    /// Stop the child's job: CTRL_BREAK to its console process group, or terminate every member when forced.
    // SAFETY: Acts only on the supervised child's own job and console group.
    Error signalGroup(int pid, bool force) @trusted nothrow @nogc
    {
        auto child = ownedChild(pid);
        if (child is null || pid <= 0)
            return Error(Status.invalidArgument, "invalid owned process group");
        if (!force)
        {
            // Without a shared console the event cannot be delivered; the grace period then ends in termination.
            GenerateConsoleCtrlEvent(ctrlBreakEvent, cast(DWORD) pid);
            return Error.init;
        }
        if (WaitForSingleObject(child.process, 0) != WAIT_OBJECT_0)
            child.killed = true;
        if (TerminateJobObject(child.job, killedExitCode))
            return Error.init;
        const code = GetLastError();
        if (TerminateProcess(child.process, killedExitCode) || WaitForSingleObject(child.process, 0) == WAIT_OBJECT_0)
            return Error.init;
        return Error(nativeStatus(code), "could not signal child process group");
    }

    /// Wait for the child, release its handles and job, and report how it ended. A child that was still
    /// running when its job was terminated reports SIGKILL; one ended by the CTRL_BREAK stop reports SIGTERM.
    // SAFETY: Called only by the owner after the child exited or was terminated; the record is cleared once.
    Result!ExitStatus reap(int pid) @trusted nothrow @nogc
    {
        auto child = ownedChild(pid);
        if (child is null)
            return Result!ExitStatus(ExitStatus.init, Error(Status.unavailable, "child wait ownership lost"));
        WaitForSingleObject(child.process, INFINITE);
        DWORD code;
        const known = GetExitCodeProcess(child.process, &code);
        const lastError = GetLastError();
        const killed = child.killed;
        // Closing the last job handle also ends any member that outlived the leader.
        CloseHandle(child.job);
        CloseHandle(child.process);
        lockTable();
        *child = Owned.init;
        unlockTable();
        if (!known)
            return Result!ExitStatus(ExitStatus.init, Error(nativeStatus(lastError), "could not reap child process"));
        if (killed)
            return Result!ExitStatus(ExitStatus(sigkill, true));
        if (code == statusControlCExit)
            return Result!ExitStatus(ExitStatus(sigterm, true));
        return Result!ExitStatus(ExitStatus(cast(int) code));
    }

    // One output pipe: an overlapped inbound server end for the parent and an inheritable client end for the
    // child. Both are owned by the caller.
    // SAFETY: The pipe name is a local NUL-terminated UTF-16 buffer; the security attributes are local.
    private bool createPipe(out HANDLE reader, out HANDLE writer) @trusted nothrow @nogc
    {
        wchar[64] name = 0;
        const prefix = `\\.\pipe\flint-os-`w;
        name[0 .. prefix.length] = prefix[];
        size_t at = prefix.length;
        at = appendNumber(name, at, GetCurrentProcessId());
        name[at++] = '-';
        at = appendNumber(name, at, atomicOp!"+="(pipeSerial, 1));
        reader = CreateNamedPipeW(name.ptr, PIPE_ACCESS_INBOUND | FILE_FLAG_OVERLAPPED | FILE_FLAG_FIRST_PIPE_INSTANCE,
                PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT | pipeRejectRemoteClients, 1, 0, 65_536, 0, null);
        if (reader == INVALID_HANDLE_VALUE)
        {
            reader = null;
            return false;
        }
        auto inherit = SECURITY_ATTRIBUTES(SECURITY_ATTRIBUTES.sizeof, null, 1);
        writer = CreateFileW(name.ptr, GENERIC_WRITE, 0, &inherit, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, null);
        if (writer == INVALID_HANDLE_VALUE)
        {
            CloseHandle(reader);
            reader = writer = null;
            return false;
        }
        return true;
    }

    private size_t appendNumber(ref wchar[64] text, size_t at, uint value) pure nothrow @nogc
    {
        wchar[10] digits;
        size_t count;
        do
        {
            digits[count++] = cast(wchar)('0' + value % 10);
            value /= 10;
        }
        while (value != 0);
        foreach_reverse (digit; digits[0 .. count])
            text[at++] = digit;
        return at;
    }

    // Claim a reader slot for a pipe server end, with its event and read buffer. Closes the handle on failure.
    // SAFETY: The event and buffer become owned by the slot, which closeFd releases.
    private int adoptReader(HANDLE reader) @trusted nothrow @nogc
    {
        auto event = CreateEventW(null, 1, 0, null);
        auto buffer = cast(ubyte*) malloc(readBytes);
        const descriptor = event is null || buffer is null ? -1 : claim(SlotKind.pipe, reader);
        if (descriptor < 0)
        {
            if (event !is null)
                CloseHandle(event);
            free(buffer);
            CloseHandle(reader);
            return -1;
        }
        auto slot = slotOf(descriptor);
        slot.overlapped.hEvent = event;
        slot.buffer = buffer;
        return descriptor;
    }

    /// Quote one argument for the command line the Microsoft C runtime splits back into argv.
    private void quoteArgument(ref string line, string argument) pure nothrow
    {
        if (line.length != 0)
            line ~= ' ';
        bool plain = argument.length != 0;
        foreach (character; argument)
            if (character == ' ' || character == '\t' || character == '\n' || character == '\v' || character == '"')
                plain = false;
        if (plain)
        {
            line ~= argument;
            return;
        }
        line ~= '"';
        size_t backslashes;
        foreach (character; argument)
        {
            if (character == '\\')
            {
                ++backslashes;
                continue;
            }
            foreach (_; 0 .. character == '"' ? backslashes * 2 + 1 : backslashes)
                line ~= '\\';
            backslashes = 0;
            line ~= character;
        }
        foreach (_; 0 .. backslashes * 2)
            line ~= '\\';
        line ~= '"';
    }

    private string withoutTerminator(string value) pure nothrow @nogc
    {
        return value.length != 0 && value[$ - 1] == '\0' ? value[0 .. $ - 1] : value;
    }

    private bool absolutePath(string path) pure nothrow @nogc
    {
        return (path.length >= 3 && path[1] == ':' && (path[2] == '\\' || path[2] == '/'))
            || (path.length >= 2 && (path[0] == '\\' || path[0] == '/') && (path[1] == '\\' || path[1] == '/'));
    }

    private bool hasExtension(string path) pure nothrow @nogc
    {
        foreach_reverse (character; path)
        {
            if (character == '.')
                return true;
            if (character == '\\' || character == '/')
                return false;
        }
        return false;
    }

    // UTF-16 copy with a terminator, or null when the text is not valid UTF-8.
    private wchar[] wide(string text) nothrow
    {
        import std.utf : toUTF16;

        try
            return (toUTF16(text) ~ '\0').dup;
        catch (Exception)
            return null;
    }

    private struct Launched
    {
        HANDLE process;
        HANDLE thread;
        DWORD pid;
        DWORD failure;
    }

    // Start one candidate suspended with exactly the three standard handles inherited.
    // SAFETY: Every pointer refers to a local NUL-terminated UTF-16 buffer or local structure that outlives the
    // call; the attribute list is initialized, used and deleted within this frame.
    @trusted private Launched start(wchar[] application, wchar[] commandLine,
            wchar[] environmentBlock, wchar[] directory, HANDLE input, HANDLE output, HANDLE errors) nothrow
    {
        Launched launched;
        HANDLE[3] inherited = [input, output, errors];
        SIZE_T size;
        InitializeProcThreadAttributeList(null, 1, 0, &size);
        auto list = malloc(size);
        if (list is null)
        {
            launched.failure = ERROR_NOT_ENOUGH_MEMORY;
            return launched;
        }
        scope (exit)
            free(list);
        if (!InitializeProcThreadAttributeList(list, 1, 0, &size))
        {
            launched.failure = GetLastError();
            return launched;
        }
        scope (exit)
            DeleteProcThreadAttributeList(list);
        if (!UpdateProcThreadAttribute(list, 0, handleListAttribute, inherited.ptr, inherited.sizeof, null, null))
        {
            launched.failure = GetLastError();
            return launched;
        }
        StartupInfoEx info;
        info.startup.cb = StartupInfoEx.sizeof;
        info.startup.dwFlags = STARTF_USESTDHANDLES;
        info.startup.hStdInput = input;
        info.startup.hStdOutput = output;
        info.startup.hStdError = errors;
        info.attributes = list;
        DWORD flags = createSuspended | createNewProcessGroup | createUnicodeEnvironment | extendedStartupInfoPresent;
        if (GetConsoleCP() == 0)
            flags |= createNoWindow; // No console to share: do not open one for the child.
        PROCESS_INFORMATION process;
        if (!CreateProcessW(application.ptr, commandLine.ptr, null, null, 1, flags,
                environmentBlock.ptr, directory.length > 1 ? directory.ptr : null, &info.startup, &process))
        {
            launched.failure = GetLastError();
            return launched;
        }
        launched.process = process.hProcess;
        launched.thread = process.hThread;
        launched.pid = process.dwProcessId;
        return launched;
    }

    // The three standard handles a child inherits: NUL input and the client ends of two output pipes.
    private struct Handles
    {
        HANDLE input;
        HANDLE outWriter;
        HANDLE errWriter;
    }

    /// Start argv[0] from the first candidate path that names an executable, in `directory`, with `env`, its
    /// output connected to two new pipe readers and its input to NUL. A candidate without an extension is also
    /// tried with `.exe` and `.com`; batch files are not executed.
    Result!Child launch(scope string[] paths, scope string[] args, scope string[] env, string directory)
    {
        string line;
        foreach (argument; args)
            quoteArgument(line, withoutTerminator(argument));
        auto commandLine = wide(line);
        wchar[] environmentBlock;
        foreach (entry; env)
            environmentBlock ~= wide(withoutTerminator(entry));
        environmentBlock ~= '\0';
        const cwd = withoutTerminator(directory);
        auto workingDirectory = wide(cwd);
        if (commandLine is null || workingDirectory is null || commandLine.length > 32_767)
            return Result!Child(Child.init, Error(Status.invalidArgument, "invalid or excessive argv"));

        Handles handles;
        Child child;
        auto opened = openStandardHandles(handles, child);
        scope (exit)
            closeHandles(handles);
        if (opened.code != Status.ok)
            return Result!Child(Child.init, opened);
        DWORD code;
        auto job = createJob(code);
        if (job is null)
        {
            closeChildPipes(child);
            return Result!Child(Child.init, Error(nativeStatus(code), "could not create child job"));
        }

        auto launched = startFirst(paths, cwd, commandLine, environmentBlock, workingDirectory, handles);
        if (launched.process is null)
        {
            closeHandle(job);
            closeChildPipes(child);
            return Result!Child(Child.init, Error(nativeStatus(launched.failure), "could not start requested child"));
        }
        const adopted = adopt(launched, job, child);
        if (adopted.code != Status.ok)
        {
            closeChildPipes(child);
            return Result!Child(Child.init, adopted);
        }
        return Result!Child(child);
    }

    // Try each candidate path, and each executable suffix for one without an extension, until one starts. Like
    // execvp, a candidate that is missing or denied moves on, and a denial is reported only if nothing started.
    private Launched startFirst(scope string[] paths, string cwd, wchar[] commandLine,
            wchar[] environmentBlock, wchar[] workingDirectory, ref const Handles handles)
    {
        Launched launched;
        launched.failure = ERROR_FILE_NOT_FOUND;
        bool denied;
        foreach (candidate; paths)
        {
            string path = withoutTerminator(candidate);
            if (cwd.length != 0 && !absolutePath(path))
                path = cwd ~ (cwd[$ - 1] == '\\' || cwd[$ - 1] == '/' ? "" : "\\") ~ path;
            foreach (suffix; hasExtension(path) ? [""] : ["", ".exe", ".com"])
            {
                auto application = wide(path ~ suffix);
                if (application is null)
                    continue;
                launched = start(application, commandLine.dup, environmentBlock, workingDirectory,
                        cast(HANDLE) handles.input, cast(HANDLE) handles.outWriter, cast(HANDLE) handles.errWriter);
                if (launched.process !is null)
                    return launched;
                denied = denied || launched.failure == ERROR_ACCESS_DENIED;
                if (!missing(launched.failure) && launched.failure != ERROR_ACCESS_DENIED)
                    return launched;
            }
        }
        if (denied && missing(launched.failure))
            launched.failure = ERROR_ACCESS_DENIED;
        return launched;
    }

    // A candidate that does not exist, so the next one is tried.
    private bool missing(DWORD failure) pure nothrow @nogc
    {
        return failure == ERROR_FILE_NOT_FOUND || failure == ERROR_PATH_NOT_FOUND
            || failure == ERROR_INVALID_NAME || failure == ERROR_BAD_PATHNAME;
    }

    // Open NUL as inheritable input and create both output pipes, claiming their reader slots in `child`.
    // SAFETY: Every handle created here is owned by `handles` (closed by closeHandles) or by a claimed slot.
    private Error openStandardHandles(ref Handles handles, ref Child child) @trusted nothrow
    {
        auto inherit = SECURITY_ATTRIBUTES(SECURITY_ATTRIBUTES.sizeof, null, 1);
        auto input = CreateFileW("NUL"w.ptr, GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE,
                &inherit, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, null);
        if (input == INVALID_HANDLE_VALUE)
            return Error(nativeStatus(GetLastError()), "could not open child input");
        handles.input = input;
        HANDLE outReader, errReader;
        if (!createPipe(outReader, handles.outWriter))
            return Error(nativeStatus(GetLastError()), "could not create child pipe");
        if (!createPipe(errReader, handles.errWriter))
        {
            CloseHandle(outReader);
            return Error(nativeStatus(GetLastError()), "could not create child pipe");
        }
        child.stdoutFd = adoptReader(outReader);
        child.stderrFd = adoptReader(errReader);
        if (child.stdoutFd >= 0 && child.stderrFd >= 0)
            return Error.init;
        closeChildPipes(child);
        return Error(Status.resourceExhausted, "could not create child pipe");
    }

    // SAFETY: Closes only the handles this launch opened; the child holds its own inherited copies.
    private void closeHandles(ref Handles handles) @trusted nothrow @nogc
    {
        foreach (handle; [handles.input, handles.outWriter, handles.errWriter])
            if (handle !is null)
                CloseHandle(handle);
        handles = Handles.init;
    }

    // SAFETY: Closes one handle owned by the caller.
    private void closeHandle(HANDLE handle) @trusted nothrow @nogc
    {
        if (handle !is null)
            CloseHandle(handle);
    }

    // A job that kills its members when its last handle closes and lets deliberate daemons break away.
    // SAFETY: The limits structure is local and sized for the information class; the job handle is the caller's.
    private HANDLE createJob(out DWORD code) @trusted nothrow @nogc
    {
        auto job = CreateJobObjectW(null, null);
        JobExtendedLimits limits;
        limits.basic.limitFlags = jobKillOnClose | jobBreakawayOk;
        if (job !is null && SetInformationJobObject(job, jobExtendedLimitInformation, &limits, limits.sizeof))
            return job;
        code = GetLastError();
        if (job !is null)
            CloseHandle(job);
        return null;
    }

    // Put the suspended child into its job, resume it and record it. On failure the child is ended and every
    // handle released.
    // SAFETY: The process, thread and job handles are owned by this call until the child table takes the first
    // and last; the thread handle is always closed.
    private Error adopt(ref Launched launched, HANDLE job, ref Child child) @trusted nothrow @nogc
    {
        if (!AssignProcessToJobObject(job, launched.process) || ResumeThread(launched.thread) == 0xFFFF_FFFF)
        {
            const code = GetLastError();
            TerminateProcess(launched.process, killedExitCode);
            WaitForSingleObject(launched.process, INFINITE);
            CloseHandle(launched.thread);
            CloseHandle(launched.process);
            CloseHandle(job);
            return Error(nativeStatus(code), "could not start requested child");
        }
        CloseHandle(launched.thread);
        child.pid = cast(int) launched.pid;
        if (record(Owned(child.pid, launched.process, job)))
            return Error.init;
        TerminateJobObject(job, killedExitCode);
        WaitForSingleObject(launched.process, INFINITE);
        CloseHandle(launched.process);
        CloseHandle(job);
        return Error(Status.resourceExhausted, "too many supervised children");
    }

    // SAFETY: The static child table is written only under the table lock.
    private bool record(Owned owned) @trusted nothrow @nogc
    {
        lockTable();
        scope (exit)
            unlockTable();
        foreach (ref child; children)
        {
            if (child.process !is null)
                continue;
            child = owned;
            return true;
        }
        return false;
    }
}
