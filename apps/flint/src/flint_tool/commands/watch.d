/// `flint watch`: rebuild and restart, or retest, on every change (ADR-021 section 1, ADR-027).
///
/// The watcher compares a snapshot of the project's inputs (path, size and modification time of everything under
/// src/, test/, config/, native/ and resources/, and flint.toml) four times a second, which works on every
/// platform and costs microseconds for a project. A file modified in the last two seconds is also hashed: a second
/// save of the same size within one tick of the file system's clock keeps its time. A change waits until the files are still for a moment, so an
/// editor's save of several files is one cycle. Builds are incremental: DUB's up-to-date checks, the content-hashed
/// C cache and the resident compile server do the work.
module flint_tool.commands.watch;

import flint_tool.diagnostics.report : Report;
import flint_tool.engine.session : Session;

@safe:

/// What a cycle does.
enum WatchMode : ubyte
{
    /// Build, then (re)start the executable.
    run,
    /// Run the tests.
    test,
    /// Build only.
    build
}

/// One file's identity in a snapshot.
struct Stamp
{
    /// Size in bytes.
    ulong size;
    /// Modification time, in hnsecs.
    long modified;
    /// SHA-256 of the content, for a file modified in the last two seconds or hashed in the previous snapshot;
    /// empty otherwise.
    string digest;
}

/// The project's inputs, by project-relative path. `previous`, the snapshot before, says which files were hashed.
Stamp[string] snapshot(string root, const Stamp[string] previous = null)
{
    import std.file : DirEntry, dirEntries, exists, isDir, SpanMode;
    import std.path : buildPath;
    import std.datetime.systime : Clock;
    import flint_tool.support.files : relativeTo, sha256File;

    // A stamp this recent can be shared by a later write: the file system's clock moves in ticks.
    const recent = Clock.currTime.stdTime - 20_000_000; // two seconds, far wider than any clock tick
    Stamp stampOf(ref DirEntry entry, string path)
    {
        auto stamp = Stamp(entry.size, entry.timeLastModified.stdTime);
        const prior = path in previous;
        const hashedBefore = prior !is null && prior.digest.length && prior.size == stamp.size
            && prior.modified == stamp.modified;
        if (stamp.modified < recent && !hashedBefore)
            return stamp;
        const digest = sha256File(entry.name);
        // Once settled, the hash is dropped again when it matches the one before.
        if (stamp.modified >= recent || digest != prior.digest)
            stamp.digest = digest;
        return stamp;
    }

    Stamp[string] stamps;
    foreach (top; ["src", "test", "config", "native", "resources"])
    {
        const directory = buildPath(root, top);
        if (!exists(directory) || !isDir(directory))
            continue;
        foreach (DirEntry entry; dirEntries(directory, SpanMode.depth, false))
        {
            if (entry.isFile)
            {
                const path = relativeTo(entry.name, root);
                stamps[path] = stampOf(entry, path);
            }
        }
    }
    const manifest = buildPath(root, "flint.toml");
    if (exists(manifest))
    {
        auto entry = DirEntry(manifest);
        stamps["flint.toml"] = stampOf(entry, "flint.toml");
    }
    return stamps;
}

/// Paths added, removed or changed between two snapshots, sorted.
string[] changes(const Stamp[string] before, const Stamp[string] after)
{
    import std.algorithm.sorting : sort;

    string[] changed;
    foreach (path, stamp; after)
    {
        const previous = path in before;
        if (previous is null || previous.size != stamp.size || previous.modified != stamp.modified
                || (previous.digest.length && stamp.digest.length && previous.digest != stamp.digest))
            changed ~= path;
    }
    foreach (path, stamp; before)
    {
        if (path !in after)
            changed ~= path;
    }
    sort(changed);
    return changed;
}

/// `flint watch [--test|--build] [-- program arguments]`.
int commandWatch(ref Session session, string project, WatchMode mode, string[] programArguments)
{
    import core.thread.osthread : Thread;
    import core.time : msecs;
    import flint_tool.commands.output : finishBare;
    import flint_tool.commands.project : Target, TargetKind, locate;
    import flint_tool.support.process : interrupted;

    Report report;
    Target target;
    if (!locate(session, project, target, report))
        return finishBare(session, report, "flint.watch/1");
    if (target.kind == TargetKind.workspace)
    {
        report.error("FLINT-E0004", "flint watch watches a project", "flint watch -C <project>");
        return finishBare(session, report, "flint.watch/1");
    }
    if (mode == WatchMode.run && target.manifest.type != "executable")
        mode = WatchMode.test;
    Watcher watcher = Watcher(session.executable, target.root, mode, programArguments,
            target.manifest.artifactName(), session.json);
    auto current = snapshot(target.root);
    watcher.cycle(session, null);
    while (!interrupted())
    {
        Thread.sleep(250.msecs);
        auto next = snapshot(target.root, current);
        auto changed = changes(current, next);
        if (changed.length == 0)
        {
            watcher.reap(session);
            continue;
        }
        // Let a burst of saves settle into one cycle.
        do
        {
            Thread.sleep(200.msecs);
            current = next;
            next = snapshot(target.root, current);
        }
        while (changes(current, next).length && !interrupted());
        changed ~= changes(current, next);
        current = next;
        watcher.cycle(session, changed);
    }
    watcher.stop();
    return 0;
}

/// The watch loop's state: the cycle count and the running program.
private struct Watcher
{
    string flint;
    string root;
    WatchMode mode;
    string[] arguments;
    string executable;
    bool json;
    long cycles;
    import std.process : Pid;

    Pid program;

    /// Build, test or restart for `changed` files (none on the first cycle).
    void cycle(ref Session session, string[] changed)
    {
        import std.path : buildPath;
        import flint_tool.support.process : Launch, streamed;

        cycles++;
        if (changed.length)
            session.progress("Changed", describe(changed));
        if (mode == WatchMode.run)
            stop();
        const command = mode == WatchMode.test ? "test" : "build";
        Launch launch;
        launch.directory = root;
        int exitCode;
        {
            import flint_tool.sys.posix : writeError;

            const outcome = streamed([flint, command, "-C", root], launch, (scope const(char)[] text) @safe {
                if (!json)
                    writeError(text);
            }, (scope const(char)[] text) @safe {
                if (!json)
                    writeError(text);
            });
            exitCode = outcome.started ? outcome.code : -1;
        }
        const ok = exitCode == 0;
        if (ok && mode == WatchMode.run)
            start(session, buildPath(root, ".flint", "build", "dev", executable));
        else if (!json)
            session.progress(ok ? "Ready" : "Waiting", ok
                    ? "watching for changes" : "fix the errors above; " ~ "watching for changes");
        if (json)
            event(changed, command, ok, exitCode);
    }

    private string describe(scope const string[] changed)
    {
        import std.array : join;
        import std.conv : to;

        if (changed.length <= 3)
            return changed.join(", ");
        const others = changed[3 .. $].length;
        return changed[0 .. 3].join(", ") ~ " and " ~ others.to!string ~ " more";
    }

    private void event(scope const string[] changed, string action, bool ok, int exitCode)
    {
        import flint.serde.owned : serialize;
        import flint_tool.sys.posix : writeOutput;

        static struct Event
        {
            string schema = "flint.watch/1";
            long cycle;
            const(string)[] changed;
            string action;
            bool ok;
            int exit_code;
            bool restarted;
        }

        const record = Event("flint.watch/1", cycles, changed, action, ok, exitCode, program !is null);
        const line = serialize(record);
        if (line.ok)
            writeOutput(line.value ~ "\n");
    }

    private void start(ref Session session, string artifact)
    {
        import std.process : Config, spawnProcess;
        import flint_tool.sys.posix : StandardStream, standardStream;

        // With --json, standard output carries the events: the program writes to standard error instead.
        const output = json ? StandardStream.error : StandardStream.output;
        program = spawnProcess([artifact] ~ arguments, standardStream(StandardStream.input),
                standardStream(output), standardStream(StandardStream.error), null, Config.none, root);
        if (!json)
            session.progress("Running", executable ~ " (restarted on every change; Ctrl+C stops both)");
    }

    /// Collect a program that exited by itself.
    void reap(ref Session session)
    {
        import std.conv : to;
        import std.process : tryWait;

        if (program is null)
            return;
        const status = tryWait(program);
        if (!status.terminated)
            return;
        if (!json)
            session.progress("Exited", executable ~ " with status " ~ status.status.to!string
                    ~ "; watching for changes");
        program = null;
    }

    /// Stop the running program: SIGTERM, then SIGKILL after two seconds.
    void stop()
    {
        import core.thread.osthread : Thread;
        import core.time : msecs;
        import std.process : tryWait, wait;
        import flint_tool.sys.posix : signalProcessGroup;

        if (program is null)
            return;
        enum terminate = 15;
        enum forceKill = 9;
        const pid = program.processID;
        if (!tryWait(program).terminated)
        {
            signalProcessGroup(pid, terminate);
            foreach (_; 0 .. 40)
            {
                if (tryWait(program).terminated)
                    break;
                Thread.sleep(50.msecs);
            }
            if (!tryWait(program).terminated)
            {
                signalProcessGroup(pid, forceKill);
                wait(program);
            }
        }
        program = null;
    }
}

@("a same-size save within one tick of the file system's clock is still a change, and settles")
unittest
{
    import std.conv : to;
    import std.datetime.systime : Clock;
    import std.file : mkdirRecurse, rmdirRecurse, setTimes, tempDir, timeLastModified, write;
    import std.path : buildPath;
    import std.process : thisProcessID;

    const root = buildPath(tempDir, "flint-watch-" ~ thisProcessID.to!string);
    mkdirRecurse(buildPath(root, "src"));
    scope (exit)
        rmdirRecurse(root);
    const file = buildPath(root, "src", "app.d");
    write(file, "module a;\n");
    const first = snapshot(root);
    const stamped = timeLastModified(file);
    // The second save shares the first one's size and modification time, as two saves in one tick do.
    write(file, "module b;\n");
    setTimes(file, Clock.currTime, stamped);
    const second = snapshot(root, first);
    assert(changes(first, second) == ["src/app.d"], "a save that kept its size and time");
    assert(changes(second, snapshot(root, second)).length == 0, "no change without a save");
}
