module flint.term.sys.linux_session;

@safe:

// The native terminal session is native/linux.c on Linux and macOS, and flint.term.sys.windows_console on
// Windows, both behind the ABI in flint.term.sys.linux_abi.
version (linux)
    version = FlintTermNative;
else version (OSX)
    version = FlintTermNative;
else version (Windows)
    version = FlintTermNative;

version (FlintTermNative)
{
    import core.sync.mutex : Mutex;
    import flint.arena : Error, Result, Status;
    import flint.term.events : ColorProfile, Event, EventKind, Options, Size;
    import flint.term.internal : DecodeStep, Decoder, deadlineAfter, nowNanos, readBytes;
    import flint.term.sys.linux_abi : Handle = TerminalHandle, flint_term_native_open,
        flint_term_native_tty, flint_term_native_size, flint_term_native_poll,
        flint_term_native_read,
        flint_term_native_write, flint_term_native_wake,
        flint_term_native_closing, flint_term_native_close, flint_term_native_destroy;

    private enum NativeStatus : int
    {
        ok,
        unsupported,
        conflict,
        ioError,
        outOfMemory,
        wait,
        eof,
        cancelled,
        retry,
        input,
        resize,
        interrupt
    }

    private Error failure(NativeStatus status) pure nothrow @nogc
    {
        switch (status)
        {
        case NativeStatus.ok:
            return Error.init;
        case NativeStatus.unsupported:
            return Error(Status.unsupported, "operation requires a terminal");
        case NativeStatus.conflict:
            return Error(Status.conflict, "terminal or interrupt handler already owned");
        case NativeStatus.outOfMemory:
            return Error(Status.outOfMemory, "unable to allocate a terminal session");
        case NativeStatus.cancelled:
            return Error(Status.cancelled, "terminal session closed");
        case NativeStatus.wait:
            return Error(Status.timedOut, "terminal event deadline elapsed");
        default:
            return Error(Status.ioError, "terminal I/O failed");
        }
    }

    package(flint.term) final class LinuxSession
    {
        private Handle* native;
        private Mutex readGate;
        private Mutex writeGate;
        private Decoder decoder;
        private ubyte[readBytes] slab;
        private size_t position;
        private size_t available;
        private bool eof;
        private ColorProfile profile;

        private this()
        {
            readGate = new Mutex;
            writeGate = new Mutex;
        }

        static Result!LinuxSession open(Options options)
        {
            auto session = new LinuxSession;
            // Resolve environment policy before acquiring native state.
            const capabilities = environmentColors();
            const opened = openNative(options, session.native);
            if (opened != NativeStatus.ok)
                return Result!LinuxSession(null, failure(opened));
            if (isTerminal(session.native))
                session.profile = capabilities;
            return Result!LinuxSession(session);
        }

        Result!Event next(long timeoutNanos) scope
        {
            readGate.lock_nothrow();
            scope (exit)
                readGate.unlock_nothrow();

            if (isClosing(native))
                return eventFailure(NativeStatus.cancelled);
            const deadline = deadlineAfter(nowNanos(), timeoutNanos);
            bool waited;
            for (;;)
            {
                auto ready = decodeBuffered(nowNanos());
                if (ready.ready)
                    return Result!Event(ready.value);
                const now = nowNanos();
                if (waited && now >= deadline)
                    return eventFailure(NativeStatus.wait);
                const activity = awaitActivity(deadline, now);
                waited = true;
                if (activity == NativeStatus.wait || activity == NativeStatus.retry)
                {
                    ready = decoder.expire(nowNanos());
                    if (ready.ready)
                        return Result!Event(ready.value);
                    continue;
                }
                if (activity == NativeStatus.input)
                {
                    const read = fillSlab();
                    if (read == NativeStatus.ok)
                        continue;
                    return eventFailure(read);
                }
                return activityResult(activity);
            }
        }

        Error write(scope const(char)[] text) scope nothrow
        {
            writeGate.lock_nothrow();
            scope (exit)
                writeGate.unlock_nothrow();
            if (isClosing(native))
                return failure(NativeStatus.cancelled);
            return failure(writeNative(native, text));
        }

        Result!Size size() const scope nothrow
        {
            Size measured;
            const status = sizeNative(native, measured);
            return Result!Size(measured, failure(status));
        }

        ColorProfile colors() const scope pure nothrow @nogc
        {
            return profile;
        }

        Error close() scope nothrow
        {
            signalClose(native);
            readGate.lock_nothrow();
            scope (exit)
                readGate.unlock_nothrow();
            writeGate.lock_nothrow();
            scope (exit)
                writeGate.unlock_nothrow();
            return failure(closeNative(native));
        }

        void dispose() scope nothrow
        {
            if (native is null)
                return;
            close();
            destroyNative(native);
            native = null;
        }

        private NativeStatus awaitActivity(long deadline, long now) scope nothrow @nogc
        {
            const escape = decoder.escapeDeadline();
            const until = escape < deadline ? escape : deadline;
            const remaining = until == long.max ? -1 : until > now ? until - now : 0;
            return waitNative(native, remaining);
        }

        private Result!Event activityResult(NativeStatus activity) const scope nothrow
        {
            if (activity == NativeStatus.resize)
                return resized();
            if (activity == NativeStatus.interrupt)
                return Result!Event(Event(EventKind.interrupt));
            return eventFailure(activity);
        }

        private DecodeStep decodeBuffered(long now) scope
        {
            while (position < available)
            {
                auto result = decoder.feed(slab[position], now);
                if (result.consumed)
                    ++position;
                if (result.ready)
                    return result;
            }
            return eof ? decoder.endOfInput() : DecodeStep.init;
        }

        private NativeStatus fillSlab() scope nothrow @nogc
        {
            position = 0;
            const received = readNative(native, slab[]);
            available = received.count;
            if (received.status == NativeStatus.eof)
                eof = true;
            return received.status == NativeStatus.eof || received.status == NativeStatus.retry
                ? NativeStatus.ok : received.status;
        }

        private Result!Event resized() const scope nothrow
        {
            const dimensions = size();
            if (!dimensions.ok())
                return Result!Event(Event.init, dimensions.error);
            Event changed;
            changed.kind = EventKind.resize;
            changed.size = dimensions.value;
            return Result!Event(changed);
        }
    }

    private Result!Event eventFailure(NativeStatus status) pure nothrow @nogc
    {
        return Result!Event(Event.init, failure(status));
    }

    /// The color profile TERM, COLORTERM and NO_COLOR select. A Windows console that interprets virtual-terminal
    /// sequences renders 24-bit color and sets no TERM, so an unset TERM there means true color.
    package(flint.term) ColorProfile environmentColors() nothrow
    {
        const terminal = environmentValue("TERM", "");
        const noColor = environmentValue("NO_COLOR") != "";
        version (Windows)
        {
            if (terminal == "")
                return noColor ? ColorProfile.none : ColorProfile.trueColor;
        }
        return detectColors(terminal, environmentValue("COLORTERM", ""), noColor);
    }

    package(flint.term) ColorProfile detectColors(string terminal, string colorterm, bool noColor) nothrow
    {
        if (noColor || terminal == "" || terminal == "dumb")
            return ColorProfile.none;
        if (colorterm == "truecolor" || colorterm == "24bit" || containsBytes(terminal, "-direct"))
            return ColorProfile.trueColor;
        return containsBytes(terminal, "256color") ? ColorProfile.ansi256 : ColorProfile.ansi16;
    }

    // Byte-wise substring test, the case-sensitive std.string.indexOf(...) >= 0 on two UTF-8 strings.
    private bool containsBytes(scope const(char)[] text, scope const(char)[] part) pure nothrow @nogc
    {
        if (part.length > text.length)
            return false;
        foreach (start; 0 .. text.length - part.length + 1)
        {
            if (text[start .. start + part.length] == part)
                return true;
        }
        return false;
    }

    version (Windows)
    {
        // std.process.environment.get without importing std.process: the process environment block, which
        // std.process writes, rather than the C runtime's startup copy that getenv reads. A copy of the value,
        // "" when it is set but empty, or `fallback` when it is unset.
        // SAFETY: The name is a NUL-terminated UTF-16 copy; the value is written into a local buffer of the length
        // passed, or a GC buffer of the reported length, and converted before returning.
        package(flint.term) string environmentValue(string name, string fallback = null) @trusted nothrow
        {
            import core.sys.windows.winbase : GetEnvironmentVariableW;
            import std.utf : toUTF16z, toUTF8;

            try
            {
                const wide = toUTF16z(name);
                wchar[256] buffer = void;
                auto length = GetEnvironmentVariableW(wide, buffer.ptr, cast(uint) buffer.length);
                if (length == 0)
                    return GetEnvironmentVariableW(wide, null, 0) == 1 ? "" : fallback;
                if (length < buffer.length)
                    return toUTF8(buffer[0 .. length]);
                auto larger = new wchar[length];
                length = GetEnvironmentVariableW(wide, larger.ptr, cast(uint) larger.length);
                return length != 0 && length < larger.length ? toUTF8(larger[0 .. length]) : fallback;
            }
            catch (Exception)
                return fallback;
        }
    }
    else
    {
        // std.process.environment.get without importing std.process (and std.uni): a copy of the variable's value,
        // "" when it is set but empty, or `fallback` when it is unset.
        // SAFETY: getenv receives a NUL-terminated copy of the name and returns null or a NUL-terminated string,
        // which is read up to its terminator and copied before any other environment call.
        package(flint.term) string environmentValue(string name, string fallback = null) @trusted nothrow
        {
            import core.stdc.string : strlen;
            import core.stdc.stdlib : getenv;

            const terminated = name ~ '\0';
            const value = getenv(terminated.ptr);
            if (value is null)
                return fallback;
            const length = strlen(value);
            return length == 0 ? "" : value[0 .. length].idup;
        }
    }

    // SAFETY: C initializes the output to null on every failure and returns an
    // owned allocation on success. It never keeps the reference to this slot.
    private NativeStatus openNative(Options options, ref Handle* terminal) @trusted nothrow @nogc
    {
        const uint mask = (options.raw ? 1 : 0) | (options.alternateScreen ? 2 : 0) | (options.mouse
                ? 4 : 0) | (options.bracketedPaste ? 8 : 0);
        return cast(NativeStatus) flint_term_native_open(mask, &terminal);
    }

    // SAFETY: Query reads immutable capability data in a live native owner.
    private bool isTerminal(scope const Handle* terminal) @trusted nothrow @nogc
    {
        return flint_term_native_tty(terminal) != 0;
    }

    // SAFETY: Native retirement and query share the lifecycle lock. C writes
    // only the two in-scope uint slots and remembers neither address.
    private NativeStatus sizeNative(scope const Handle* terminal, out Size dimensions) @trusted nothrow @nogc
    {
        return cast(NativeStatus) flint_term_native_size(terminal, &dimensions.columns, &dimensions.rows);
    }

    // SAFETY: The caller holds the read gate, keeping all polled descriptors
    // live until the synchronous wait returns.
    private NativeStatus waitNative(scope const Handle* terminal, long duration) @trusted nothrow @nogc
    {
        return cast(NativeStatus) flint_term_native_poll(terminal, duration);
    }

    private struct Read
    {
        NativeStatus status;
        size_t count;
    }

    // SAFETY: The read gate pins the descriptor. C validates the size and
    // reads only into the supplied span during this call.
    private Read readNative(scope const Handle* handle, scope ubyte[] buffer) @trusted nothrow @nogc
    {
        Read received;
        received.status = cast(NativeStatus) flint_term_native_read(handle, buffer.ptr,
                buffer.length, &received.count);
        return received.count <= buffer.length ? received : Read(NativeStatus.ioError, 0);
    }

    // SAFETY: The write gate pins stdout and the wake descriptor. The scoped
    // span remains valid for the synchronous write and is never retained.
    private NativeStatus writeNative(scope const Handle* terminal, scope const(char)[] text) @trusted nothrow @nogc
    {
        return cast(NativeStatus) flint_term_native_write(terminal, text.ptr, text.length);
    }

    // SAFETY: C observes the live owner's closing flag under the lifecycle lock.
    private bool isClosing(scope const Handle* terminal) @trusted nothrow @nogc
    {
        return flint_term_native_closing(terminal) != 0;
    }

    // SAFETY: The lifecycle lock ensures the wake descriptor is live while
    // signalling. It is never written again after closure has started.
    private void signalClose(scope Handle* terminal) @trusted nothrow @nogc
    {
        flint_term_native_wake(terminal);
    }

    // SAFETY: The caller holds both I/O gates after signalling close, so no
    // read or write can still be using the descriptors C retires.
    private NativeStatus closeNative(scope Handle* terminal) @trusted nothrow @nogc
    {
        return cast(NativeStatus) flint_term_native_close(terminal);
    }

    // SAFETY: Only destruction of the move-only owner calls this, after both
    // I/O gates were quiesced and the native descriptors were retired.
    private void destroyNative(scope Handle* terminal) @trusted nothrow @nogc
    {
        flint_term_native_destroy(terminal);
    }

    @("capabilities respect terminal color profiles")
    unittest
    {
        assert(detectColors("", "", false) == ColorProfile.none);
        assert(detectColors("dumb", "truecolor", false) == ColorProfile.none);
        assert(detectColors("xterm", "", false) == ColorProfile.ansi16);
        assert(detectColors("xterm-256color", "", false) == ColorProfile.ansi256);
        assert(detectColors("xterm-256color", "truecolor", false) == ColorProfile.trueColor);
        assert(detectColors("xterm-direct", "", false) == ColorProfile.trueColor);
        assert(detectColors("xterm", "24bit", true) == ColorProfile.none);
    }
}
