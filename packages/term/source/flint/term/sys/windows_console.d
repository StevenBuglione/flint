/// The Windows console behind the terminal ABI that native/linux.c implements on Linux.
///
/// The session logic in flint.term.sys.linux_session is shared: it sees the same statuses and the same byte
/// stream. Console input runs in virtual-terminal mode, so keys arrive as the VT sequences the shared decoder
/// already parses; records are converted from UTF-16 to UTF-8 here. A window-size record reports a resize, the
/// counterpart of SIGWINCH, and Ctrl+C outside raw mode reports an interrupt through a console control handler,
/// the counterpart of SIGINT. Raw mode turns off line input, echo and Ctrl+C processing, as cfmakeraw does.
/// Output switches the console to virtual-terminal processing and the UTF-8 code page for the session's lifetime
/// and restores both on close.
module flint.term.sys.windows_console;

@system:

version (Windows)
{
    import core.stdc.stdlib : calloc, free;
    import core.sys.windows.windef : BOOL, DWORD, HANDLE, WORD;
    import core.sys.windows.wincon : CONSOLE_SCREEN_BUFFER_INFO, GetConsoleMode, GetConsoleScreenBufferInfo,
        INPUT_RECORD, KEY_EVENT, ReadConsoleInputW, SetConsoleMode, WINDOW_BUFFER_SIZE_EVENT;
    import core.sys.windows.winbase : CloseHandle, CreateEventW, DuplicateHandle, GetCurrentProcess,
        GetFileType, GetStdHandle,
        INFINITE, INVALID_HANDLE_VALUE, PeekNamedPipe, ReadFile, STD_INPUT_HANDLE,
        STD_OUTPUT_HANDLE, SetEvent, Sleep, WAIT_OBJECT_0, WaitForMultipleObjects, WriteFile;
    import core.sys.windows.winerror : WAIT_TIMEOUT;
    import core.sys.windows.winnt : DUPLICATE_SAME_ACCESS;

    private enum : int
    {
        termOk,
        termUnsupported,
        termConflict,
        termIoError,
        termNoMemory,
        termWait,
        termEof,
        termCancelled,
        termRetry,
        termInput,
        termResize,
        termInterrupt
    }

    private enum uint raw = 1, alternate = 2, mouse = 4, paste = 8;
    private enum size_t readSlab = 32_768;

    // Console modes (wincon.h).
    private enum DWORD processedInput = 0x0001, lineInput = 0x0002, echoInput = 0x0004,
            windowInput = 0x0008, quickEditMode = 0x0040, extendedFlags = 0x0080, virtualTerminalInput = 0x0200;
    private enum DWORD processedOutput = 0x0001, virtualTerminalProcessing = 0x0004, disableNewlineAutoReturn = 0x0008;
    private enum uint utf8CodePage = 65_001;
    private enum DWORD fileTypeDisk = 1, fileTypePipe = 3;

    private struct SrwLock
    {
        void* state;
    }

    private alias ControlHandler = extern (Windows) BOOL function(DWORD) nothrow @nogc;

    private extern (Windows) nothrow @nogc
    {
        void AcquireSRWLockExclusive(SrwLock* lock);
        void ReleaseSRWLockExclusive(SrwLock* lock);
        BOOL SetConsoleCtrlHandler(ControlHandler handler, BOOL add);
        uint GetConsoleOutputCP();
        BOOL SetConsoleOutputCP(uint codePage);
        uint GetConsoleCP();
        BOOL SetConsoleCP(uint codePage);
    }

package(flint.term):

    struct TerminalHandle
    {
        private HANDLE input;
        private HANDLE output;
        private HANDLE wake;
        private uint modes;
        private bool ttyIn;
        private bool ttyOut;
        private bool watched;
        private bool closing;
        private bool closed;
        private bool snapshot;
        private DWORD inputMode;
        private DWORD outputMode;
        private uint inputCodePage;
        private uint outputCodePage;
        private DWORD inputType;
        // UTF-8 bytes converted from console records and not yet read, and a pending high surrogate.
        private ubyte[64] pending;
        private size_t pendingStart;
        private size_t pendingEnd;
        private wchar highSurrogate;
        private bool resized;
        // The window size last reported, so a buffer-size record that leaves it unchanged is not a resize.
        private uint columns;
        private uint rows;
    }

    // Serializes process-global console state and handle retirement, like the lifecycle mutex in linux.c.
    // The control handler never takes it.
    private __gshared SrwLock lifecycle;
    private __gshared bool ownerActive;
    private __gshared HANDLE interruptEvent;

    private extern (Windows) BOOL onControl(DWORD kind) nothrow @nogc
    {
        auto event = interruptEvent;
        if (kind != 0 || event is null) // CTRL_C_EVENT only; every other event keeps its default handling.
            return 0;
        SetEvent(event);
        return 1;
    }

    private bool console(HANDLE handle, out DWORD mode) nothrow @nogc
    {
        return handle !is null && handle != INVALID_HANDLE_VALUE && GetConsoleMode(handle, &mode) != 0;
    }

    private HANDLE duplicate(DWORD which) nothrow @nogc
    {
        auto standard = GetStdHandle(which);
        if (standard is null || standard == INVALID_HANDLE_VALUE)
            return null;
        HANDLE owned;
        if (!DuplicateHandle(GetCurrentProcess(), standard, GetCurrentProcess(), &owned, 0, 0, DUPLICATE_SAME_ACCESS))
            return null;
        return owned;
    }

    private int outputAll(scope const TerminalHandle* state, scope const(void)* bytes, size_t length) nothrow @nogc
    {
        auto cursor = cast(const(ubyte)*) bytes;
        while (length != 0)
        {
            const batch = length < 4096 ? cast(DWORD) length : 4096;
            DWORD written;
            if (!WriteFile(cast(HANDLE) state.output, cursor, batch, &written, null) || written == 0)
                return termIoError;
            cursor += written;
            length -= written;
        }
        return termOk;
    }

    private int writeMode(scope const TerminalHandle* state, uint bit, bool opening) nothrow @nogc
    {
        switch (bit)
        {
        case alternate:
            return opening ? outputAll(state, "\x1b[?1049h".ptr, 8) : outputAll(state, "\x1b[?1049l".ptr, 8);
        case mouse:
            return opening ? outputAll(state, "\x1b[?1000h\x1b[?1006h".ptr, 16) : outputAll(state,
                    "\x1b[?1006l\x1b[?1000l".ptr, 16);
        case paste:
            return opening ? outputAll(state, "\x1b[?2004h".ptr, 8) : outputAll(state, "\x1b[?2004l".ptr, 8);
        default:
            return termOk;
        }
    }

    private int watch(TerminalHandle* state) nothrow @nogc
    {
        if (ownerActive)
            return termConflict;
        if (interruptEvent is null)
        {
            // Lives for the process: a handler already running during removal can never signal a reused handle.
            interruptEvent = CreateEventW(null, 1, 0, null);
            if (interruptEvent is null)
                return termIoError;
        }
        import core.sys.windows.winbase : ResetEvent;

        ResetEvent(interruptEvent);
        if (!SetConsoleCtrlHandler(&onControl, 1))
            return termIoError;
        ownerActive = true;
        state.watched = true;
        return termOk;
    }

    private int restore(TerminalHandle* state) nothrow @nogc
    {
        int first = termOk;
        for (uint mode = paste; mode >= alternate; mode >>= 1)
        {
            if ((state.modes & mode) == 0)
                continue;
            const status = writeMode(state, mode, false);
            if (first == termOk)
                first = status;
        }
        state.modes = 0;
        if (state.snapshot)
        {
            if (!SetConsoleMode(state.input, state.inputMode) && first == termOk)
                first = termIoError;
            if (!SetConsoleMode(state.output, state.outputMode) && first == termOk)
                first = termIoError;
            SetConsoleCP(state.inputCodePage);
            SetConsoleOutputCP(state.outputCodePage);
            state.snapshot = false;
        }
        if (state.watched)
        {
            if (!SetConsoleCtrlHandler(&onControl, 0) && first == termOk)
                first = termIoError;
            state.watched = false;
            ownerActive = false;
        }
        return first;
    }

    private int initialize(TerminalHandle* state, uint modes) nothrow @nogc
    {
        DWORD inputMode, outputMode;
        state.ttyIn = console(state.input, inputMode);
        state.ttyOut = console(state.output, outputMode);
        state.inputType = GetFileType(state.input);
        if (!state.ttyIn || !state.ttyOut)
            return (modes & raw) ? termUnsupported : termOk;
        int status = watch(state);
        if (status != termOk)
            return status;
        state.inputMode = inputMode;
        state.outputMode = outputMode;
        state.inputCodePage = GetConsoleCP();
        state.outputCodePage = GetConsoleOutputCP();
        state.snapshot = true;
        cast(void) windowSize(state, state.columns, state.rows);
        DWORD input = (inputMode | windowInput | virtualTerminalInput | extendedFlags) & ~quickEditMode;
        DWORD output = outputMode | processedOutput | virtualTerminalProcessing;
        if (modes & raw)
        {
            input &= ~(lineInput | echoInput | processedInput);
            output |= disableNewlineAutoReturn;
        }
        if (!SetConsoleMode(state.input, input) || !SetConsoleMode(state.output, output)
                || !SetConsoleOutputCP(utf8CodePage) || !SetConsoleCP(utf8CodePage))
            return termIoError;
        for (uint mode = alternate; mode <= paste; mode <<= 1)
        {
            if ((modes & mode) == 0)
                continue;
            state.modes |= mode;
            status = writeMode(state, mode, true);
            if (status != termOk)
                return status;
        }
        return termOk;
    }

    private void closeHandles(TerminalHandle* state) nothrow @nogc
    {
        foreach (handle; [state.input, state.output, state.wake])
            if (handle !is null)
                CloseHandle(handle);
    }

    int flint_term_native_open(uint modes, TerminalHandle** result) nothrow @nogc
    {
        if (result is null)
            return termIoError;
        *result = null;
        auto state = cast(TerminalHandle*) calloc(1, TerminalHandle.sizeof);
        if (state is null)
            return termNoMemory;
        state.input = duplicate(STD_INPUT_HANDLE);
        state.output = duplicate(STD_OUTPUT_HANDLE);
        state.wake = CreateEventW(null, 1, 0, null);
        int status = termIoError;
        if (state.input !is null && state.output !is null && state.wake !is null)
        {
            AcquireSRWLockExclusive(&lifecycle);
            status = initialize(state, modes);
            if (status != termOk)
                cast(void) restore(state);
            ReleaseSRWLockExclusive(&lifecycle);
        }
        if (status != termOk)
        {
            closeHandles(state);
            free(state);
            return status;
        }
        *result = state;
        return termOk;
    }

    int flint_term_native_tty(scope const TerminalHandle* state) nothrow @nogc
    {
        return state.ttyOut;
    }

    private bool windowSize(scope const TerminalHandle* state, out uint columns, out uint rows) nothrow @nogc
    {
        CONSOLE_SCREEN_BUFFER_INFO information;
        if (!GetConsoleScreenBufferInfo(cast(HANDLE) state.output, &information))
            return false;
        columns = information.srWindow.Right - information.srWindow.Left + 1;
        rows = information.srWindow.Bottom - information.srWindow.Top + 1;
        return true;
    }

    int flint_term_native_size(scope const TerminalHandle* state, scope uint* columns, scope uint* rows) nothrow @nogc
    {
        AcquireSRWLockExclusive(&lifecycle);
        scope (exit)
            ReleaseSRWLockExclusive(&lifecycle);
        if (state.closing)
            return termCancelled;
        if (!state.ttyOut && !state.ttyIn)
            return termUnsupported;
        return windowSize(state, *columns, *rows) ? termOk : termIoError;
    }

    // Append one UTF-16 unit as UTF-8, pairing surrogates across records.
    private void appendUnit(TerminalHandle* state, wchar unit) nothrow @nogc
    {
        uint code = unit;
        if (unit >= 0xD800 && unit < 0xDC00)
        {
            state.highSurrogate = unit;
            return;
        }
        if (unit >= 0xDC00 && unit < 0xE000)
        {
            if (state.highSurrogate == 0)
                return;
            code = 0x10000 + ((state.highSurrogate - 0xD800) << 10) + (unit - 0xDC00);
        }
        state.highSurrogate = 0;
        ubyte[4] bytes;
        size_t count;
        if (code < 0x80)
            bytes[count++] = cast(ubyte) code;
        else if (code < 0x800)
        {
            bytes[count++] = cast(ubyte)(0xC0 | (code >> 6));
            bytes[count++] = cast(ubyte)(0x80 | (code & 0x3F));
        }
        else if (code < 0x10000)
        {
            bytes[count++] = cast(ubyte)(0xE0 | (code >> 12));
            bytes[count++] = cast(ubyte)(0x80 | ((code >> 6) & 0x3F));
            bytes[count++] = cast(ubyte)(0x80 | (code & 0x3F));
        }
        else
        {
            bytes[count++] = cast(ubyte)(0xF0 | (code >> 18));
            bytes[count++] = cast(ubyte)(0x80 | ((code >> 12) & 0x3F));
            bytes[count++] = cast(ubyte)(0x80 | ((code >> 6) & 0x3F));
            bytes[count++] = cast(ubyte)(0x80 | (code & 0x3F));
        }
        state.pending[state.pendingEnd .. state.pendingEnd + count] = bytes[0 .. count];
        state.pendingEnd += count;
    }

    // Read the available console records into the pending bytes, at most a few at a time so they always fit.
    private int drainRecords(TerminalHandle* state) nothrow @nogc
    {
        INPUT_RECORD[8] records;
        DWORD count;
        if (state.pendingStart == state.pendingEnd)
            state.pendingStart = state.pendingEnd = 0;
        if (state.pending.length - state.pendingEnd < records.length * 4 * 2)
            return termOk; // Room only after the caller reads what is pending.
        if (!ReadConsoleInputW(state.input, records.ptr, records.length, &count))
            return termIoError;
        foreach (ref record; records[0 .. count])
        {
            if (record.EventType == WINDOW_BUFFER_SIZE_EVENT)
            {
                uint columns, rows;
                if (windowSize(state, columns, rows) && (columns != state.columns || rows != state.rows))
                {
                    state.columns = columns;
                    state.rows = rows;
                    state.resized = true;
                }
            }
            else if (record.EventType == KEY_EVENT && record.KeyEvent.bKeyDown && record.KeyEvent.UnicodeChar != 0)
                appendUnit(state, record.KeyEvent.UnicodeChar);
        }
        return termOk;
    }

    int flint_term_native_poll(scope const TerminalHandle* constant, long timeout) nothrow @nogc
    {
        auto state = cast(TerminalHandle*) constant;
        if (state.pendingStart < state.pendingEnd)
            return termInput;
        const millis = timeoutMillis(timeout);
        if (!state.ttyIn && state.inputType == fileTypeDisk)
            return termInput;
        if (!state.ttyIn && state.inputType == fileTypePipe)
            return pollPipe(state, millis);
        return pollConsole(state, millis);
    }

    // A nanosecond timeout as whole milliseconds, rounded up; negative means no limit.
    private DWORD timeoutMillis(long timeout) pure nothrow @nogc
    {
        if (timeout < 0)
            return INFINITE;
        const millis = (timeout + 999_999) / 1_000_000;
        return millis > uint.max - 1 ? uint.max - 1 : cast(DWORD) millis;
    }

    // Wait for console input, close or Ctrl+C, then turn the available records into bytes or a resize.
    private int pollConsole(TerminalHandle* state, DWORD millis) nothrow @nogc
    {
        import core.sys.windows.winbase : ResetEvent;

        HANDLE[3] handles = [state.input, state.wake, state.watched ? interruptEvent : state.wake];
        const status = WaitForMultipleObjects(3, handles.ptr, 0, millis);
        if (status == WAIT_TIMEOUT)
            return termWait;
        if (status == WAIT_OBJECT_0 + 1 || (status == WAIT_OBJECT_0 + 2 && !state.watched))
            return termCancelled;
        if (status == WAIT_OBJECT_0 + 2)
        {
            ResetEvent(interruptEvent);
            return termInterrupt;
        }
        if (status != WAIT_OBJECT_0 || drainRecords(state) != termOk)
            return termIoError;
        if (state.resized)
        {
            state.resized = false;
            return termResize;
        }
        return state.pendingStart < state.pendingEnd ? termInput : termRetry;
    }

    // An anonymous pipe cannot be waited on, so its readiness is polled, waking every millisecond for close.
    private int pollPipe(TerminalHandle* state, DWORD millis) nothrow @nogc
    {
        import core.sys.windows.winbase : WaitForSingleObject;

        DWORD waited;
        for (;;)
        {
            DWORD available;
            if (!PeekNamedPipe(state.input, null, 0, null, &available, null) || available != 0)
                return termInput; // Data, or a broken pipe that the read reports as end of input.
            if (WaitForSingleObject(state.wake, 0) == WAIT_OBJECT_0)
                return termCancelled;
            if (millis != INFINITE && waited >= millis)
                return termWait;
            Sleep(1);
            ++waited;
        }
    }

    int flint_term_native_read(scope const TerminalHandle* constant, scope ubyte* bytes, size_t length,
            scope size_t* written) nothrow @nogc
    {
        auto state = cast(TerminalHandle*) constant;
        *written = 0;
        if (bytes is null || length == 0 || length > readSlab)
            return termIoError;
        if (state.ttyIn)
        {
            if (state.pendingStart == state.pendingEnd)
                return termRetry;
            const available = state.pendingEnd - state.pendingStart;
            const count = available < length ? available : length;
            bytes[0 .. count] = state.pending[state.pendingStart .. state.pendingStart + count];
            state.pendingStart += count;
            *written = count;
            return termOk;
        }
        DWORD count;
        if (!ReadFile(state.input, bytes, cast(DWORD) length, &count, null))
            return termEof; // A broken pipe is end of input.
        if (count == 0)
            return termEof;
        *written = count;
        return termOk;
    }

    nothrow @nogc int flint_term_native_write(scope const TerminalHandle* state, scope const(char)* text, size_t count)
    {
        if (count == 0)
            return termOk;
        if (text is null)
            return termIoError;
        return outputAll(state, text, count);
    }

    void flint_term_native_wake(scope TerminalHandle* state) nothrow @nogc
    {
        AcquireSRWLockExclusive(&lifecycle);
        if (!state.closing)
        {
            state.closing = true;
            SetEvent(state.wake);
        }
        ReleaseSRWLockExclusive(&lifecycle);
    }

    int flint_term_native_closing(scope const TerminalHandle* state) nothrow @nogc
    {
        AcquireSRWLockExclusive(&lifecycle);
        const closing = state.closing;
        ReleaseSRWLockExclusive(&lifecycle);
        return closing;
    }

    int flint_term_native_close(scope TerminalHandle* state) nothrow @nogc
    {
        AcquireSRWLockExclusive(&lifecycle);
        scope (exit)
            ReleaseSRWLockExclusive(&lifecycle);
        int status = termOk;
        if (!state.closed)
        {
            status = restore(state);
            closeHandles(state);
            state.input = state.output = state.wake = null;
            state.closed = true;
        }
        return status;
    }

    void flint_term_native_destroy(scope TerminalHandle* state) nothrow @nogc
    {
        free(state);
    }
}
