/// Building and testing projects and workspace packages through the forked DUB, with receipts.
module flint_tool.engine.builder;

import flint.os : EnvVar;
import flint_tool.engine.receipt : AdditionsRecord, ComponentRecord, EnvironmentRecord,
    NativePackageRecord, OutputRecord, ProfileRecord, Receipt,
    ToolchainRecord, finishSourceIdentity, nativeIdentity, outputRecord, pendingOutputRecord,
    receiptPath, writeReceipt;
import flint_tool.engine.cbuild : CBuild, compileNativeC;
import flint_tool.engine.session : Session;
import flint_tool.diagnostics.report : Report, Severity, at, diagnostic;
import flint_tool.home.policy : ProfileSpec;
import flint_tool.project.layout : CheckSummary, checkProject;
import flint_tool.project.manifest : Manifest, ProfileOverride;
import flint_tool.project.resolve : Resolution;
import flint_tool.toolchain.toolchain : Toolchain, canonicalToolchain, inspect, verifyToolchain;

@safe:

/// What to build and how.
struct BuildRequest
{
    /// Profile name.
    string profile = "dev";
    /// Compiler executable name overriding the profile's, or empty.
    string compiler;
    /// Extra compiler flags from --dflags and the `--` pass-through.
    string[] dflags;
    /// Extra linker flags from --lflags.
    string[] lflags;
    /// Turn toolchain mismatches into errors.
    bool verify;
    /// Require an existing, current flint.lock.
    bool locked;
    /// Rebuild everything.
    bool force;
    /// Build the unittest configuration.
    bool test;
    /// Target name for cross builds (engine/target.d); empty for the host's native builds.
    string target;
    /// Compiler flags the target adds.
    string[] targetDflags;
    /// Embedded C flags the target adds.
    string[] targetCflags;
    /// Instrument with ASan and UBSan (`flint test --sanitize`): the sanitize profile, with embedded C
    /// compiled with the policy's sanitizer flags.
    bool sanitize;
    /// Built for `flint run --debug`, which always keeps debug information (ADR-025 section 4a).
    bool debugger;
    /// Link the pinned platform modules from the platform cache (ADR-030 section 5); `--no-platform-cache` turns
    /// it off and compiles them from source.
    bool platformCache = true;
    /// Link the platform modules statically into a dev build (`--static`). Without it a dev build links them as one
    /// shared object, so an edit relinks only the project (owner decision 2, 2026-11-23).
    bool staticLink;
    /// `--no-debug`: no debug information anywhere (the project, the platform archives, the shared object) and no
    /// symbol table in the link, as the Go comparator's `-ldflags=-s -w` (owner decision 4b27d207). The flags are
    /// part of every platform cache key, so debug and no-debug archives never mix.
    bool noDebug;
}

/// One finished build.
struct BuildOutcome
{
    /// The build succeeded and the artifact exists.
    bool ok;
    /// Absolute artifact path.
    string artifact;
    /// Absolute receipt path.
    string receipt;
    /// The receipt's canonical verdict.
    bool canonical;
    /// Why it is not canonical.
    string[] reasons;
    /// The DUB command.
    string[] command;
    /// DUB's output.
    string output;
    /// Compiler used.
    string compiler;
    /// Checks the fast subset ran.
    CheckSummary checks;
    /// Embedded C.
    CBuild native;
    /// Native packages linked into the artifact.
    imported!"flint_tool.project.native".NativeResolution natives;
    /// The platform cache's archives the artifact links.
    imported!"flint_tool.engine.platformcache".PlatformPlan platform;
    /// The AOT library as a platform-cache entry: linked from the cache when `archive` is set, else stored there
    /// after the build compiled it (engine/platformcache.d `aotLibraryModule`).
    imported!"flint_tool.engine.platformcache".PlatformModule aotLibrary;
    /// The shared platform object a dev build links (`linkShared`), or empty when it links archives.
    string platformShared;
    /// The root package's settings for a direct build (`rootSettingsOf`).
    imported!"flint_tool.engine.direct".RootSettings rootSettings;
    /// Where the build's time went (receipt `phases_ms`).
    imported!"flint_tool.engine.receipt".PhasesRecord phases;
}

/// The profile, flags and DUB home a project build uses, settled before it prepares anything.
private struct BuildSettings
{
    /// The selected profile.
    ProfileSpec spec;
    /// The flags passed as DFLAGS.
    string dflags;
    /// DUB's home for this build.
    string dubHome;
}

/// The project's root directory relative to the current directory, for display.
string display(string path)
{
    import std.file : getcwd;
    import flint_tool.support.files : relativeTo;

    return relativeTo(path, getcwd());
}

/// The resolved profile, or an E0003 diagnostic.
bool selectProfile(ref Session session, string name, out ProfileSpec spec, ref Report report)
{
    import std.array : join;
    import flint_tool.home.policy : profileNames;

    if (session.home.profile(name, spec))
        return true;
    report.error("FLINT-E0003", "unknown profile `" ~ name ~ "`", "choose one of: " ~ profileNames.join(", "));
    return false;
}

/// mold threads for flint's builds when FLINT_LINK_THREADS is unset (link-threads-ab, certified at df11097e): 8,
/// or the host's online CPUs when it has fewer.
string linkThreads() nothrow
{
    import std.conv : to;

    enum preferred = 8;
    long online = preferred;
    version (linux) // mold links only on Linux
    {
        import core.sys.posix.unistd : _SC_NPROCESSORS_ONLN, sysconf;

        online = sysconf(_SC_NPROCESSORS_ONLN);
    }
    const threads = online >= 1 && online < preferred ? online : preferred;
    try
        return threads.to!string;
    catch (Exception)
        return "8";
}

@("linkThreads is 8, or fewer on a host with fewer CPUs")
unittest
{
    import std.conv : to;

    const threads = linkThreads().to!int;
    assert(threads >= 1 && threads <= 8);
}

/// Environment for DUB: flint's own, without DFLAGS, with the pinned toolchain first on PATH.
EnvVar[] buildEnvironment(ref Session session, const ref Toolchain toolchain, const ref ProfileSpec spec,
        string dubHome, string dflags)
{
    import std.path : dirName;
    import std.process : environment;

    import flint_tool.toolchain.host : pathListSeparator;

    EnvVar[] variables;
    foreach (name, value; environment.toAA())
    {
        version (Windows)
        {
            import std.uni : toUpper;

            const key = name.toUpper; // Windows names are case-insensitive: PATH arrives as `Path`.
        }
        else
            const key = name;
        // flint sets the prelude itself, for the project builds that link the platform cache.
        if (key == "DFLAGS" || key == "DUB_HOME" || key == "PATH" || key == "FLINT_DMD_SERVER_PRELUDE")
            continue;
        const disabledServer = name == "FLINT_DMD_SERVER" && !spec.compile_server;
        if (disabledServer || (name == "FLINT_DUB_PIPELINE" && !spec.dub_pipeline))
            continue;
        variables ~= EnvVar(name, value);
    }
    version (Windows)
        const inherited = environment.get("PATH", "");
    else
        const inherited = environment.get("PATH", "/usr/bin:/bin");
    variables ~= EnvVar("PATH",
            dirName(toolchain.dmd.path) ~ pathListSeparator ~ dirName(toolchain.ldc2.path)
            ~ pathListSeparator ~ inherited);
    variables ~= EnvVar("DUB_HOME", dubHome);
    // mold's thread count for the forked DMD's direct link, whose own default is 4. Eight cut gs-rest-service's
    // static edit link from 174 to 136 ms (link-threads-ab, df11097e: 99% interval of the difference -42 to
    // -30 ms) and left shared builds unchanged. mold's output does not depend on it. A set value wins.
    if (environment.get("FLINT_LINK_THREADS", null) is null)
        variables ~= EnvVar("FLINT_LINK_THREADS", linkThreads());
    if (spec.native_sanitize.length)
        variables = sanitizerBuildEnvironment(session, variables);
    if (dflags.length)
        variables ~= EnvVar("DFLAGS", dflags);
    if (!spec.compile_server)
        variables ~= EnvVar("FLINT_DMD_SERVER", "0");
    import flint_tool.toolchain.host : dubPipelineHost;

    // The pipeline writes ELF or COFF archives; macOS needs the Darwin format, so it builds sequentially (ADR-024).
    if (!spec.dub_pipeline || !dubPipelineHost)
        variables ~= EnvVar("FLINT_DUB_PIPELINE", "0");
    return variables;
}

/// Variables that change builds, as recorded in receipts.
EnvironmentRecord[] influentialEnvironment()
{
    import std.algorithm.sorting : sort;
    import std.process : environment;

    EnvironmentRecord[] records;
    string[] names = [
        "FLINT_DMD_SERVER", "FLINT_DUB_PIPELINE", "FLINT_DMD_DIRECT_LINK", "FLINT_LINK_THREADS", "CC",
        "LD"
    ];
    version (Windows)
        names ~= "LINKCMD64"; // Selects DMD's linker: the pinned lld-link instead of link.exe (ADR-026).
    foreach (name; names)
    {
        const value = environment.get(name, null);
        if (value !is null)
            records ~= EnvironmentRecord(name, value);
    }
    sort!((a, b) => a.name < b.name)(records);
    return records;
}

/// Run DUB, streaming its output when verbose and capturing it otherwise.
bool runDub(ref Session session, scope const(string)[] argv, EnvVar[] env, string cwd, out string output,
        bool hideTrace = false)
{
    import flint_tool.support.process : Launch, streamed;
    import flint_tool.sys.posix : writeError;

    Launch launch;
    launch.directory = cwd;
    launch.environment = env;
    launch.inherit = false;
    string collected;
    const stream = session.verbose && !session.json;
    const outcome = streamed(argv, launch, (scope const(char)[] text) @safe {
        collected ~= text;
        if (stream)
            writeError(text);
    }, (scope const(char)[] text) @safe {
        collected ~= text;
        if (stream)
            writeError(hideTrace ? withoutTrace(text.idup) : text);
    });
    output = collected;
    if (!outcome.started)
        output = outcome.failure;
    return outcome.ok;
}

private bool traceRequested(scope const EnvVar[] environment)
{
    foreach (ref variable; environment)
    {
        if (variable.name == "FLINT_DUB_TRACE")
            return true;
    }
    return false;
}

/// `text` with every Flint DUB trace line on a line of its own. DUB's stdout reaches the pipe in 4096-byte blocks
/// while its trace goes to stderr unbuffered, so a trace line can land inside a long `-v` command line; it moves
/// to just before the line it split, which is joined again. `parseReplay` and `dubPhases` read whole lines.
string separateTrace(string text)
{
    import std.algorithm.searching : startsWith;
    import std.string : indexOf;

    enum marker = "[flint-dub ";
    string result, line, traces;
    size_t at = 0;
    while (at < text.length)
    {
        const newline = text.indexOf('\n', at);
        const lineStop = newline < 0 ? text.length : cast(size_t) newline + 1;
        if (text[at .. $].startsWith(marker))
        {
            const trace = text[at .. lineStop];
            const whole = trace[$ - 1] == '\n' ? trace : trace ~ "\n";
            if (line.length)
                traces ~= whole; // it split `line`: it goes before it
            else
                result ~= whole;
            at = lineStop;
            continue;
        }
        const next = text.indexOf(marker, at);
        const stop = next >= 0 && cast(size_t) next < lineStop ? cast(size_t) next : lineStop;
        line ~= text[at .. stop];
        at = stop;
        if (line[$ - 1] == '\n')
        {
            result ~= traces ~ line;
            traces = null;
            line = null;
        }
    }
    return result ~ traces ~ line;
}

@("separateTrace moves a trace line out of the command line it split, and leaves whole lines alone")
unittest
{
    enum split = "[cwd=/p] dmd -c -I/a/sour[flint-dub   54.8ms] compile begin\nce -of/o/x.o x.d\n";
    assert(separateTrace(split) == "[flint-dub   54.8ms] compile begin\n[cwd=/p] dmd -c -I/a/source -of/o/x.o x.d\n");
    enum twice = "head\n[cwd=/p] dmd -c -I/a[flint-dub 1ms] a\n -I/b[flint-dub 2ms] b\n x.d\ntail\n";
    assert(separateTrace(twice) == "head\n[flint-dub 1ms] a\n[flint-dub 2ms] b\n[cwd=/p] dmd -c -I/a -I/b x.d\ntail\n");
    enum whole = "[flint-dub 1ms] a\nline\n[flint-dub 2ms] b\n";
    assert(separateTrace(whole) == whole);
    assert(separateTrace("no trace\n") == "no trace\n");
}

/// `text` without the Flint DUB's `[flint-dub ...]` trace lines.
string withoutTrace(string text)
{
    import std.algorithm.searching : startsWith;
    import std.string : lineSplitter, KeepTerminator;

    string kept;
    foreach (line; text.lineSplitter!(KeepTerminator.yes))
    {
        if (!line.startsWith("[flint-dub "))
            kept ~= line;
    }
    return kept;
}

/// The DUB process's phases from its trace: compile from "pipeline N compile jobs" (or "pipeline planned") to
/// "pipeline compiled", or DUB's own build's first "compile begin" to its last "compile end"; link from
/// "link begin" to "link end"; and the rest of `wall` as plan.
void dubPhases(string output, long wall, ref imported!"flint_tool.engine.receipt".PhasesRecord phases)
{
    import std.algorithm.searching : findSplit, startsWith;
    import std.conv : ConvException, to;
    import std.string : lineSplitter, strip;

    PhaseMarks marks;
    foreach (line; output.lineSplitter)
    {
        if (!line.startsWith("[flint-dub "))
            continue;
        auto parts = line["[flint-dub ".length .. $].findSplit("ms]");
        try
            marks.note(parts[2].strip, parts[0].strip.to!double);
        catch (ConvException)
            continue;
    }
    phases.compile = marks.compileStart >= 0 && marks.compileEnd >= marks.compileStart
        ? cast(long)(marks.compileEnd - marks.compileStart) : -1;
    phases.link = marks.linkStart >= 0 && marks.linkEnd >= marks.linkStart
        ? cast(long)(marks.linkEnd - marks.linkStart) : -1;
    phases.plan = wall - (phases.compile > 0 ? phases.compile : 0) - (phases.link > 0 ? phases.link : 0);
}

/// The trace events that bound DUB's compile and link, in milliseconds since DUB started.
private struct PhaseMarks
{
    double compileStart = -1, compileEnd = -1, linkStart = -1, linkEnd = -1;

    void note(scope const(char)[] event, double at) pure
    {
        import std.algorithm.searching : canFind, startsWith;

        if (event == "pipeline planned" || (event.startsWith("pipeline ") && event.canFind(" compile jobs")))
            compileStart = at;
        else if (event == "pipeline compiled" || event == "compile end")
            compileEnd = at; // DUB's own build traces each compile: the last end
        else if (event == "compile begin" && compileStart < 0)
            compileStart = at; // and the first begin
        else if (event == "link begin")
            linkStart = at;
        else if (event == "link end")
            linkEnd = at;
    }
}

/// The compile server's platform prelude for this build, or null. The server preloads the platform modules for
/// dev builds only (coordinator, 2026-11-23): a test build compiles with -unittest, which the prelude's switches
/// would not match anyway. The project build and the AOT step's extraction compile share it.
private string serverPrelude(const ref BuildRequest request, const ref ProfileSpec spec, const ref BuildOutcome result)
{
    if (result.platform.active && spec.compile_server && !request.test && request.profile == "dev")
        return result.platform.prelude;
    return null;
}

/// The platform modules' `-version=` flags when the build links the platform, as its prelude lists them; the AOT
/// step's extraction compile passes them whether or not the compile server serves it.
private string[] platformVersions(const ref BuildOutcome result)
{
    import std.file : exists, readText;
    import flint_tool.engine.aot.step : preludeVersions;

    if (!result.platform.active || !result.platform.prelude.length || !exists(result.platform.prelude))
        return null;
    return preludeVersions(readText(result.platform.prelude));
}

/// A project build's additions to its environment. Returns whether the user asked for DUB's trace.
private bool projectEnvironment(const ref BuildRequest request, const ref ProfileSpec spec,
        const ref BuildOutcome result, ref EnvVar[] environment)
{
    const prelude = serverPrelude(request, spec, result);
    if (prelude.length)
        environment ~= EnvVar("FLINT_DMD_SERVER_PRELUDE", prelude);
    // The Flint DUB reports its phases with FLINT_DUB_TRACE (toolchain/README.md); flint reads them for the
    // receipt and keeps them out of what it shows.
    const userTrace = traceRequested(environment);
    if (!userTrace)
        environment ~= EnvVar("FLINT_DUB_TRACE", "1");
    return userTrace;
}

/// The root package's settings as DUB would describe them, from the recipe flint wrote and the platform's
/// description: the recipe's flags, `Have_<package>` for the project and every package of its closure, the
/// closure's versions, import and string import paths, and every D source the recipe names. A direct build then
/// needs no `dub describe`, which a cold build would otherwise run.
private imported!"flint_tool.engine.direct".RootSettings rootSettingsOf(const ref Manifest manifest,
        const ref Resolution resolution,
        const ref imported!"flint_tool.engine.recipe".RecipeExtras extras,
        const ref imported!"flint_tool.engine.platformcache".PlatformPlan plan)
{
    import std.array : replace;
    import std.path : absolutePath, buildNormalizedPath, buildPath;
    import flint_tool.engine.direct : RootSettings;
    import flint_tool.engine.recipe : hasApplicationConfig, recipeDirectory;
    import flint_tool.support.files : findFiles;

    static string have(string name)
    {
        return "Have_" ~ name.replace(":", "_").replace("-", "_");
    }

    RootSettings settings;
    settings.dflags = ["-preview=dip1000"] ~ extras.diagnosticFlags.dup ~ extras.platformDflags.dup;
    settings.versions = [have(manifest.name)];
    const root = buildNormalizedPath(absolutePath(manifest.root));
    const recipe = buildPath(root, recipeDirectory);
    settings.importPaths = [buildPath(root, "src") ~ "/"];
    if (extras.aot)
        settings.importPaths ~= buildPath(root, ".flint", "generated", "aot") ~ "/";
    if (hasApplicationConfig(root))
        settings.stringImportPaths ~= buildPath(root, "config") ~ "/";
    foreach (relative; findFiles(buildPath(root, "src"), "**/*.d"))
        settings.sources ~= buildPath(root, "src", relative);
    if (extras.scanned)
        settings.sources ~= buildNormalizedPath(recipe, "../scan/flint_scan.d");
    foreach (relative; extras.aotOwn.length ? extras.aotOwn ~ "../aot-library/flint_aot_library.d" : null)
        settings.sources ~= buildNormalizedPath(recipe, relative);
    if (extras.aot && extras.aotOwn.length == 0)
    {
        foreach (relative; findFiles(buildPath(root, ".flint", "generated", "aot"), "**/*.d"))
            settings.sources ~= buildPath(root, ".flint", "generated", "aot", relative);
    }
    settings.lflags = extras.platformLflags.dup;
    addClosure(settings, resolution.direct, plan);
    return settings;
}

/// For a shared dev build, the root settings a direct build compiles with (`rootSettingsOf`).
private void noteRootSettings(const ref Manifest manifest, const ref Resolution resolution,
        const ref imported!"flint_tool.engine.recipe".RecipeExtras extras, ref BuildOutcome result)
{
    if (result.platform.active && result.platform.inputs.sharedLink)
        result.rootSettings = rootSettingsOf(manifest, resolution, extras, result.platform);
}

/// The closure's versions and import paths, as DUB walks it: the root's direct dependencies and theirs.
private void addClosure(ref imported!"flint_tool.engine.direct".RootSettings settings,
        scope const string[] direct, const ref imported!"flint_tool.engine.platformcache".PlatformPlan plan)
{
    import std.algorithm.searching : canFind;
    import std.array : replace;

    static string have(string name)
    {
        return "Have_" ~ name.replace(":", "_").replace("-", "_");
    }

    bool[string] seen;
    string[] pending = direct.dup;
    while (pending.length)
    {
        const name = pending[0];
        pending = pending[1 .. $];
        if (name in seen)
            continue;
        seen[name] = true;
        settings.versions ~= have(name);
        foreach (ref item; plan.modules)
        {
            if (item.name != name)
                continue;
            foreach (identifier; item.versions)
                if (!settings.versions.canFind(identifier))
                    settings.versions ~= identifier;
            foreach (path; item.importPaths)
                settings.importPaths ~= path ~ "/";
            foreach (path; item.stringImportPaths)
                settings.stringImportPaths ~= path ~ "/";
            pending ~= item.dependencies.dup;
        }
    }
}

/// Build through DUB, reading its phases from the Flint DUB's trace.
private bool buildWithDub(ref Session session, scope const(string)[] command, EnvVar[] environment,
        string root, bool hideTrace, ref BuildOutcome result)
{
    import core.time : MonoTime;

    const start = MonoTime.currTime;
    const built = runDub(session, command, environment, root, result.output, hideTrace);
    result.output = separateTrace(result.output);
    dubPhases(result.output, (MonoTime.currTime - start).total!"msecs", result.phases);
    if (hideTrace)
        result.output = withoutTrace(result.output);
    return built;
}

/// Whether flint may build the project itself, without DUB (engine/direct.d): a DMD dev build that links the
/// platform cache (the shared object, or with --static the archives), with no dependency DUB would build (only core packages, and the AOT library, if any,
/// from the platform cache) and no embedded C. `FLINT_DIRECT_BUILD=0` builds through DUB.
private bool directEligible(const ref BuildRequest request, const ref Resolution graph, const ref BuildOutcome result)
{
    import std.process : environment;

    // A DMD dev build that links the platform cache: the shared object, or with --static its archives.
    if (environment.get("FLINT_DIRECT_BUILD", "") == "0" || request.test || !result.platform.active
            || request.profile != "dev" || result.compiler != "dmd")
        return false;
    if (result.aotLibrary.key.length && result.aotLibrary.archive.length == 0)
        return false; // DUB builds the AOT library this time
    if (result.native.objects.length)
        return false;
    foreach (ref item; graph.packages)
    {
        if (item.kind != "core")
            return false;
    }
    return true;
}

private imported!"flint_tool.engine.direct".DirectBuild directBuildOf(const ref Manifest manifest,
        const ref Toolchain toolchain, string compiler, const ref BuildRequest request,
        EnvVar[] environment, string dflags, const ref BuildOutcome result)
{
    import std.path : buildPath;
    import flint_tool.engine.direct : DirectBuild, copySettings;
    import flint_tool.engine.recipe : recipeDirectory;

    DirectBuild build;
    build.compiler = toolchain.component(compiler).path;
    build.compilerSha256 = toolchain.component(compiler).sha256;
    build.dub = toolchain.dub.path;
    build.dubSha256 = toolchain.dub.sha256;
    build.root = manifest.root;
    build.recipeDirectory = buildPath(manifest.root, recipeDirectory);
    build.configuration = request.profile;
    build.artifact = artifactPath(manifest, request);
    build.environment = environment;
    build.dflags = dflags;
    build.settings = copySettings(result.rootSettings);
    build.computed = result.rootSettings.sources.length > 0;
    return build;
}

/// Build without DUB when the project allows it: a shared dev build compiles and links itself; a static one
/// replays DUB's recorded commands. Otherwise build with DUB, and for a static dev build record what it ran. DUB
/// compiles a static dev build one root module per compiler process (`--build-mode=singleFile`, in parallel), so
/// a replay recompiles only the modules an edit can affect: separate compilation's template emission is sound
/// only when every object comes from a compile of its own module.
private bool buildEligible(ref Session session, const imported!"flint_tool.engine.direct".DirectBuild build,
        scope const(string)[] command, EnvVar[] environment, bool hideTrace, ref BuildOutcome result)
{
    import flint_tool.engine.direct : DirectResult, directBuild, recordReplay, recordReplayModules, replayBuild;

    const shared_ = result.platformShared.length > 0;
    const direct = shared_ ? directBuild(session, build, result.output, result.phases) : replayBuild(session,
            build, result.output, result.phases);
    if (direct != DirectResult.unavailable)
        return direct == DirectResult.built;
    import flint_tool.support.files : fileClockNow, stampBuilt;

    // Before DUB reads a source: an edit while it builds is then newer than both the artifact and the record.
    const started = fileClockNow(build.recipeDirectory);
    const built = buildWithDub(session, shared_ ? command : command ~ [
        "-v", "--build-mode=singleFile", "--parallel"
    ], environment, build.root, hideTrace, result);
    if (built && !shared_)
    {
        recordReplay(build, result.output);
        recordReplayModules(build, started);
    }
    if (built)
        stampBuilt(build.artifact, started);
    return built;
}

/// Close the phases: the total since the session opened, and flint's own share of it.
private void finishPhases(ref Session session, ref imported!"flint_tool.engine.receipt".PhasesRecord phases)
{
    import core.time : MonoTime;

    phases.total = (MonoTime.currTime - session.started).total!"msecs";
    phases.flint = phases.total - phases.aot - phases.plan - (phases.compile > 0 ? phases.compile
            : 0) - (phases.link > 0 ? phases.link : 0);
}

/// The tail of tool output worth showing in a diagnostic.
string tail(string text, size_t lines = 40)
{
    import std.string : lineSplitter, strip;
    import std.array : array, join;

    auto all = text.lineSplitter.array;
    if (all.length > lines)
        all = all[$ - lines .. $];
    return all.join("\n").strip.idup;
}

/// The sanitize profile links through `-gcc=clang` against the sanitizer-aware LDC runtime: the pinned clang
/// goes first on PATH and the runtime's directory on LIBRARY_PATH, as tools/ci.py's sanitizer lane does.
private EnvVar[] sanitizerBuildEnvironment(ref Session session, EnvVar[] variables)
{
    import std.path : buildPath;
    import std.process : environment;
    import flint_tool.toolchain.toolchain : toolchainDirectory;

    const directory = toolchainDirectory(session.home);
    EnvVar[] kept;
    foreach (variable; variables)
    {
        if (variable.name == "PATH")
            kept ~= EnvVar("PATH", buildPath(directory, llvmDirectory, "bin") ~ ":" ~ variable.value);
        else if (variable.name != "LIBRARY_PATH")
            kept ~= variable;
    }
    const existing = environment.get("LIBRARY_PATH", "");
    kept ~= EnvVar("LIBRARY_PATH", buildPath(directory, sanitizerRuntime,
            "lib") ~ (existing.length ? ":" ~ existing : ""));
    return kept ~ sanitizerRunEnvironment(session);
}

/// The pinned LLVM release directory under the toolchain (tools/install_toolchains.py LLVM_ROOT).
enum llvmDirectory = "LLVM-22.1.8-Linux-X64";
/// The sanitizer-aware LDC runtime directory (tools/install_toolchains.py SANITIZER_RUNTIME).
enum sanitizerRuntime = "ldc-1.43.0-sanitizer-runtime";

/// Sanitizer options of instrumented test runs, as tools/ci.py sets them: leaks detected, the first error
/// fatal, ASan fake stacks scanned by the sanitizer-aware runtime's GC.
EnvVar[] sanitizerRunEnvironment(ref Session session)
{
    import std.path : buildPath;
    import flint_tool.toolchain.toolchain : toolchainDirectory;

    return [
        EnvVar("ASAN_OPTIONS", "detect_leaks=1:abort_on_error=1:detect_stack_use_after_return=1"),
        EnvVar("UBSAN_OPTIONS", "halt_on_error=1:print_stacktrace=1"),
        EnvVar("ASAN_SYMBOLIZER_PATH", buildPath(toolchainDirectory(session.home), llvmDirectory,
                "bin", "llvm-symbolizer"))
    ];
}

/// Whether the sanitizer toolchain a `--sanitize` build needs is installed; FLINT-E0816 otherwise.
bool sanitizerToolchain(ref Session session, ref Report report)
{
    import std.file : exists;
    import std.path : buildPath;
    import flint_tool.toolchain.toolchain : toolchainDirectory;

    const directory = toolchainDirectory(session.home);
    const clang = buildPath(directory, llvmDirectory, "bin", "clang");
    const runtime = buildPath(directory, sanitizerRuntime, "flint-sanitizer-runtime.json");
    if (exists(clang) && exists(runtime))
        return true;
    report.error("FLINT-E0816", "the sanitizer toolchain is not installed (" ~ (exists(clang)
            ? runtime : clang) ~ ")", "flint toolchain install --sanitizers");
    return false;
}

/// Everything before DUB runs: lock, toolchain, fast checks, embedded C and the generated recipes.
private bool prepareBuild(ref Session session, const ref Manifest manifest, const ref Resolution resolution,
        const ref BuildRequest request, const ref BuildSettings settings, out Toolchain toolchain,
        ref BuildOutcome result, ref Report report)
{
    import flint_tool.engine.aot.step : runAotStep;

    if (!prepareLock(session, manifest, resolution, request.locked, report))
        return false;
    if (!usableToolchain(session, result.compiler, request.verify, toolchain, report))
        return false;
    if (request.sanitize && !sanitizerToolchain(session, report))
        return false;
    result.checks = checkProject(session.home, manifest, resolution, false, report);
    foreach (waiver; result.checks.unchecked)
        session.progress("Unchecked", waiver);
    if (!report.ok || !prepareNatives(session, manifest, resolution, request, result.natives, report))
        return false;
    string[] cflags = request.targetCflags.dup;
    foreach (directory; result.natives.includeDirs)
        cflags ~= "-I" ~ directory;
    if (!compileNativeC(session, manifest, request.sanitize, cflags, result.native, report))
        return false;
    import core.time : MonoTime;

    // The platform comes first so the AOT step's extraction compile is served with its prelude (m7, 2026-11-24):
    // planPlatform reads no AOT output.
    if (!preparePlatform(session, manifest, resolution, request, settings, toolchain, result, report))
        return false;
    const aotStart = MonoTime.currTime;
    const aot = runAotStep(session, manifest, resolution, toolchain, result.compiler, report,
            serverPrelude(request, settings.spec, result), platformVersions(result));
    result.phases.aot = (MonoTime.currTime - aotStart).total!"msecs";
    if (!aot.ok)
        return false;
    return writeRecipes(session, manifest, resolution, result, condensedDiagnostics(session,
            toolchain, result.compiler), aot.active, report);
}

/// Link the platform modules from the platform cache when the build allows it (engine/platformcache.d).
private bool preparePlatform(ref Session session, const ref Manifest manifest, const ref Resolution resolution,
        const ref BuildRequest request, const ref BuildSettings settings, const ref Toolchain toolchain,
        ref BuildOutcome result, ref Report report)
{
    import flint_tool.engine.platformcache : PlatformInputs, planPlatform, platformCacheAllowed;
    import flint_tool.engine.target : hostTarget;

    if (!platformCacheAllowed(request.platformCache, request.sanitize, request.target))
        return true;
    PlatformInputs inputs;
    inputs.dub = toolchain.dub.path;
    inputs.compiler = toolchain.component(result.compiler).path;
    inputs.compilerSha256 = toolchain.component(result.compiler).sha256;
    inputs.dubSha256 = toolchain.dub.sha256;
    inputs.release = session.home.platform.release;
    inputs.dflags = settings.dflags;
    inputs.target = hostTarget();
    inputs.environment = buildEnvironment(session, toolchain, settings.spec, settings.dubHome, settings.dflags);
    inputs.cache = platformCacheRoot(session);
    inputs.workingDirectory = session.home.root;
    // Owner decision 2 (2026-11-23): a DMD dev build links the platform as one shared object; --static, tests,
    // release and size builds link its archives.
    inputs.sharedLink = request.profile == "dev" && !request.test && !request.staticLink && result.compiler == "dmd";
    return planPlatform(session, manifest.root, resolution, inputs, result.platform, report);
}

/// DUB's home for a project build: `<project>/.flint/dub` (`dub-<target>` for a cross target). On Windows it is
/// `<cache>/dub/<12 hex of the project path>` instead. DUB's build cache nests the package and configuration under
/// it, and a project inside a platform checkout (`.flint/platform/<repo>-<commit>/...`) went past MAX_PATH there.
private string projectDubHome(ref Session session, string root, string target)
{
    import std.path : buildPath;

    const name = target.length ? "dub-" ~ target : "dub";
    version (Windows)
    {
        import std.path : absolutePath, buildNormalizedPath;
        import flint_tool.support.files : sha256Hex;

        const project = buildNormalizedPath(absolutePath(root));
        return buildPath(platformCacheRoot(session), name, sha256Hex(cast(const(ubyte)[]) project)[0 .. 12]);
    }
    else
        return buildPath(root, ".flint", name);
}

/// The cache directory: FLINT_CACHE, else `<home>/.flint/cache` (as project/remote.d's Fetcher).
private string platformCacheRoot(ref Session session)
{
    import std.path : absolutePath, buildNormalizedPath, buildPath;
    import std.process : environment;

    const relocated = environment.get("FLINT_CACHE", "");
    return relocated.length
        ? buildNormalizedPath(absolutePath(relocated)) : buildPath(session.home.root, ".flint", "cache");
}

/// Write or remove `.flint/generated/scan/flint_scan.d`; true when the project has an `@FlintApplication`.
private bool writeScan(ref Session session, const ref Manifest manifest, const ref Resolution resolution)
{
    import std.file : exists, remove;
    import std.path : buildPath;
    import flint_tool.engine.scan : renderScan, scanDirectory, scanProject;
    import flint_tool.support.files : writeIfChanged;

    const path = buildPath(manifest.root, scanDirectory, "flint_scan.d");
    const scan = scanProject(manifest);
    const text = renderScan(session.home, resolution, scan);
    if (text.length == 0)
    {
        if (exists(path))
            remove(path);
        return false;
    }
    writeIfChanged(path, text);
    return true;
}

/// `-verror-hide` for the DMD fork (ADR-027 section 5): an error raised inside druntime, Phobos or a Flint package
/// is reported at the user's line that caused it. Not with `--verbose`, LDC, or a fork that was not built from this
/// checkout's patch, which would not know the switch.
string[] condensedDiagnostics(ref Session session, const ref Toolchain toolchain, string compiler)
{
    import std.algorithm.searching : canFind;
    import std.path : buildNormalizedPath, buildPath, dirName, dirSeparator;
    import flint_tool.check.structural : realPath;
    import flint_tool.toolchain.host : dmdForkHost;

    if (!dmdForkHost || compiler != "dmd" || session.verbose || !toolchain.fork.verified)
        return null;
    string[] flags = [
        "-verror-hide=" ~ buildNormalizedPath(session.home.root, "packages") ~ dirSeparator
    ];
    // dmd.conf names druntime and Phobos as `<bin>/../../src`, and DMD reports their files with that spelling,
    // where <bin> is the directory DUB invoked it from, or the resolved one.
    const bin = dirName(toolchain.component("dmd").path);
    foreach (directory; [bin, realPath(bin)])
    {
        const spellings = [
            buildPath(directory, "..", "..", "src"), buildNormalizedPath(directory, "..", "..", "src")
        ];
        foreach (spelling; spellings)
        {
            const flag = "-verror-hide=" ~ spelling ~ dirSeparator;
            if (!flags.canFind(flag))
                flags ~= flag;
        }
    }
    return flags;
}

/// Resolve the native packages for this build's target and variant, and bundle the `bundled` ones.
private bool prepareNatives(ref Session session, const ref Manifest manifest, const ref Resolution resolution,
        const ref BuildRequest request,
        out imported!"flint_tool.project.native".NativeResolution natives, ref Report report)
{
    import std.path : buildPath;
    import flint_tool.engine.target : hostTarget;
    import flint_tool.project.native : bundle;
    import flint_tool.project.resolve : nativesFor;
    import flint_tool.toolchain.toolchain : toolchainDirectory;

    const target = request.target.length ? request.target : hostTarget();
    if (!nativesFor(session.home, manifest, resolution, target, request.sanitize, natives, report))
        return false;
    foreach (reason; natives.nonPortable)
        session.progress("Non-portable", reason);
    if (natives.packages.length)
        session.progress("Native", countNatives(natives) ~ " for " ~ target);
    const clang = buildPath(toolchainDirectory(session.home), "LLVM-22.1.8-Linux-X64", "bin", "clang");
    return bundle(natives, clang, buildPath(manifest.root, ".flint", "build", "lib"), report);
}

private string countNatives(const ref imported!"flint_tool.project.native".NativeResolution natives)
{
    import std.array : join;

    string[] names;
    foreach (ref package_; natives.packages)
        names ~= package_.name ~ " " ~ package_.version_ ~ (package_.linkage == "static"
                ? "" : " (" ~ package_.linkage ~ ")");
    return names.join(", ");
}

/// Whether the checkout's native DUB blocks are this build's. `tools/native_build.py --retarget-dub` points them at
/// another target's install (a musl package from a glibc host) and leaves `.native/dub-target` naming it; a build
/// for any other target would then link that target's C libraries, so it refuses.
private bool nativeBlocksMatch(string home, string target, ref Report report)
{
    import std.path : buildPath;
    import std.string : strip;
    import flint_tool.engine.target : hostTarget;
    import flint_tool.support.files : readIfPresent;

    const marked = readIfPresent(buildPath(home, ".native", "dub-target")).strip;
    const building = target.length ? target : hostTarget();
    if (marked.length == 0 || marked == building)
        return true;
    report.error("FLINT-E0713",
            "this checkout's native packages are retargeted to " ~ marked ~ ", and this build is for " ~ building,
            "python3 tools/native_build.py --target " ~ building ~ " --retarget-dub");
    return false;
}

/// Build a project with a profile: lock, toolchain, fast checks, recipe, DUB, receipt.
bool buildProject(ref Session session, const ref Manifest manifest, const ref Resolution resolution,
        BuildRequest request, out BuildOutcome result, ref Report report)
{
    import std.array : join;
    import std.path : buildPath;
    import flint_tool.engine.recipe : recipeDirectory;

    if (!nativeBlocksMatch(session.home.root, request.target, report))
        return false;
    ProfileSpec spec;
    if (!selectProfile(session, request.profile, spec, report))
        return false;
    {
        import flint_tool.engine.receipt : startSourceIdentity;

        // The receipt's git commands run while the project builds.
        startSourceIdentity(manifest.root, session.pendingSource);
    }
    const compiler = request.compiler.length ? request.compiler : spec.compiler;
    result.compiler = compiler;
    const flags = composeFlags(spec, manifest.overrideFor(request.profile), request);
    const dubHome = projectDubHome(session, manifest.root, request.target);
    const settings = BuildSettings(spec, flags.dflags.join(" "), dubHome);
    Toolchain toolchain;
    if (!prepareBuild(session, manifest, resolution, request, settings, toolchain, result, report))
        return false;

    const command = projectCommand(toolchain, compiler, manifest.root, request);
    result.command = command.dup;
    auto environment = buildEnvironment(session, toolchain, spec, dubHome, settings.dflags);
    const userTrace = projectEnvironment(request, spec, result, environment);
    const label = request.test ? "test" : request.profile;
    session.progress(request.test ? "Compiling" : "Building",
            manifest.name ~ " " ~ manifest.version_ ~ " (" ~ label ~ ", " ~ compiler ~ ")");
    const built = directEligible(request, resolution, result) ? buildEligible(session,
            directBuildOf(manifest, toolchain,
                compiler, request, environment, settings.dflags, result), command, environment, !userTrace, result)
        : buildWithDub(session, command, environment, manifest.root, !userTrace, result);
    if (!built)
    {
        report.error("FLINT-E0701", request.test ? "the test build failed" : "the build failed",
                "the compiler output follows:\n" ~ tail(result.output));
        return false;
    }
    result.artifact = artifactPath(manifest, request);
    if (!artifactExists(result.artifact, report))
        return false;
    // The static-data map (docs/spring/phase1/gc.md, 3d), on every build path, before the receipt hashes the file.
    {
        import flint_tool.support.gcmap : attachStaticMap, auditsStaticData;

        attachStaticMap(result.artifact, auditsStaticData(request.profile));
    }
    storeAotArchive(session, result);
    auto receipt = projectReceipt(session, manifest, toolchain, request, flags, result);
    finishPhases(session, result.phases); // after the receipt's hashing, which is flint's work too
    receipt.phases_ms = result.phases;
    result.receipt = receiptPath(result.artifact);
    writeReceipt(result.receipt, receipt);
    result.canonical = receipt.canonical;
    result.reasons = receipt.non_canonical_reasons;
    result.ok = true;
    return true;
}

private string[] projectCommand(const ref Toolchain toolchain, string compiler, string root,
        const ref BuildRequest request)
{
    import std.path : buildPath;
    import flint_tool.engine.recipe : recipeDirectory;

    string[] command = [
        toolchain.dub.path, "build", "--root=" ~ buildPath(root, recipeDirectory),
        "--config=" ~ (request.test ? "unittest" : request.profile),
        "--compiler=" ~ toolchain.component(compiler).path, "--build=plain", "--skip-registry=all"
    ];
    if (request.force)
        command ~= "--force";
    return command;
}

/// Inspect and verify the compiler and DUB; false when a build cannot proceed.
private bool usableToolchain(ref Session session, string compiler, bool verify, out Toolchain toolchain,
        ref Report report)
{
    toolchain = inspect(session.home, [compiler, "dub"], true);
    verifyToolchain(toolchain, [compiler, "dub"], verify ? Severity.error : Severity.warning, report);
    return toolchain.component(compiler).present && toolchain.dub.present && !(verify && !report.ok);
}

/// The flags a build passes: profile flags (for plain profiles), additions, and linker flags as -L.
struct Flags
{
    /// Compiler flags, including -L linker flags.
    string[] dflags;
    /// Linker flags.
    string[] lflags;
    /// Additions from flint.toml.
    string[] manifestDflags;
    /// Additions from flint.toml.
    string[] manifestLflags;
    /// `[profile.dev] debug = false` removed the debug information flags.
    bool noDebug;
}

private Flags composeFlags(const ref ProfileSpec spec, ProfileOverride additions, const ref BuildRequest request)
{
    import flint_tool.engine.target : linksElf, linksGlibcPie;

    Flags flags;
    // A "plain" profile's flags are the complete flag set (through DFLAGS). Other build types, such as the
    // test profile's, apply only to the project: its unittest configuration adds -unittest, so dependencies
    // are not rebuilt with their own unittests.
    if (spec.build_type == "plain")
        flags.dflags = spec.dflags.dup;
    // A project's unittest configuration adds -unittest itself; the sanitize profile's own -unittest would
    // also compile and run every dependency's unittests inside the project's test binary.
    if (request.test && request.sanitize)
    {
        string[] kept;
        foreach (flag; flags.dflags)
        {
            if (flag != "-unittest")
                kept ~= flag;
        }
        flags.dflags = kept;
    }
    flags.dflags ~= request.targetDflags ~ additions.dflags ~ request.dflags;
    flags.noDebug = (additions.noDebug || request.noDebug) && !request.debugger;
    if (flags.noDebug)
        flags.dflags = withoutDebugInformation(flags.dflags);
    flags.lflags = spec.lflags.dup;
    if (linksGlibcPie(request.target))
        flags.lflags ~= spec.glibc_lflags;
    if (linksElf(request.target))
        flags.lflags ~= spec.elf_lflags;
    flags.lflags ~= additions.lflags ~ request.lflags;
    if (request.noDebug && !request.debugger)
        flags.lflags ~= "-s"; // no symbol table either, as Go's -s
    foreach (flag; flags.lflags)
        flags.dflags ~= "-L" ~ flag;
    flags.manifestDflags = additions.dflags;
    flags.manifestLflags = additions.lflags;
    return flags;
}

/// `flags` without the compiler flags that emit debug information (`[profile.dev] debug = false`).
string[] withoutDebugInformation(scope const(string)[] flags)
{
    import std.algorithm.searching : canFind, startsWith;

    static immutable debugFlags = ["-g", "-gf", "-gc", "-gline-tables-only"];
    string[] kept;
    foreach (flag; flags)
    {
        if (!debugFlags.canFind(flag) && !flag.startsWith("-gdwarf"))
            kept ~= flag;
    }
    return kept;
}

private bool prepareLock(ref Session session, const ref Manifest manifest, const ref Resolution resolution,
        bool locked, ref Report report)
{
    import std.path : buildPath;
    import flint_tool.project.lock : LockState, checkLock, lockName, renderLock, writeLock;

    const expected = renderLock(session.home, manifest, resolution);
    if (checkLock(manifest.root, expected, locked, report) == LockState.missing && !locked)
    {
        writeLock(manifest.root, expected);
        session.progress("Locked", "wrote " ~ display(buildPath(manifest.root, lockName)));
    }
    return report.ok;
}

private bool writeRecipes(ref Session session, const ref Manifest manifest, const ref Resolution resolution,
        ref BuildOutcome result, string[] diagnosticFlags, bool aot, ref Report report)
{
    import std.path : buildPath;
    import flint_tool.engine.cbuild : NativeCPolicy, loadNativeCPolicy;
    import flint_tool.engine.platformcache : linkGroup, platformObjects;
    import flint_tool.engine.recipe : RecipeExtras, dependencyRecipeDirectory, recipeDirectory,
        renderDependencyRecipe, renderRecipe;
    import flint_tool.support.files : writeIfChanged;

    RecipeExtras extras;
    extras.objects = result.native.objects.dup;
    extras.nativeFlags = result.natives.linkFlags.dup;
    extras.diagnosticFlags = diagnosticFlags;
    extras.scanned = writeScan(session, manifest, resolution);
    extras.aot = aot;
    if (aot)
    {
        import flint_tool.engine.recipe : aotLibraryDirectory, renderAotLibraryLink, renderAotLibraryRecipe;

        string[] library, modules;
        splitAotModules(manifest.root, extras.aotOwn, library, modules);
        if (library.length)
        {
            writeIfChanged(buildPath(manifest.root, aotLibraryDirectory, "dub.sdl"),
                    renderAotLibraryRecipe(session.home, resolution, library, diagnosticFlags, result.platform.active));
            writeIfChanged(buildPath(manifest.root, aotLibraryDirectory, "flint_aot_library.d"),
                    renderAotLibraryLink(modules));
            if (result.platform.active)
                extras.aotArchive = planAotArchive(manifest.root, library, diagnosticFlags, result);
        }
        else
            extras.aotOwn = null;
    }
    extras.platform = result.platform.active;
    extras.platformLflags = linkGroup(extras.aotArchive.length
            ? result.platform.archives ~ extras.aotArchive : result.platform.archives) ~ platformObjects(
            result.platform.modules);
    if (result.platform.active && result.platform.inputs.sharedLink && !linkShared(result, extras, report))
        return false;
    if (result.native.objects.length)
    {
        NativeCPolicy policy;
        string digest;
        if (!loadNativeCPolicy(session.home, policy, digest, report))
            return false;
        extras.linkHardening = policy.link_hardening;
    }
    writeIfChanged(buildPath(manifest.root, recipeDirectory, "dub.sdl"), renderRecipe(session.home,
            manifest, resolution, extras));
    noteRootSettings(manifest, resolution, extras, result);
    {
        import flint_tool.engine.recipe : joinedRootDirectory, joinsRepos, renderJoinedRoot;

        if (joinsRepos(session.home, resolution))
            writeIfChanged(buildPath(manifest.root, joinedRootDirectory, "dub.sdl"),
                    renderJoinedRoot(session.home, resolution, buildPath(manifest.root, joinedRootDirectory)));
    }
    {
        import flint_tool.engine.recipe : renderSelections;

        // Written even when empty: without the file, DUB rebuilds and relinks the project on every build.
        syncDubPackages(manifest.root, resolution);
        writeIfChanged(buildPath(manifest.root, recipeDirectory, "dub.selections.json"),
                renderSelections(manifest.root, resolution));
    }
    foreach (ref item; resolution.packages)
    {
        import flint_tool.engine.recipe : generatedRecipe;

        if (!generatedRecipe(item.kind))
            continue;
        if (item.manifestType != "library")
        {
            report.error("FLINT-E0302", "dependency `" ~ item.name ~ "` is an executable project",
                    "depend on library projects; set type = \"library\" in its flint.toml");
            return false;
        }
        const directory = buildPath(manifest.root, dependencyRecipeDirectory(item.name));
        writeIfChanged(buildPath(directory, "dub.sdl"), renderDependencyRecipe(session.home, item,
                resolution, result.platform.active, directory));
    }
    return true;
}

/// Link the platform as one shared object and point the project's link at it (owner decision 2): the native
/// libraries move into the shared object, and the project links druntime and Phobos as a shared library too, so
/// every D module shares one runtime.
private bool linkShared(ref BuildOutcome result,
        ref imported!"flint_tool.engine.recipe".RecipeExtras extras, ref Report report)
{
    import std.path : dirName;
    import flint_tool.engine.platformcache : linkSharedPlatform, phobosDirectory, platformNativeFlags;

    // The shared object holds the platform only. The AOT library is generated for the project's closure and may be
    // cached only after the first build, so it is linked into the project: the object's key, and so the object a
    // cold build finds, does not depend on whether the library existed yet.
    const native = platformNativeFlags(result.platform.modules) ~ result.natives.linkFlags;
    string failure;
    if (!linkSharedPlatform(result.platform, null, null, native, result.platformShared, failure))
    {
        report.error("FLINT-E0712",
                "the platform cache could not be prepared: the shared platform object failed " ~ "to link",
                "flint build --static links the archives instead; the linker said:\n" ~ tail(failure));
        return false;
    }
    extras.platformLflags = (extras.aotArchive.length
            ? [extras.aotArchive] : null) ~ [
        result.platformShared, "-rpath=" ~ dirName(result.platformShared),
        "-rpath=" ~ phobosDirectory(result.platform.inputs.compiler)
    ];
    extras.platformDflags = ["-defaultlib=libphobos2.so"];
    extras.nativeFlags = null;
    return true;
}

/// Key the AOT library in the platform cache, and return its cached archive, or null when the build compiles it
/// (`storeAotArchive` keeps it afterwards).
private string planAotArchive(string root, scope const string[] library,
        scope const string[] diagnosticFlags, ref BuildOutcome result)
{
    import std.path : buildNormalizedPath, buildPath;
    import flint_tool.engine.aot.driver : aotDirectory;
    import flint_tool.engine.platformcache : aotLibraryModule, cachedArchive;
    import flint_tool.engine.recipe : recipeDirectory;

    string[] files;
    foreach (relative; library)
        files ~= buildNormalizedPath(root, recipeDirectory, relative);
    result.aotLibrary = aotLibraryModule(result.platform, buildNormalizedPath(root, aotDirectory), files,
            diagnosticFlags, buildPath(root, ".flint", "build", "aot-library", "libflint-aot-library.a"));
    return cachedArchive(result.aotLibrary, result.platform.cache) ? result.aotLibrary.archive : null;
}

/// After a build that compiled the AOT library, keep its archive in the platform cache for the next cold build of
/// any project with the same closure. A failure to store it only costs that reuse.
private void storeAotArchive(ref Session session, ref BuildOutcome result)
{
    import flint_tool.engine.platformcache : keptPerModule, prune, storeArchive;

    if (result.aotLibrary.key.length == 0 || result.aotLibrary.archive.length)
        return;
    string failure;
    if (storeArchive(result.aotLibrary, result.platform.cache, failure))
        prune(result.platform.cache, keptPerModule);
    else
        session.progress("Uncached", "the AOT library: " ~ failure);
}

/// Split Flint AOT's modules, relative to the root recipe: `own` are the registry and the modules generated for the
/// project's source (`flint_aot/<module path>` where `src/<module path>` exists), which an edit may change;
/// `library` are the rest, generated for platform and dependency modules, which build as the AOT library, and
/// `modules` their module names.
private void splitAotModules(string root, out string[] own, out string[] library, out string[] modules)
{
    import std.algorithm.sorting : sort;
    import std.array : replace;
    import std.file : SpanMode, dirEntries, exists;
    import std.path : buildPath, dirSeparator, extension, relativePath;
    import flint_tool.engine.aot.driver : aotDirectory;

    const generated = buildPath(root, aotDirectory);
    const prefix = "flint_aot" ~ dirSeparator;
    foreach (entry; dirEntries(generated, SpanMode.depth))
    {
        if (!entry.isFile || entry.name.extension != ".d")
            continue;
        const relative = relativePath(entry.name, generated);
        const generatedForSource = relative.length > prefix.length && relative[0 .. prefix.length] == prefix;
        const recipeRelative = "../aot/" ~ relative.replace(dirSeparator, "/");
        if (generatedForSource && !exists(buildPath(root, "src", relative[prefix.length .. $])))
        {
            library ~= recipeRelative;
            modules ~= moduleOfPath(relative);
        }
        else
            own ~= recipeRelative;
    }
    sort(own);
    sort(library);
    sort(modules);
}

/// `flint_aot.flint.web` for `flint_aot/flint/web/package.d`.
private string moduleOfPath(string relative)
{
    import std.array : replace;
    import std.path : dirSeparator, stripExtension;

    string name = relative.stripExtension.replace(dirSeparator, ".");
    enum suffix = ".package";
    if (name.length > suffix.length && name[$ - suffix.length .. $] == suffix)
        name = name[0 .. $ - suffix.length];
    return name;
}

/// Refresh the working copy of each DUB package from its verified source when the source's hash changed.
private void syncDubPackages(string root, const ref Resolution resolution)
{
    import std.file : copy, exists, mkdirRecurse, rmdirRecurse;
    import std.path : buildPath, dirName;
    import flint_tool.engine.recipe : dubPackagesDirectory, workingName;
    import flint_tool.support.files : findFiles, readIfPresent, writeIfChanged;

    foreach (ref item; resolution.packages)
    {
        if (item.kind != "dub" && item.kind != "local")
            continue;
        const destination = buildPath(root, dubPackagesDirectory, workingName(item));
        const stamp = buildPath(destination, ".flint-source");
        if (readIfPresent(stamp) == item.contentSha256 ~ "\n")
            continue;
        if (exists(destination))
            rmdirRecurse(destination);
        foreach (relative; findFiles(item.directory, "**"))
        {
            import std.algorithm.searching : canFind, startsWith;

            if (relative.startsWith(".git/") || relative.startsWith(".dub/") || relative.canFind("/.dub/"))
                continue;
            mkdirRecurse(dirName(buildPath(destination, relative)));
            copy(buildPath(item.directory, relative), buildPath(destination, relative));
        }
        writeIfChanged(stamp, item.contentSha256 ~ "\n");
    }
}

private string artifactPath(const ref Manifest manifest, const ref BuildRequest request)
{
    import std.path : buildPath;
    import flint_tool.toolchain.host : executable;

    const name = manifest.artifactName();
    if (request.test)
        return buildPath(manifest.root, ".flint", "build", "test", executable(name ~ "-test"));
    version (Windows)
        const library = name ~ ".lib";
    else
        const library = "lib" ~ name ~ ".a";
    const file = manifest.type == "library" ? library : executable(name);
    return buildPath(manifest.root, ".flint", "build", request.profile, file);
}

private bool artifactExists(string artifact, ref Report report)
{
    import std.file : exists;

    if (exists(artifact))
        return true;
    report.error("FLINT-E0704", artifact ~ " was not produced", "flint build --verbose");
    return false;
}

/// The identities every receipt shares: tool, source, toolchain and native install.
private Receipt baseReceipt(ref Session session, string sourceRoot, const ref Toolchain toolchain,
        scope const(string)[] components)
{
    Receipt receipt;
    receipt.tool.release = session.home.platform.release;
    receipt.tool.platform = session.home.platform.flint;
    receipt.tool.sha256 = session.toolSha();
    receipt.source = finishSourceIdentity(session.pendingSource, sourceRoot);
    receipt.toolchain = toolchainRecord(toolchain, components);
    receipt.native = nativeIdentity(session.home.root);
    receipt.environment = influentialEnvironment();
    return receipt;
}

private Receipt projectReceipt(ref Session session, const ref Manifest manifest, const ref Toolchain toolchain,
        const ref BuildRequest request, const ref Flags flags, const ref BuildOutcome result)
{
    import std.path : buildPath;
    import flint_tool.engine.target : hostTarget;
    import flint_tool.project.lock : lockName;
    import flint_tool.support.files : sha256File;

    ProfileSpec spec;
    session.home.profile(request.profile, spec);
    auto receipt = baseReceipt(session, manifest.root, toolchain, [result.compiler, "dub"]);
    receipt.project.name = manifest.name;
    receipt.project.version_number = manifest.version_;
    receipt.project.kind = "project";
    receipt.project.manifest_sha256 = sha256File(buildPath(manifest.root, "flint.toml"));
    receipt.project.lock_sha256 = sha256File(buildPath(manifest.root, lockName));
    receipt.profile = ProfileRecord(request.profile, session.home.digests["policy/profiles.toml"],
            result.compiler, spec.build_type, spec.dflags.dup, flags.dflags.dup, flags.lflags.dup);
    receipt.additions = AdditionsRecord(flags.manifestDflags.dup, flags.manifestLflags.dup,
            request.dflags.dup, request.lflags.dup);
    receipt.waivers = result.checks.waivers.dup;
    receipt.unchecked = result.checks.unchecked.dup;
    receipt.command = result.command.dup;
    // A dev build's artifact is hashed when something uses its receipt as evidence; release and size builds,
    // and tests, hash it now.
    receipt.outputs = [
        request.profile == "dev" && !request.test ? pendingOutputRecord(result.artifact,
                display(result.artifact)) : outputRecord(result.artifact, display(result.artifact))
    ];
    receipt.target = request.target.length ? request.target : hostTarget();
    foreach (source; result.native.sources)
        receipt.embedded_c.sources ~= outputRecord(buildPath(manifest.root, source), source);
    receipt.embedded_c.flags = result.native.flags.dup;
    receipt.embedded_c.compiler_sha256 = result.native.compilerSha256;
    receipt.embedded_c.policy_sha256 = result.native.policySha256;
    foreach (ref package_; result.natives.packages)
        receipt.native_packages ~= NativePackageRecord(package_.name, package_.version_, package_.linkage,
                package_.recipeRevision, package_.packageId, package_.sourceSha256, package_.binarySha256);
    foreach (ref item; result.platform.modules)
    {
        import flint_tool.engine.receipt : PlatformArchiveRecord;

        if (item.archive.length)
            receipt.platform_archives ~= PlatformArchiveRecord(item.name, item.key, item.archiveSha256);
    }
    if (result.aotLibrary.archive.length)
    {
        import flint_tool.engine.receipt : PlatformArchiveRecord;

        receipt.platform_archives ~= PlatformArchiveRecord(result.aotLibrary.name,
                result.aotLibrary.key, result.aotLibrary.archiveSha256);
    }
    if (result.platformShared.length)
    {
        import std.json : JSONException, parseJSON;
        import std.path : baseName, buildPath, dirName;
        import flint_tool.engine.receipt : PlatformArchiveRecord;
        import flint_tool.support.files : readIfPresent;

        // The shared object a dev build loads at run time: its directory is `shared-<key>`, and its digest is the
        // one recorded when it was linked. Cache entries stay out of the digest log: the measurement harness
        // clones the cache with hard links, which changes every file's change time.
        string digest;
        try
            digest = parseJSON(readIfPresent(buildPath(dirName(result.platformShared), "module.json")))["sha256"].str;
        catch (JSONException)
        {
        }
        receipt.platform_archives ~= PlatformArchiveRecord("flint-platform-shared",
                baseName(dirName(result.platformShared))["shared-".length .. $], digest);
    }
    receipt.portable = result.natives.nonPortable.length == 0;
    receipt.non_portable_reasons = result.natives.nonPortable.dup;
    string[] reasons;
    if (flags.manifestDflags.length || flags.manifestLflags.length)
        reasons ~= "flint.toml adds flags to the " ~ request.profile ~ " profile";
    if (flags.noDebug)
        reasons ~= request.noDebug ? "--no-debug builds without debug information or a symbol table"
            : "flint.toml turns off debug information (debug = false)";
    reasons ~= commonReasons(spec, request, result.compiler, receipt.toolchain.verified);
    receipt.canonical = reasons.length == 0;
    receipt.non_canonical_reasons = reasons;
    return receipt;
}

private string[] commonReasons(const ref ProfileSpec spec, const ref BuildRequest request, string compiler,
        bool verified)
{
    import std.algorithm.searching : canFind;

    string[] reasons;
    if (request.dflags.length || request.lflags.length)
        reasons ~= "the command line adds flags";
    if (!spec.compilers.canFind(compiler))
        reasons ~= "the compiler is overridden (" ~ compiler ~ " is not a " ~ request.profile ~ " profile compiler)";
    if (!verified)
        reasons ~= "the toolchain is not verified against its receipt";
    return reasons;
}

/// The receipt record of the components a build used.
ToolchainRecord toolchainRecord(const ref Toolchain toolchain, scope const(string)[] names)
{
    ToolchainRecord record;
    foreach (name; names)
    {
        const component = toolchain.component(name);
        record.components ~= ComponentRecord(name, component.expected, component.reported, component.sha256);
    }
    record.verified = canonicalToolchain(toolchain, names);
    record.dmd_patch_sha256 = toolchain.fork.dmdPatch;
    record.dub_patch_sha256 = toolchain.fork.dubPatch;
    return record;
}

/// One workspace package build or test.
struct PackageRun
{
    /// Package name.
    string name;
    /// Compiler executable name.
    string compiler;
    /// The step succeeded.
    bool ok;
    /// Artifact path relative to the workspace.
    string artifact;
    /// Receipt path relative to the workspace.
    string receipt;
    /// Unittest summary line, for tests.
    string summary;
    /// Fixture peers the suite ran against (ADR-018).
    string[] peers;
    /// Declared peers that could not start.
    string[] missing_peers;
    /// Unittest summary line of the run with peers.
    string peer_summary;
}

/// Run a workspace test binary again inside the fixture peers its package declares. The offline run has passed;
/// a missing peer fails the run with FLINT-E0815 instead of skipping its suites.
private void runWithPeers(ref Session session, ref PackageRun run, string artifact,
        EnvVar[] environment, ref Report report)
{
    import std.array : join;
    import flint_tool.engine.peers : PeerTable, loadPeers, planPeers;
    import flint_tool.toolchain.toolchain : toolchainDirectory;

    PeerTable table;
    if (!loadPeers(session.home, table, report))
    {
        run.ok = false;
        return;
    }
    const plan = planPeers(session.home, table, toolchainDirectory(session.home), run.name, report);
    foreach (ref missing; plan.missing)
    {
        run.missing_peers ~= missing.peer;
        run.ok = false;
        report.error("FLINT-E0815", "flint:" ~ run.name ~ ": peer `" ~ missing.peer ~ "` cannot start: "
                ~ missing.detail ~ "; its peer-dependent suites did not run", missing.install.length
                ? missing.install : "pin a release in policy/ and install it");
    }
    if (plan.started.length == 0)
        return;
    run.peers = plan.started.dup;
    session.progress("Peers", "flint:" ~ run.name ~ " (" ~ run.compiler ~ ") with " ~ plan.started.join(", "));
    string output;
    const ok = runDub(session, plan.prefix ~ artifact, environment, session.home.root, output);
    run.peer_summary = unittestSummary(output);
    if (ok)
        return;
    run.ok = false;
    report.error("FLINT-E0702",
            "flint:" ~ run.name ~ " tests failed with " ~ run.compiler ~ " against " ~ plan.started.join(", "),
            "output:\n" ~ tail(output));
}

/// Build (`test == false`) or test workspace packages with DUB, writing a receipt per artifact.
PackageRun[] workspaceRun(ref Session session, scope const(string)[] packages, string profileName,
        scope const(string)[] compilers, bool test, BuildRequest request, ref Report report)
{
    import std.algorithm.searching : canFind;
    import flint_tool.check.structural : structuralGate;

    if (!nativeBlocksMatch(session.home.root, request.target, report))
        return null;
    ProfileSpec spec;
    if (!selectProfile(session, profileName, spec, report))
        return null;
    // The fast subset of the structural gate runs before every workspace build.
    structuralGate(session.home, packages, null, report, true);
    if (!report.ok)
        return null;
    request.profile = profileName;
    PackageRun[] runs;
    foreach (compiler; compilers)
    {
        Toolchain toolchain;
        if (!usableToolchain(session, compiler, request.verify, toolchain, report))
            return runs;
        foreach (name; session.home.closure(packages))
        {
            if (packages.canFind(name))
                runs ~= runPackage(session, name, compiler, toolchain, spec, test, request, report);
        }
    }
    return runs;
}

private PackageRun runPackage(ref Session session, string name, string compiler, const ref Toolchain toolchain,
        const ref ProfileSpec spec, bool test, const ref BuildRequest request, ref Report report)
{
    import std.array : join;
    import std.file : exists;
    import std.path : buildPath;
    import flint_tool.support.files : findFiles;
    import flint_tool.toolchain.host : executable;

    PackageRun run;
    run.name = name;
    run.compiler = compiler;
    if (findFiles(buildPath(session.home.root, "packages", name, "source"), "**/*.d").length == 0)
    {
        report.error("FLINT-E0705", name ~ ": no implementation sources", "follow its milestone task");
        return run;
    }
    const flags = composeFlags(spec, ProfileOverride.init, request);
    string[] command = [
        toolchain.dub.path, test ? "test" : "build", ":" ~ name, "--root=" ~ session.home.root,
        "--compiler=" ~ toolchain.component(compiler).path, "--build=" ~ spec.build_type,
        "--skip-registry=all"
    ];
    if (request.force)
        command ~= "--force";
    const dubHome = buildPath(session.home.root, ".flint", "dub", compiler);
    auto environment = buildEnvironment(session, toolchain, spec, dubHome, flags.dflags.join(" "));
    environment ~= packageEnvironment(name, test);
    session.progress(test ? "Testing" : "Building", "flint:" ~ name ~ " (" ~ request.profile ~ ", " ~ compiler ~ ")");
    string output;
    run.ok = runDub(session, command, environment, session.home.root, output);
    run.summary = unittestSummary(output);
    if (!run.ok)
    {
        report.error(test ? "FLINT-E0702" : "FLINT-E0701", "flint:" ~ name ~ " " ~ (test
                ? "tests failed" : "failed to build") ~ " with " ~ compiler, "output:\n" ~ tail(output));
        return run;
    }
    const artifact = test ? buildPath(session.home.root, "packages", name,
            executable("flint-" ~ name ~ "-test-unittest")) : libraryPath(session.home.root, name);
    if (!exists(artifact))
        return run;
    if (test)
        runWithPeers(session, run, artifact, environment, report);
    auto receipt = baseReceipt(session, session.home.root, toolchain, [compiler, "dub"]);
    receipt.project.name = "flint:" ~ name;
    receipt.project.version_number = session.home.platform.release;
    receipt.project.kind = "workspace";
    receipt.profile = ProfileRecord(request.profile, session.home.digests["policy/profiles.toml"],
            compiler, spec.build_type, spec.dflags.dup, flags.dflags.dup, flags.lflags.dup);
    receipt.additions = AdditionsRecord(null, null, request.dflags.dup, request.lflags.dup);
    receipt.command = command;
    receipt.outputs = [outputRecord(artifact, display(artifact))];
    receipt.non_canonical_reasons = commonReasons(spec, request, compiler, receipt.toolchain.verified);
    receipt.canonical = receipt.non_canonical_reasons.length == 0;
    const path = buildPath(session.home.root, ".flint", "receipts", (test
            ? "test-" : "build-") ~ name ~ "-" ~ compiler ~ ".receipt.json");
    writeReceipt(path, receipt);
    run.artifact = display(artifact);
    run.receipt = display(path);
    return run;
}

/// Run the live scenarios policy/test-peers.toml declares for `packages`, against their pinned peers.
PackageRun[] runScenarios(ref Session session, scope const(string)[] packages, ref Report report)
{
    import std.algorithm.searching : canFind;
    import flint_tool.engine.peers : MissingPeer, PeerTable, loadPeers, resolveCommand;
    import flint_tool.toolchain.toolchain : toolchainDirectory;

    PeerTable table;
    if (!loadPeers(session.home, table, report))
        return null;
    PackageRun[] runs;
    foreach (ref item; session.home.packages)
    {
        if (!packages.canFind(item.name) || item.name !in table.scenarios)
            continue;
        PackageRun run;
        run.name = item.name;
        run.compiler = "scenarios";
        string[] command;
        MissingPeer missing;
        if (!resolveCommand(session.home, table, toolchainDirectory(session.home),
                table.scenarios[item.name], command, missing, report))
        {
            run.missing_peers = [missing.binary];
            report.error("FLINT-E0815", "flint:" ~ item.name ~ ": live scenarios cannot start: " ~ missing.detail,
                    missing.install.length ? missing.install : "pin a release in policy/ and install it");
            runs ~= run;
            continue;
        }
        session.progress("Scenarios", "flint:" ~ item.name ~ " against its pinned brokers");
        import std.process : environment;

        EnvVar[] variables;
        foreach (name, value; environment.toAA())
        {
            if (name != "DFLAGS")
                variables ~= EnvVar(name, value);
        }
        string output;
        run.ok = runDub(session, command, variables, session.home.root, output);
        run.summary = scenarioSummary(output);
        if (!run.ok)
            report.error("FLINT-E0702", "flint:" ~ item.name ~ " live scenarios failed", "output:\n" ~ tail(output));
        runs ~= run;
    }
    return runs;
}

/// "N of M scenarios passed" from a scenario runner's JSON summary line.
string scenarioSummary(string output)
{
    import std.conv : to;
    import std.string : lineSplitter, strip;
    import flint.serde : DecodeOptions, UnknownFields;
    import flint.serde.owned : deserialize;

    static struct Summary
    {
        long passed;
        long failed;
    }

    DecodeOptions lenient;
    lenient.unknownFields = UnknownFields.ignore;
    string found;
    foreach (line; output.lineSplitter)
    {
        const text = line.strip;
        if (text.length && text[0] == '{')
        {
            const decoded = deserialize!Summary(text, lenient);
            if (decoded.ok)
                found = decoded.value.passed.to!string ~ " of " ~ (decoded.value.passed + decoded.value.failed)
                    .to!string ~ " scenarios passed";
        }
    }
    return found;
}

/// Per-package test environment, as tools/ci.py run_tests sets it. The CI closure builds desktop's SDL
/// canvas backend, whose pinned SDL has no Wayland driver (ADR-020), so its suite runs on SDL's offscreen
/// driver; the WebKitGTK backend is tested on a real display by its own profile.
EnvVar[] packageEnvironment(string name, bool test)
{
    if (test && name == "engine-desktop")
        return [EnvVar("SDL_VIDEODRIVER", "offscreen")];
    return null;
}

private string libraryPath(string root, string name)
{
    import std.array : replace;
    import std.path : buildPath;

    // DUB names a static library `lib<name>.a` on POSIX hosts and `<name>.lib` on Windows.
    version (Windows)
        return buildPath(root, "packages", name, "flint_" ~ name.replace("-", "_") ~ ".lib");
    else
        return buildPath(root, "packages", name, "libflint_" ~ name.replace("-", "_") ~ ".a");
}

/// The druntime unittest summary line, such as "6 modules passed unittests".
string unittestSummary(string output)
{
    import std.algorithm.searching : canFind;
    import std.string : lineSplitter, strip;

    string found;
    foreach (line; output.lineSplitter)
    {
        if (line.canFind("unittests") && (line.canFind("passed") || line.canFind("failed")))
            found = line.strip.idup;
    }
    return found;
}
