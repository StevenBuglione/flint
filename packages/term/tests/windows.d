module flint.term.windows_tests;

// Windows counterparts of the pipe and pseudo-terminal tests. The pseudo-terminal is a ConPTY: the test
// executable starts itself inside one (FLINT_TERM_TEST_CHILD set), and the child reports what describe and a raw
// Session observed into a file named by FLINT_TERM_TEST_RESULT.
version (Windows)
{
    import core.sys.windows.windef : BOOL, DWORD, HANDLE;
    import flint.term : ColorProfile, EventKind, KeyCode, Options, Session, Stream, describe;

    private enum childVariable = "FLINT_TERM_TEST_CHILD";
    private enum resultVariable = "FLINT_TERM_TEST_RESULT";

    private struct Coordinates
    {
        short x;
        short y;
    }

    private extern (Windows) nothrow @nogc @system
    {
        int CreatePseudoConsole(Coordinates size, HANDLE input, HANDLE output, DWORD flags, void** console);
        void ClosePseudoConsole(void* console);
        BOOL InitializeProcThreadAttributeList(void* list, DWORD count, DWORD flags, size_t* size);
        BOOL UpdateProcThreadAttribute(void* list, DWORD flags, size_t attribute, void* value,
                size_t size, void* previous, size_t* returned);
        void DeleteProcThreadAttributeList(void* list);
    }

    shared static this()
    {
        import core.stdc.stdlib : exit;
        import std.process : environment;

        if (environment.get(childVariable, "").length == 0)
            return;
        const path = environment.get(resultVariable);
        try
            exit(child(path));
        catch (Exception failure)
        {
            report(path, "child failed " ~ failure.toString());
            exit(2);
        }
    }

    private void report(string path, string line)
    {
        import std.file : append;

        append(path, line ~ "\n");
    }

    private string profileName(ColorProfile profile)
    {
        import std.conv : to;

        return profile.to!string;
    }

    // Inside the pseudoconsole: report describe under three environments, then read two keys in raw mode.
    private int child(string path) @trusted
    {
        import core.sys.windows.wincon : GetConsoleMode, SetConsoleMode;
        import core.sys.windows.winbase : CreateFileW, OPEN_EXISTING, STD_INPUT_HANDLE,
            STD_OUTPUT_HANDLE, SetStdHandle;
        import core.sys.windows.winnt : FILE_SHARE_READ, FILE_SHARE_WRITE, GENERIC_READ, GENERIC_WRITE;
        import std.conv : to;
        import std.process : environment;

        // A child inherits redirected standard handles from a redirected parent even inside a pseudoconsole, so
        // the console's own input and output become the standard handles first.
        auto output = CreateFileW("CONOUT$"w.ptr, GENERIC_READ | GENERIC_WRITE,
                FILE_SHARE_READ | FILE_SHARE_WRITE, null, OPEN_EXISTING, 0, null);
        auto input = CreateFileW("CONIN$"w.ptr, GENERIC_READ | GENERIC_WRITE,
                FILE_SHARE_READ | FILE_SHARE_WRITE, null, OPEN_EXISTING, 0, null);
        SetStdHandle(STD_OUTPUT_HANDLE, output);
        SetStdHandle(STD_INPUT_HANDLE, input);
        uint mode;
        GetConsoleMode(output, &mode);
        SetConsoleMode(output, mode | 0x0004); // ENABLE_VIRTUAL_TERMINAL_PROCESSING, as an application does.
        environment.remove("TERM");
        environment.remove("NO_COLOR");
        auto info = describe(Stream.output);
        report(path, "describe " ~ info.terminal.to!string ~ " " ~ info.size.columns.to!string ~ "x"
                ~ info.size.rows.to!string ~ " " ~ profileName(info.colors));
        environment["TERM"] = "xterm-256color";
        report(path, "term " ~ profileName(describe(Stream.output).colors));
        environment["NO_COLOR"] = "1";
        report(path, "nocolor " ~ profileName(describe(Stream.output).colors));
        environment.remove("NO_COLOR");
        environment.remove("TERM");

        auto opened = Session.open(Options(true, false, false, false));
        if (!opened.ok)
        {
            report(path, "open failed " ~ opened.error.message);
            return 1;
        }
        auto session = move(opened.value);
        report(path, "size " ~ session.size().value.columns.to!string ~ "x" ~ session.size().value.rows.to!string);
        report(path, "ready");
        {
            import std.file : write;

            write(path ~ ".ready", ""); // The parent polls for this file and never opens the report while it grows.
        }
        foreach (_; 0 .. 2)
        {
            auto event = session.next(10_000_000_000);
            if (!event.ok)
            {
                report(path, "event failed " ~ event.error.message);
                return 1;
            }
            const key = event.value.key;
            report(path, "event " ~ event.value.kind.to!string ~ " " ~ key.code.to!string ~ " " ~ (
                    cast(uint) key.character).to!string);
        }
        report(path, "close " ~ session.close().code.to!string);
        return 0;
    }

    private T move(T)(ref T value)
    {
        import core.lifetime : coreMove = move;

        return coreMove(value);
    }

    @("describe reports a redirected stdout as a colorless non-terminal")
    @trusted unittest
    {
        import core.sys.windows.winbase : CloseHandle, CreatePipe, GetStdHandle, STD_OUTPUT_HANDLE, SetStdHandle;

        HANDLE reader, writer;
        assert(CreatePipe(&reader, &writer, null, 0));
        auto saved = GetStdHandle(STD_OUTPUT_HANDLE);
        assert(SetStdHandle(STD_OUTPUT_HANDLE, writer));
        const info = describe(Stream.output);
        assert(SetStdHandle(STD_OUTPUT_HANDLE, saved));
        CloseHandle(reader);
        CloseHandle(writer);
        assert(!info.terminal && info.size.columns == 0 && info.size.rows == 0);
        assert(info.colors == ColorProfile.none);
    }

    @("a ConPTY child sees its window size, honours TERM and NO_COLOR, and reads keys in raw mode")
    @trusted unittest
    {
        import core.stdc.stdlib : free, malloc;
        import core.sys.windows.winbase : CloseHandle, CreatePipe, CreateProcessW, INFINITE,
            PROCESS_INFORMATION, ReadFile, STARTUPINFOW, Sleep, WaitForSingleObject, WriteFile;
        import core.thread.osthread : Thread;
        import std.file : exists, readText, remove, tempDir, thisExePath;
        import std.path : buildPath;
        import std.process : environment;
        import std.string : indexOf, splitLines;
        import std.utf : toUTF16z;
        import std.uuid : randomUUID;

        const result = buildPath(tempDir(), "flint-term-" ~ randomUUID().toString() ~ ".txt");
        scope (exit)
            foreach (file; [result, result ~ ".ready"])
                if (exists(file))
                    remove(file);
        HANDLE inputRead, inputWrite, outputRead, outputWrite;
        assert(CreatePipe(&inputRead, &inputWrite, null, 0) && CreatePipe(&outputRead, &outputWrite, null, 0));
        void* console;
        assert(CreatePseudoConsole(Coordinates(97, 31), inputRead, outputWrite, 0, &console) == 0);
        CloseHandle(inputRead);
        CloseHandle(outputWrite);
        // The pseudoconsole blocks on a full output pipe, so it is drained until the console closes.
        auto drain = new Thread(() {
            ubyte[4096] buffer;
            uint count;
            while (ReadFile(outputRead, buffer.ptr, buffer.length, &count, null) && count != 0)
            {
            }
        }).start();

        size_t size;
        InitializeProcThreadAttributeList(null, 1, 0, &size);
        auto list = malloc(size);
        assert(list !is null && InitializeProcThreadAttributeList(list, 1, 0, &size));
        enum size_t pseudoconsoleAttribute = 0x0002_0016;
        assert(UpdateProcThreadAttribute(list, 0, pseudoconsoleAttribute, console, (void*).sizeof, null, null));
        struct StartupInfoEx
        {
            STARTUPINFOW startup;
            void* attributes;
        }

        StartupInfoEx info;
        info.startup.cb = StartupInfoEx.sizeof;
        info.attributes = list;
        environment[childVariable] = "1";
        environment[resultVariable] = result;
        scope (exit)
        {
            environment.remove(childVariable);
            environment.remove(resultVariable);
        }
        auto command = ("\"" ~ thisExePath() ~ "\"").toUTF16z;
        PROCESS_INFORMATION process;
        const started = CreateProcessW(null, cast(wchar*) command, null, null, 0, 0x0008_0000,
                null, null, &info.startup, &process);
        DeleteProcThreadAttributeList(list);
        free(list);
        assert(started);
        foreach (_; 0 .. 1_000)
        {
            if (exists(result ~ ".ready"))
                break;
            Sleep(10);
        }
        uint written;
        const keys = "z\x1b[A";
        assert(WriteFile(inputWrite, keys.ptr, cast(uint) keys.length, &written, null) && written == keys.length);
        assert(WaitForSingleObject(process.hProcess, 20_000) == 0);
        CloseHandle(process.hThread);
        CloseHandle(process.hProcess);
        ClosePseudoConsole(console);
        CloseHandle(inputWrite);
        drain.join();
        CloseHandle(outputRead);

        const lines = readText(result).splitLines;
        assert(lines.length == 8, readText(result));
        assert(lines[0 .. 6] == [
            "describe true 97x31 trueColor", "term ansi256", "nocolor none", "size 97x31", "ready",
            "event key character 122"
        ], readText(result));
        assert(lines[6].indexOf("event key up ") == 0 && lines[7] == "close ok", readText(result));
    }
}
