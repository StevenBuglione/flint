/// The Windows counterparts of flint_tool.sys.posix.
module flint_tool.sys.windows;

@safe:

version (Windows)
{
    private extern (Windows) nothrow @nogc @system
    {
        uint GetFinalPathNameByHandleW(void* file, wchar* path, uint length, uint flags);
    }

    /// Windows has no exec: run `argv` in `directory` with flint's standard handles and console, then end flint
    /// with the program's exit code. Returns only when the program could not be started, with ENOENT.
    int replaceProcess(string executable, scope const(string)[] argv, string directory)
    {
        import core.stdc.stdlib : exit;
        import std.process : Config, spawnProcess, wait;

        int code;
        try
        {
            // Ctrl+C reaches the program through the shared console; flint's own handler keeps flint waiting.
            auto program = spawnProcess([executable] ~ argv[1 .. $], null, Config.none,
                    directory.length ? directory : null);
            code = wait(program);
        }
        catch (Exception)
            return 2;
        terminate(code);
    }

    // SAFETY: Ends the process after the program it ran has exited; flint holds no state that needs teardown.
    private noreturn terminate(int code) @trusted nothrow @nogc
    {
        import core.stdc.stdlib : exit;

        exit(code);
    }

    /// The final path of an existing file or directory, with every link resolved and without the `\\?\` prefix,
    /// or null when it cannot be opened.
    // SAFETY: The path is a NUL-terminated GC copy; the final path is written into a local buffer of the length
    // passed, and the handle is closed before returning.
    @trusted string finalPath(string path)
    {
        import core.sys.windows.winbase : CloseHandle, CreateFileW, FILE_FLAG_BACKUP_SEMANTICS,
            INVALID_HANDLE_VALUE, OPEN_EXISTING;
        import core.sys.windows.winnt : FILE_SHARE_DELETE, FILE_SHARE_READ, FILE_SHARE_WRITE;
        import std.utf : toUTF16z, toUTF8;

        auto handle = CreateFileW(toUTF16z(path), 0x0080, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                null, OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS, null);
        if (handle == INVALID_HANDLE_VALUE)
            return null;
        scope (exit)
            CloseHandle(handle);
        wchar[32_768] buffer = void;
        const length = GetFinalPathNameByHandleW(handle, buffer.ptr, cast(uint) buffer.length, 0);
        if (length == 0 || length >= buffer.length)
            return null;
        auto text = toUTF8(buffer[0 .. length]);
        if (text.length > 8 && text[0 .. 8] == `\\?\UNC\`)
            return `\\` ~ text[8 .. $];
        return text.length > 4 && text[0 .. 4] == `\\?\` ? text[4 .. $] : text;
    }

    /// Windows runs no compile server (ADR-026), so no server lock is ever held.
    bool lockHeld(string)
    {
        return false;
    }

    /// End the process `pid`; Windows has no process groups to signal, so `signal` only sets the exit code.
    // SAFETY: The handle opened for `pid` is closed before returning; no memory is passed.
    bool signalProcessGroup(int pid, int signal) @trusted nothrow @nogc
    {
        import core.sys.windows.winbase : CloseHandle, OpenProcess, TerminateProcess;

        enum uint processTerminate = 0x0001;
        if (pid <= 0)
            return false;
        auto process = OpenProcess(processTerminate, 0, pid);
        if (process is null)
            return false;
        scope (exit)
            CloseHandle(process);
        return TerminateProcess(process, 128 + signal) != 0;
    }

    /// Whether the process `pid` is still running.
    // SAFETY: The handle opened for `pid` is closed before returning; the wait does not block.
    bool processAlive(int pid) @trusted nothrow @nogc
    {
        import core.sys.windows.winbase : CloseHandle, OpenProcess, WaitForSingleObject;
        import core.sys.windows.winerror : WAIT_TIMEOUT;

        enum uint synchronize = 0x0010_0000;
        if (pid <= 0)
            return false;
        auto process = OpenProcess(synchronize, 0, pid);
        if (process is null)
            return false;
        scope (exit)
            CloseHandle(process);
        return WaitForSingleObject(process, 0) == WAIT_TIMEOUT;
    }

    /// The first of `names` Windows can load as a library, or null. Each library is freed again at once.
    string loadableLibrary(scope const(string)[] names)
    {
        import std.utf : toUTF16z;

        foreach (name; names)
        {
            const(wchar)* wide;
            try
                wide = toUTF16z(name);
            catch (Exception)
                continue;
            if (probeLibrary(wide))
                return name;
        }
        return null;
    }

    // SAFETY: The name is a NUL-terminated GC copy kept alive by the caller; the module LoadLibraryW returns is
    // freed before returning and never escapes this function.
    private bool probeLibrary(const(wchar)* name) @trusted nothrow @nogc
    {
        import core.sys.windows.winbase : FreeLibrary, LoadLibraryW;

        auto library = LoadLibraryW(name);
        if (library is null)
            return false;
        FreeLibrary(library);
        return true;
    }

    /// Write all of `text` to standard output.
    void writeOutput(scope const(char)[] text)
    {
        import core.sys.windows.winbase : STD_OUTPUT_HANDLE;

        writeAll(STD_OUTPUT_HANDLE, text);
    }

    /// Write all of `text` to standard error.
    void writeError(scope const(char)[] text)
    {
        import core.sys.windows.winbase : STD_ERROR_HANDLE;

        writeAll(STD_ERROR_HANDLE, text);
    }

    /// Let flint's own consoles interpret the colour and cursor sequences it writes, as a terminal does.
    // SAFETY: The mode queries and updates write only locals and act on the process's own standard handles.
    void prepareConsole() @trusted nothrow @nogc
    {
        import core.sys.windows.wincon : GetConsoleMode, SetConsoleMode;
        import core.sys.windows.winbase : GetStdHandle, STD_ERROR_HANDLE, STD_OUTPUT_HANDLE;

        enum uint virtualTerminalProcessing = 0x0004;
        foreach (which; [STD_OUTPUT_HANDLE, STD_ERROR_HANDLE])
        {
            auto handle = GetStdHandle(which);
            uint mode;
            if (handle !is null && GetConsoleMode(handle, &mode))
                SetConsoleMode(handle, mode | virtualTerminalProcessing);
        }
    }

    // A console shows UTF-16 whatever its code page, so text bound for one is converted; anything else gets the
    // UTF-8 bytes unchanged.
    // SAFETY: Reads at most text.length bytes; the conversion writes only within the local buffer, and each call
    // is given the count of units or bytes that remain.
    private void writeAll(uint which, scope const(char)[] text) @trusted nothrow @nogc
    {
        import core.sys.windows.wincon : GetConsoleMode, WriteConsoleW;
        import core.sys.windows.winbase : GetStdHandle, WriteFile;
        import core.sys.windows.winnls : CP_UTF8, MultiByteToWideChar;

        auto handle = GetStdHandle(which);
        if (handle is null)
            return;
        uint mode;
        const console = GetConsoleMode(handle, &mode) != 0;
        size_t done;
        while (done < text.length)
        {
            size_t take = text.length - done;
            if (take > 4096)
            {
                take = 4096;
                while (take > 0 && (text[done + take] & 0xC0) == 0x80)
                    --take;
                if (take == 0)
                    take = 4096;
            }
            uint written;
            if (console)
            {
                wchar[4096] wide = void;
                const units = MultiByteToWideChar(CP_UTF8, 0, text.ptr + done, cast(int) take,
                        wide.ptr, cast(int) wide.length);
                if (units <= 0 || !WriteConsoleW(handle, wide.ptr, units, &written, null))
                    return;
            }
            else if (!WriteFile(handle, text.ptr + done, cast(uint) take, &written, null) || written == 0)
                return;
            else
                take = written;
            done += take;
        }
    }
}
