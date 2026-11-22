module flint.os.windows_test;

// The Windows counterparts of the POSIX process, interrupt and glob suites. Windows has no /bin/sh, so the
// test executable is its own child: started with FLINT_OS_TEST_CHILD set, the module constructor below runs
// the requested behaviour and exits before any unittest starts.
version (Windows)
{
    import flint.arena : Status;
    import flint.conc : CancelSource, Context, Deadline;
    import flint.os : EnvVar, GlobOptions, ProcessOptions, glob, onInterrupt, run, stream;

    private enum childVariable = "FLINT_OS_TEST_CHILD";

    private alias ControlHandler = extern (Windows) int function(uint) nothrow @nogc;

    private extern (Windows) nothrow @nogc @system
    {
        int SetConsoleCtrlHandler(ControlHandler handler, int add);
        int GenerateConsoleCtrlEvent(uint event, uint group);
        uint GetConsoleCP();
        uint GetProcessId(void* process);
        int FreeConsole();
        int AllocConsole();
    }

    shared static this()
    {
        import core.stdc.stdlib : exit;
        import std.process : environment;

        const mode = environment.get(childVariable, "");
        if (mode.length != 0)
            exit(childMain(mode));
    }

    private int childMain(string mode) @trusted
    {
        import core.runtime : Runtime;
        import core.sys.windows.winbase : Sleep;
        import std.conv : to;

        const args = Runtime.args;
        switch (mode)
        {
        case "exit":
            return args[1].to!int;
        case "echo":
            return echo(args[1 .. $]);
        case "split":
            return split();
        case "flood":
            return flood();
        case "lines":
            return lines();
        case "sleep":
            Sleep(30_000);
            return 0;
        case "pid":
            return reportPid();
        default:
            return processChild(mode, args);
        }
    }

    // The child modes that act on processes and handles.
    private int processChild(string mode, scope const(string)[] args)
    {
        switch (mode)
        {
        case "tree":
            return tree();
        case "handle":
            return probeHandle(args[1]);
        case "interrupt":
            return interruptChild();
        default:
            return 99;
        }
    }

    private int echo(scope const(string)[] arguments) @trusted
    {
        import core.stdc.stdio : printf;
        import std.file : getcwd;
        import std.process : environment;

        foreach (argument; arguments)
            printf("[%.*s]\n", cast(int) argument.length, argument.ptr);
        const cwd = getcwd();
        const value = environment.get("FLINT_TEST", "<unset>");
        printf("%.*s\n%.*s\n", cast(int) cwd.length, cwd.ptr, cast(int) value.length, value.ptr);
        return 0;
    }

    private int split() @trusted
    {
        import core.stdc.stdio : fflush, fprintf, printf, stderr, stdout;

        printf("abcd");
        fflush(stdout);
        fprintf(stderr, "EFGH");
        return 0;
    }

    private int lines() @trusted
    {
        import core.stdc.stdio : fprintf, printf, stderr;

        foreach (line; 1 .. 100_001)
        {
            printf("%d\n", line);
            fprintf(stderr, "%d\n", line);
        }
        return 0;
    }

    private int reportPid() @trusted
    {
        import core.stdc.stdio : fflush, printf, stdout;
        import core.sys.windows.winbase : Sleep;

        printf("%u\n", processId());
        fflush(stdout);
        Sleep(30_000);
        return 0;
    }

    private uint processId() @trusted
    {
        import core.sys.windows.winbase : GetCurrentProcessId;

        return GetCurrentProcessId();
    }

    // Ten MiB to each stream from two threads, so neither pipe can be drained only after the other closes.
    private int flood() @trusted
    {
        import core.sys.windows.winbase : GetStdHandle, STD_ERROR_HANDLE, STD_OUTPUT_HANDLE, WriteFile;
        import core.thread.osthread : Thread;

        static void fill(uint which)
        {
            auto handle = GetStdHandle(which);
            ubyte[65_536] block = 0;
            foreach (_; 0 .. 160)
            {
                uint written;
                if (!WriteFile(handle, block.ptr, block.length, &written, null) || written != block.length)
                    return;
            }
        }

        auto errors = new Thread(() { fill(STD_ERROR_HANDLE); }).start();
        fill(STD_OUTPUT_HANDLE);
        errors.join();
        return 0;
    }

    // Ignore CTRL_BREAK, start a sleeping grandchild of our own, print both process ids, and wait.
    private int tree() @trusted
    {
        import core.stdc.stdio : fflush, printf, stdout;
        import core.sys.windows.winbase : Sleep;
        import std.file : thisExePath;
        import std.process : Config, spawnProcess;

        static extern (Windows) int ignore(uint) nothrow @nogc
        {
            return 1;
        }

        cast(void) SetConsoleCtrlHandler(&ignore, 1);
        auto grandchild = spawnProcess([thisExePath()], [childVariable: "sleep"], Config.none);
        printf("%u %u\n", processId(), grandchild.osHandle is null ? 0 : grandchildId(grandchild.osHandle));
        fflush(stdout);
        Sleep(30_000);
        return 0;
    }

    private uint grandchildId(void* handle) @trusted
    {
        return GetProcessId(handle);
    }

    // Whether the handle value inherited by number is usable in this process.
    private int probeHandle(string value) @trusted
    {
        import core.stdc.stdio : printf;
        import core.sys.windows.winbase : GetHandleInformation;
        import std.conv : to;

        uint flags;
        if (GetHandleInformation(cast(void*) value.to!size_t, &flags))
            return 3;
        printf("ready");
        return 0;
    }

    private string self()
    {
        import std.file : thisExePath;

        return thisExePath();
    }

    private ProcessOptions childOptions(string mode)
    {
        ProcessOptions options;
        options.environment = [EnvVar(childVariable, mode)];
        return options;
    }

    private bool processAlive(uint pid) @trusted
    {
        import core.sys.windows.winbase : CloseHandle, OpenProcess, WaitForSingleObject;

        enum uint synchronize = 0x0010_0000;
        auto handle = OpenProcess(synchronize, 0, pid);
        if (handle is null)
            return false;
        scope (exit)
            CloseHandle(handle);
        return WaitForSingleObject(handle, 0) != 0;
    }

    @("missing executable and the child's exit 127 are distinct")
    unittest
    {
        Context context;
        const missing = run(context, ["flint-test-nonexistent-command-99817"]);
        assert(missing.error.code == Status.notFound);
        const exited = run(context, [self(), "127"], childOptions("exit"));
        assert(exited.ok && exited.value.code == 127 && !exited.value.signalled);
    }

    @("argv survives Windows command-line quoting and the child sees its directory and environment")
    unittest
    {
        import std.algorithm.searching : canFind;
        import std.file : getcwd, tempDir;
        import std.path : buildNormalizedPath;
        import std.string : splitLines;

        Context context;
        auto options = childOptions("echo");
        options.environment ~= EnvVar("FLINT_TEST", "value with spaces");
        options.workingDirectory = tempDir();
        const tricky = [
            `plain`, `two words`, `quote " inside`, `trailing\`, `back\\"slash`, ``, `tab	x`
        ];
        const result = run(context, [self()] ~ tricky, options);
        assert(result.ok && result.value.code == 0, result.error.message);
        const lines = (cast(const(char)[]) result.value.stdoutBytes).splitLines;
        assert(lines.length == tricky.length + 2);
        foreach (index, argument; tricky)
            assert(lines[index] == "[" ~ argument ~ "]", lines[index]);
        assert(buildNormalizedPath(lines[$ - 2]) == buildNormalizedPath(tempDir()));
        assert(lines[$ - 1] == "value with spaces");
    }

    @("an override replaces an inherited variable whose name differs only in case")
    unittest
    {
        import std.process : environment;

        Context context;
        environment["Flint_Test"] = "inherited";
        scope (exit)
            environment.remove("Flint_Test");
        auto options = childOptions("echo");
        options.environment ~= EnvVar("FLINT_TEST", "override");
        const result = run(context, [self()], options);
        assert(result.ok);
        import std.string : splitLines;

        assert((cast(const(char)[]) result.value.stdoutBytes).splitLines[$ - 1] == "override");
    }

    @("ten MiB on each stream drains without deadlock and capture stops at the combined limit")
    unittest
    {
        Context context;
        auto options = childOptions("flood");
        options.maxCaptureBytes = 32UL << 20;
        const result = run(context, [self()], options);
        assert(result.ok && result.value.code == 0, result.error.message);
        assert(result.value.stdoutBytes.length == 10 << 20 && result.value.stderrBytes.length == 10 << 20);

        options = childOptions("split");
        options.maxCaptureBytes = 6;
        const limited = run(context, [self()], options);
        assert(limited.error.code == Status.resourceExhausted);
        assert(limited.value.stdoutBytes.length + limited.value.stderrBytes.length == 6);
    }

    @("a deadline reports timedOut and a cancelled context starts nothing")
    unittest
    {
        import core.time : MonoTime;

        auto source = CancelSource.create(Context.init, Deadline.afterMillis(200));
        assert(source.ok);
        auto context = source.value.context();
        auto options = childOptions("sleep");
        options.terminateGraceNanos = 100_000_000;
        const started = MonoTime.currTime;
        const timedOut = run(context, [self()], options);
        // CTRL_BREAK ends the child (SIGTERM) when a console is shared, else the job is terminated (SIGKILL).
        assert(timedOut.ok && timedOut.value.timedOut && timedOut.value.signalled);
        assert(timedOut.value.code == 15 || timedOut.value.code == 9);
        assert((MonoTime.currTime - started).total!"msecs" < 10_000);

        auto cancelled = CancelSource.create(Context.init, Deadline.init);
        assert(cancelled.ok);
        cancelled.value.cancel();
        auto stopped = cancelled.value.context();
        assert(run(stopped, [self()], childOptions("exit")).error.code == Status.cancelled);
    }

    @("invalid argv and options are rejected before anything starts")
    unittest
    {
        Context context;
        assert(run(context, ["cmd\0tail"]).error.code == Status.invalidArgument);
        ProcessOptions options;
        options.environment = [EnvVar("BAD=NAME", "x")];
        assert(run(context, [self()], options).error.code == Status.invalidArgument);
        options = ProcessOptions.init;
        options.terminateGraceNanos = -1;
        assert(run(context, [self()], options).error.code == Status.invalidArgument);
    }

    @("forced termination ends the whole job, including a grandchild that ignores CTRL_BREAK")
    unittest
    {
        import std.conv : to;
        import std.string : split, strip;

        auto source = CancelSource.create(Context.init, Deadline.afterMillis(1_500));
        assert(source.ok);
        auto context = source.value.context();
        auto options = childOptions("tree");
        options.terminateGraceNanos = 200_000_000;
        const result = run(context, [self()], options);
        assert(result.ok && result.value.timedOut && result.value.signalled, result.error.message);
        const ids = (cast(const(char)[]) result.value.stdoutBytes).strip.split;
        assert(ids.length == 2);
        assert(!processAlive(ids[0].to!uint) && !processAlive(ids[1].to!uint));
    }

    @("a stalled streaming sink terminates the child")
    unittest
    {
        import core.sys.windows.winbase : Sleep;

        Context context;
        auto options = childOptions("pid");
        options.sinkStallNanos = 100_000_000;
        options.terminateGraceNanos = 50_000_000;
        const stalled = stream(context, [self()], (scope const(ubyte)[]) @trusted { Sleep(1_000); },
                (scope const(ubyte)[]) {}, options);
        assert(stalled.error.code == Status.timedOut, stalled.error.message);
        assert(stalled.value.signalled);
    }

    @("the child inherits only its three standard handles")
    unittest
    {
        import core.sys.windows.winbase : CloseHandle, CreateEventW;
        import std.conv : to;

        auto event = () @trusted { return CreateEventW(null, 1, 0, null); }();
        assert(event !is null);
        scope (exit)
            () @trusted { CloseHandle(event); }();
        () @trusted {
            import core.sys.windows.winbase : SetHandleInformation;

            assert(SetHandleInformation(event, 1, 1)); // HANDLE_FLAG_INHERIT
        }();
        Context context;
        const result = run(context, [self(), (cast(size_t) event).to!string], childOptions("handle"));
        assert(result.ok && result.value.code == 0 && result.value.stdoutBytes == "ready");
    }

    @("with an empty PATH a bare name is not found and a relative path resolves in the working directory")
    unittest
    {
        import std.path : baseName, dirName;

        Context context;
        auto options = childOptions("exit");
        options.inheritEnvironment = false;
        options.environment ~= EnvVar("PATH", "");
        assert(run(context, ["cmd", "/c", "exit 0"], options).error.code == Status.notFound);
        options.workingDirectory = dirName(self());
        const relative = run(context, [`.\` ~ baseName(self()), "5"], options);
        assert(relative.ok && relative.value.code == 5, relative.error.message);
    }

    @("streamed output from both pipes arrives complete and in order")
    unittest
    {
        import std.string : splitLines;

        Context context;
        ubyte[] output, errors;
        const result = stream(context, [self()], (scope const(ubyte)[] bytes) { output ~= bytes; },
                (scope const(ubyte)[] bytes) { errors ~= bytes; }, childOptions("lines"));
        assert(result.ok && result.value.code == 0, result.error.message);
        foreach (text; [output, errors])
        {
            const lines = (cast(const(char)[]) text).splitLines;
            assert(lines.length == 100_000);
            assert(lines[0] == "1" && lines[$ - 1] == "100000");
        }
    }

    // In a console of its own, so the event reaches no other process: subscribe, raise Ctrl+C, and report
    // how many callbacks ran. Surviving to report also shows the handler claimed the event.
    private int interruptChild() @trusted
    {
        import core.atomic : atomicLoad, atomicOp;
        import core.stdc.stdio : printf;
        import core.sys.windows.winbase : Sleep;

        static shared uint seen;
        if (!FreeConsole() || !AllocConsole() || !SetConsoleCtrlHandler(null, 0))
            return 2;
        auto subscription = onInterrupt(() @safe { atomicOp!"+="(seen, 1); });
        if (!subscription.ok || !GenerateConsoleCtrlEvent(0, 0))
            return 3;
        foreach (_; 0 .. 500)
        {
            if (atomicLoad(seen) != 0)
                break;
            Sleep(10);
        }
        Sleep(50);
        const closed = subscription.value.close().code == Status.ok;
        printf("%u", atomicLoad(seen));
        return closed ? 0 : 4;
    }

    @("Ctrl+C reaches subscribers through the console control handler and does not end the process")
    unittest
    {
        Context context;
        const result = run(context, [self()], childOptions("interrupt"));
        assert(result.ok && result.value.code == 0, result.error.message);
        assert(result.value.stdoutBytes == "1");
    }

    private string temporaryRoot()
    {
        import std.conv : to;
        import std.file : mkdirRecurse, tempDir;
        import std.path : buildPath;
        import std.uuid : randomUUID;

        auto path = buildPath(tempDir(), "flint-os-glob-" ~ randomUUID().toString());
        mkdirRecurse(path);
        return path;
    }

    @("glob walks a tree with forward-slash results and stays beneath its root")
    unittest
    {
        import std.algorithm.sorting : sort;
        import std.file : mkdirRecurse, rmdirRecurse, write;
        import std.path : buildPath;

        const root = temporaryRoot();
        scope (exit)
            rmdirRecurse(root);
        mkdirRecurse(buildPath(root, "src", "app"));
        write(buildPath(root, "src", "app", "main.d"), "");
        write(buildPath(root, "src", "lib.d"), "");
        write(buildPath(root, "readme.md"), "");
        const found = glob(root, "**/*.d");
        assert(found.ok, found.error.message);
        auto names = found.value.dup;
        sort(names);
        assert(names == ["src/app/main.d", "src/lib.d"]);
        assert(glob(buildPath(root, "missing"), "*").error.code == Status.notFound);
    }

    @("glob follows a directory junction only when asked and never outside the root")
    unittest
    {
        import std.file : mkdirRecurse, rmdirRecurse, write;
        import std.path : buildPath;
        import std.process : execute;

        const root = temporaryRoot();
        const outside = temporaryRoot();
        scope (exit)
        {
            rmdirRecurse(root);
            rmdirRecurse(outside);
        }
        mkdirRecurse(buildPath(root, "inner"));
        write(buildPath(root, "inner", "a.txt"), "");
        write(buildPath(outside, "secret.txt"), "");
        // Junctions need no privilege, unlike symbolic links.
        assert(execute([
            "cmd", "/c", "mklink", "/J", buildPath(root, "inside"), buildPath(root, "inner")
        ]).status == 0);
        assert(execute(["cmd", "/c", "mklink", "/J", buildPath(root, "escape"), outside]).status == 0);
        GlobOptions options;
        const plain = glob(root, "**/*.txt", options);
        assert(plain.ok && plain.value == ["inner/a.txt"]);
        options.followSymlinks = true;
        auto followed = glob(root, "**/*.txt", options);
        assert(followed.ok, followed.error.message);
        foreach (path; followed.value)
            assert(path == "inner/a.txt" || path == "inside/a.txt", path);
        assert(followed.value.length == 2);
    }
}
