/// The forked DMD's resident compile server (ADR-016): status, start and stop.
///
/// A server listens on `<dir>/<key>.sock` and holds an flock on `<key>.sock.lock` while alive, where `<dir>`
/// is `$XDG_RUNTIME_DIR/flint-dmd` or `/tmp/flint-dmd-<uid>`. Its command line is
/// `dmd -fork-server=<socket> <key flags...>`.
module flint_tool.toolchain.daemon;

@safe:

/// One compile server.
struct Server
{
    /// Socket path.
    string socket;
    /// Server process, or zero when none was found.
    long pid;
    /// The liveness lock is held.
    bool alive;
    /// The semantic flags in the server's key.
    string[] flags;
    /// The dmd executable the server runs.
    string executable;
}

/// The directory the compile servers use.
string socketDirectory()
{
    import std.conv : to;
    import std.path : buildPath;
    import std.process : environment;
    import core.sys.posix.unistd : getuid;

    const runtime = environment.get("XDG_RUNTIME_DIR", "");
    if (runtime.length)
        return buildPath(runtime, "flint-dmd");
    return "/tmp/flint-dmd-" ~ getuid().to!string;
}

/// Every server socket in the directory, with its process and flags when it is running.
Server[] servers()
{
    import std.algorithm.sorting : sort;
    import std.path : buildPath;
    import flint.os : glob;
    import flint_tool.sys.posix : lockHeld;

    const directory = socketDirectory();
    Server[] found;
    const processes = serverProcesses();
    // Sockets are not regular files, so list the directory through flint.os.glob without a file filter.
    const listed = glob(directory, "*.sock");
    string[] sockets = listed.ok ? listed.value.dup : null;
    sort(sockets);
    foreach (relative; sockets)
    {
        Server server;
        server.socket = buildPath(directory, relative);
        server.alive = lockHeld(server.socket ~ ".lock");
        if (auto process = server.socket in processes)
        {
            server.pid = process.pid;
            server.flags = process.flags.dup;
            server.executable = process.executable;
        }
        found ~= server;
    }
    return found;
}

private struct ServerProcess
{
    long pid;
    string[] flags;
    string executable;
}

/// Running `dmd -fork-server=` processes of this user, by socket.
private ServerProcess[string] serverProcesses()
{
    import std.algorithm.iteration : splitter;
    import std.array : array;
    import std.conv : ConvException, to;
    import std.file : dirEntries, FileException, read, SpanMode;
    import std.path : baseName, buildPath;

    ServerProcess[string] found;
    foreach (entry; listProcesses())
    {
        string text;
        try
            text = cast(string) read(buildPath("/proc", entry, "cmdline")).idup;
        catch (FileException)
            continue;
        auto argv = text.splitter('\0').array;
        if (argv.length < 2 || argv[1].length <= "-fork-server=".length
                || argv[1][0 .. "-fork-server=".length] != "-fork-server=")
            continue;
        const socket = argv[1]["-fork-server=".length .. $];
        string[] flags;
        foreach (flag; argv[2 .. $])
        {
            if (flag.length)
                flags ~= flag;
        }
        try
            found[socket] = ServerProcess(entry.to!long, flags, argv[0].idup);
        catch (ConvException)
            continue;
    }
    return found;
}

private string[] listProcesses()
{
    import std.file : dirEntries, SpanMode;
    import std.path : baseName;

    string[] pids;
    foreach (entry; dirEntries("/proc", SpanMode.shallow, false))
    {
        const name = baseName(entry.name);
        bool numeric = name.length > 0;
        foreach (ch; name)
            numeric = numeric && ch >= '0' && ch <= '9';
        if (numeric)
            pids ~= name;
    }
    return pids;
}

/// Process group of `pid`, from /proc/<pid>/stat, or zero.
long processGroup(long pid)
{
    import std.algorithm.iteration : splitter;
    import std.array : array;
    import std.conv : ConvException, to;
    import std.file : FileException, readText;
    import std.string : lastIndexOf;

    try
    {
        const text = readText("/proc/" ~ pid.to!string ~ "/stat");
        const close = text.lastIndexOf(')');
        if (close < 0)
            return 0;
        auto fields = text[close + 2 .. $].splitter(' ').array;
        // After the command: state, ppid, pgrp.
        return fields.length > 2 ? fields[2].to!long : 0;
    }
    catch (FileException)
        return 0;
    catch (ConvException)
        return 0;
}

/// Stop every live server: SIGTERM its process group, wait, then remove stale socket files.
Server[] stopServers(long waitMillis = 3000, string executablePrefix = null)
{
    import core.sys.posix.signal : SIGKILL, SIGTERM;
    import core.thread : Thread;
    import core.time : msecs;
    import std.file : exists, remove;
    import flint_tool.sys.posix : processAlive, signalProcessGroup;

    auto running = servers();
    if (executablePrefix.length)
    {
        import std.algorithm.iteration : filter;
        import std.algorithm.searching : startsWith;
        import std.array : array;

        running = running.filter!(server => server.executable.startsWith(executablePrefix)).array;
    }
    foreach (ref server; running)
    {
        if (server.pid == 0)
            continue;
        const group = processGroup(server.pid);
        signalProcessGroup(cast(int)(group > 1 ? group : server.pid), SIGTERM);
    }
    long waited;
    foreach (ref server; running)
    {
        while (server.pid && processAlive(cast(int) server.pid) && waited < waitMillis)
        {
            Thread.sleep(20.msecs);
            waited += 20;
        }
        if (server.pid && processAlive(cast(int) server.pid))
            signalProcessGroup(cast(int) server.pid, SIGKILL);
    }
    foreach (server; servers())
    {
        if (server.alive)
            continue;
        foreach (path; [server.socket, server.socket ~ ".lock", server.socket ~ ".log"])
        {
            if (exists(path))
                remove(path);
        }
    }
    return running;
}

/// Start the server for `flags` by compiling a probe module, then wait until it holds its lock.
bool startServer(string dmd, scope const(string)[] flags, out Server started, out string failure,
        long waitMillis = 15_000)
{
    import core.thread : Thread;
    import core.time : msecs;
    import std.file : mkdirRecurse, rmdirRecurse, tempDir, write;
    import std.path : buildPath;
    import std.uuid : randomUUID;
    import flint.os : EnvVar;
    import flint_tool.support.process : Launch, capture;

    if (findServer(flags, started))
        return true;
    // The fork silently compiles without a server when the socket path does not fit sockaddr_un.
    const longest = socketDirectory().length + "/0123456789abcdef.sock".length;
    if (longest >= maximumSocketPath)
    {
        failure = "the socket directory " ~ socketDirectory() ~ " is too long for a Unix socket path (" ~ formatBytes(
                longest) ~ ", at most " ~ formatBytes(maximumSocketPath - 1) ~ ")";
        return false;
    }
    const directory = buildPath(tempDir(), "flint-daemon-" ~ randomUUID().toString());
    mkdirRecurse(directory);
    scope (exit)
        rmdirRecurse(directory);
    const probe = buildPath(directory, "flint_daemon_probe.d");
    write(probe, "module flint_daemon_probe;\n\nvoid probe()\n{\n}\n");
    Launch launch;
    launch.directory = directory;
    launch.environment = [EnvVar("FLINT_DMD_SERVER", "1")];
    const outcome = capture([dmd, "-c", "-of" ~ buildPath(directory, "probe.o")] ~ flags ~ [probe], launch);
    if (!outcome.ok)
    {
        failure = outcome.failure ~ outcome.combined();
        return false;
    }
    for (long waited; waited < waitMillis; waited += 50)
    {
        if (findServer(flags, started))
            return true;
        Thread.sleep(50.msecs);
    }
    failure = "no compile server for these flags appeared within " ~ formatSeconds(waitMillis);
    return false;
}

/// sizeof(sockaddr_un.sun_path) on Linux.
enum maximumSocketPath = 108;

private string formatBytes(size_t count)
{
    import std.conv : to;

    return count.to!string ~ " bytes";
}

private string formatSeconds(long millis)
{
    import std.conv : to;

    return (millis / 1000).to!string ~ " s";
}

/// The live server whose key flags equal `flags`.
bool findServer(scope const(string)[] flags, out Server found)
{
    foreach (server; servers())
    {
        if (server.alive && server.flags == flags)
        {
            found = server;
            return true;
        }
    }
    return false;
}
