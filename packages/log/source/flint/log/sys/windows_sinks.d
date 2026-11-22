/// Windows logger sinks: owned handles for a file or the standard streams, and address waits for the consumer.
module flint.log.sys.windows_sinks;

import flint.arena : Error, Result, Status;
import flint.log.types : Level;

@safe:

version (Windows)
{
    private alias Word = shared(void)*;
    private alias AddressWait = extern (Windows) int function(scope Word, scope void*, size_t, uint) nothrow @nogc;
    private alias AddressWake = extern (Windows) void function(scope Word) nothrow @nogc @system;

    // WaitOnAddress and WakeByAddressAll are resolved from KernelBase, which every process loads, so no
    // synchronization.lib reaches the link of programs that use the logger. A race resolves the same pointers.
    private __gshared AddressWait waitOnAddress;
    private __gshared AddressWake wakeByAddressAll;
    private __gshared bool addressWaitsResolved;

    // SAFETY: GetProcAddress returns either null or the named export, whose signature the aliases above state.
    private void resolveAddressWaits() @trusted nothrow @nogc
    {
        import core.sys.windows.winbase : GetModuleHandleW, GetProcAddress;

        if (addressWaitsResolved)
            return;
        auto kernel = GetModuleHandleW("kernelbase.dll"w.ptr);
        if (kernel !is null)
        {
            waitOnAddress = cast(AddressWait) GetProcAddress(kernel, "WaitOnAddress");
            wakeByAddressAll = cast(AddressWake) GetProcAddress(kernel, "WakeByAddressAll");
        }
        addressWaitsResolved = true;
    }

package(flint.log):

    struct NativeSink
    {
        private Stream output;
        private Stream errors;
    }

    // Handles are kept as integers so that a const sink still converts to a mutable copy, as on POSIX.
    private struct Stream
    {
        size_t handle;
        bool console;
        bool disk;
    }

    private Status ioStatus(uint code) pure nothrow @nogc
    {
        import core.sys.windows.winerror : ERROR_ACCESS_DENIED, ERROR_FILE_NOT_FOUND, ERROR_PATH_NOT_FOUND;

        if (code == ERROR_ACCESS_DENIED)
            return Status.permissionDenied;
        if (code == ERROR_FILE_NOT_FOUND || code == ERROR_PATH_NOT_FOUND)
            return Status.notFound;
        return Status.ioError;
    }

    // SAFETY: The UTF-16 path is NUL-terminated and borrowed only during CreateFileW. The sink owns the returned
    // handle (or the two non-inheritable duplicates of the standard streams) and closes them in closeSink.
    @trusted Result!NativeSink openSink(string path)
    {
        import core.sys.windows.winbase : CloseHandle, CreateFileW, FILE_TYPE_DISK, GetFileType,
            GetLastError, INVALID_HANDLE_VALUE, OPEN_ALWAYS, STD_ERROR_HANDLE, STD_OUTPUT_HANDLE;
        import core.sys.windows.winnt : FILE_ATTRIBUTE_NORMAL, FILE_SHARE_DELETE, FILE_SHARE_READ,
            FILE_SHARE_WRITE, GENERIC_WRITE;
        import std.utf : toUTF16z;

        if (path.length != 0)
        {
            foreach (character; path)
                if (character == 0)
                    return Result!NativeSink(NativeSink.init, Error(Status.invalidArgument,
                            "could not open logger file"));
            const(wchar)* wide;
            try
                wide = toUTF16z(path);
            catch (Exception)
                return Result!NativeSink(NativeSink.init, Error(Status.invalidArgument, "could not open logger file"));
            // Write access also opens a named pipe; disk files append through the end-of-file offset in push.
            auto handle = CreateFileW(wide, GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                    null, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, null);
            if (handle == INVALID_HANDLE_VALUE)
                return Result!NativeSink(NativeSink.init, Error(ioStatus(GetLastError()),
                        "could not open logger file"));
            const file = Stream(cast(size_t) handle, false, GetFileType(handle) == FILE_TYPE_DISK);
            return Result!NativeSink(NativeSink(file, file));
        }

        auto output = openStream(STD_OUTPUT_HANDLE);
        if (output.handle == 0)
            return Result!NativeSink(NativeSink.init, Error(ioStatus(GetLastError()), "could not open logger stdout"));
        auto errors = openStream(STD_ERROR_HANDLE);
        if (errors.handle == 0)
        {
            const status = ioStatus(GetLastError());
            CloseHandle(cast(void*) output.handle);
            return Result!NativeSink(NativeSink.init, Error(status, "could not open logger stderr"));
        }
        return Result!NativeSink(NativeSink(output, errors));
    }

    // A non-inheritable duplicate of a standard handle, which shares the caller's file pointer like the POSIX
    // duplicate does; null when the stream is absent or cannot be duplicated.
    // SAFETY: GetStdHandle borrows the process's handle; DuplicateHandle writes only the local result, which
    // the caller then owns. GetConsoleMode writes only the local mode.
    private Stream openStream(uint which) @trusted nothrow @nogc
    {
        import core.sys.windows.wincon : GetConsoleMode;
        import core.sys.windows.winbase : DuplicateHandle, GetCurrentProcess, GetStdHandle, INVALID_HANDLE_VALUE;
        import core.sys.windows.winnt : DUPLICATE_SAME_ACCESS;

        auto standard = GetStdHandle(which);
        if (standard is null || standard == INVALID_HANDLE_VALUE)
            return Stream.init;
        void* owned;
        if (!DuplicateHandle(GetCurrentProcess(), standard, GetCurrentProcess(), &owned, 0, 0, DUPLICATE_SAME_ACCESS))
            return Stream.init;
        uint mode;
        return Stream(cast(size_t) owned, GetConsoleMode(owned, &mode) != 0);
    }

    // SAFETY: The only owner releases each live handle once. A file may be shared by both severities.
    void closeSink(ref NativeSink sink) @trusted nothrow @nogc
    {
        import core.sys.windows.winbase : CloseHandle;

        if (sink.output.handle != 0)
            CloseHandle(cast(void*) sink.output.handle);
        if (sink.errors.handle != 0 && sink.errors.handle != sink.output.handle)
            CloseHandle(cast(void*) sink.errors.handle);
        sink = NativeSink.init;
    }

    /// Windows has no SIGPIPE: a write to a closed pipe fails with an error instead of a signal.
    Status protectSink() nothrow @nogc
    {
        return Status.ok;
    }

    // SAFETY: WriteFile reads at most the borrowed bytes (and at most uint.max of them) and returns before the
    // consumer can reuse its buffer; the console path converts into a local buffer first.
    Result!size_t push(ref const NativeSink sink, Level severity, scope const(char)[] bytes) @trusted nothrow @nogc
    {
        import core.sys.windows.winbase : GetLastError, OVERLAPPED, WriteFile;

        const stream = severity == Level.error ? sink.errors : sink.output;
        if (stream.console)
            return writeConsole(cast(void*) stream.handle, bytes);
        uint count;
        const length = bytes.length > uint.max ? uint.max : cast(uint) bytes.length;
        // An all-ones offset appends each write at the end of a disk file atomically, like O_APPEND.
        OVERLAPPED end;
        end.Offset = uint.max;
        end.OffsetHigh = uint.max;
        if (!WriteFile(cast(void*) stream.handle, bytes.ptr, length, &count, stream.disk ? &end : null))
            return Result!size_t(0, Error(ioStatus(GetLastError()), "logger sink write failed"));
        if (count == 0 && length != 0)
            return Result!size_t(0, Error(Status.ioError, "logger sink made no progress"));
        return Result!size_t(count);
    }

    // A console shows UTF-16 text whatever its code page, so UTF-8 records are converted before writing. Only
    // whole UTF-8 sequences are converted; the consumer resubmits the rest.
    // SAFETY: The conversion reads `bytes[0 .. take]` and writes at most `wide.length` units into the local
    // buffer; WriteConsoleW reads only the converted units.
    private Result!size_t writeConsole(void* handle, scope const(char)[] bytes) @trusted nothrow @nogc
    {
        import core.sys.windows.wincon : WriteConsoleW;
        import core.sys.windows.winbase : GetLastError;
        import core.sys.windows.winnls : CP_UTF8, MultiByteToWideChar;

        wchar[2048] wide = void;
        size_t take = bytes.length < wide.length ? bytes.length : wide.length;
        if (take < bytes.length)
        {
            while (take > 0 && (bytes[take] & 0xC0) == 0x80)
                --take;
            if (take == 0)
                take = bytes.length < wide.length ? bytes.length : wide.length;
        }
        if (take == 0)
            return Result!size_t(0);
        const units = MultiByteToWideChar(CP_UTF8, 0, bytes.ptr, cast(int) take, wide.ptr, cast(int) wide.length);
        if (units <= 0)
            return Result!size_t(0, Error(Status.ioError, "logger sink write failed"));
        uint written;
        if (!WriteConsoleW(handle, wide.ptr, units, &written, null))
            return Result!size_t(0, Error(ioStatus(GetLastError()), "logger sink write failed"));
        return Result!size_t(take);
    }

    // SAFETY: Sleep only suspends the calling thread.
    void pauseConsumer() @trusted nothrow @nogc
    {
        import core.sys.windows.winbase : Sleep;

        Sleep(1);
    }

    // SAFETY: WaitOnAddress compares the aligned 32-bit word with the local copy of expected and sleeps at most
    // the rounded-up timeout; it reads the word only during the call and retains neither address.
    void park(ref shared uint word, uint expected, long nanos) @trusted nothrow @nogc
    {
        uint compare = expected;
        const millis = nanos <= 0 ? 0 : nanos >= 0xFFFF_FFFE_000_000L
            ? 0xFFFF_FFFE : cast(uint)((nanos + 999_999) / 1_000_000);
        // A timeout, a spurious wake and a changed word all return to a caller that rechecks its condition.
        resolveAddressWaits();
        if (waitOnAddress is null)
            return pauseConsumer();
        waitOnAddress(&word, &compare, uint.sizeof, millis);
    }

    // SAFETY: The address is used only as a key for waking its current waiters.
    void wake(ref shared uint word) @trusted nothrow @nogc
    {
        resolveAddressWaits();
        if (wakeByAddressAll !is null)
            wakeByAddressAll(&word);
    }
}
