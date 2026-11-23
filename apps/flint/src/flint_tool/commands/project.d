/// Project commands: new, build, run, test, check, fmt and lock.
module flint_tool.commands.project;

import flint_tool.engine.builder : BuildOutcome, BuildRequest, PackageRun, buildProject, display, tail, workspaceRun;
import flint_tool.engine.session : Session;
import flint_tool.check.quality : QualitySummary;
import flint_tool.check.structural : StructuralSummary;
import flint_tool.commands.args : BuildArgs, CheckArgs, FmtArgs, LockArgs, NewArgs, RunArgs, TestArgs;
import flint_tool.commands.output : finish;
import flint_tool.diagnostics.report : Diagnostic, Report, Severity, Tone, at, diagnostic, paint;
import flint_tool.project.manifest : Manifest;
import flint_tool.project.resolve : Resolution;

@safe:

/// What a command acts on.
enum TargetKind : ubyte
{
    /// A Flint project with flint.toml.
    project,
    /// The Flint workspace: the core packages of this checkout.
    workspace
}

/// The located project or workspace.
struct Target
{
    /// Kind.
    TargetKind kind;
    /// Absolute root.
    string root;
    /// The manifest, for projects.
    Manifest manifest;
    /// The resolution, for projects.
    Resolution resolution;
}

/// Project identity in command reports.
struct ProjectInfo
{
    /// Project name, or "flint" for the workspace.
    string name;
    /// Project version.
    string version_number;
    /// Root relative to the current directory.
    string root;
    /// "project" or "workspace".
    string kind;
}

/// Find the project or workspace from `--project` or the current directory.
bool locate(ref Session session, string projectOption, out Target target, ref Report report)
{
    import std.file : exists, getcwd, isDir, readText;
    import std.path : absolutePath, buildNormalizedPath, buildPath;
    import flint_tool.project.manifest : findProjectRoot, isWorkspaceManifest, manifestName, parseManifest;
    import flint_tool.project.resolve : resolve;

    const start = projectOption.length ? buildNormalizedPath(absolutePath(projectOption)) : getcwd();
    if (!exists(start) || !isDir(start))
    {
        report.error("FLINT-E0101", start ~ " is not a directory", "flint build --project <directory>");
        return false;
    }
    target.root = findProjectRoot(start);
    if (target.root is null)
    {
        report.error("FLINT-E0101", "no flint.toml in " ~ start ~ " or any parent directory",
                "run flint new <name>, or cd into a project");
        return false;
    }
    const text = readText(buildPath(target.root, manifestName));
    if (isWorkspaceManifest(text))
    {
        target.kind = TargetKind.workspace;
        import flint_tool.check.structural : realPath;

        // Compare resolved paths: macOS reaches /var and /tmp through /private symlinks.
        if (realPath(target.root) != realPath(session.home.root))
        {
            report.error("FLINT-E0809",
                    target.root ~ " is another Flint checkout's workspace; this flint belongs to " ~ session.home.root,
                    "use that checkout's flint, or set FLINT_HOME=" ~ target.root);
            return false;
        }
        return true;
    }
    if (!parseManifest(target.root, session.home, target.manifest, report))
        return false;
    return resolve(session.home, target.manifest, target.resolution, report);
}

/// The ProjectInfo of a target.
ProjectInfo info(ref Session session, const ref Target target)
{
    if (target.kind == TargetKind.workspace)
        return ProjectInfo("flint", session.home.platform.release, display(target.root), "workspace");
    return ProjectInfo(target.manifest.name, target.manifest.version_, display(target.root), "project");
}

// ---------------------------------------------------------------- new

/// `flint.new/1`.
struct NewPayload
{
    /// Schema.
    string schema = "flint.new/1";
    /// Success.
    bool ok;
    /// Exit code.
    int exit_code;
    /// Diagnostics.
    Diagnostic[] diagnostics;
    /// The new project.
    ProjectInfo project;
    /// Its module root.
    string module_root;
    /// Files written (or planned), relative to the project.
    string[] files;
    /// Core packages it depends on.
    string[] dependencies;
    /// Starters whose packages were scaffolded.
    string[] starters;
    /// Nothing was written.
    bool plan;
}

/// Validate `flint new` arguments; returns the starters.
private string[] validateNew(const ref NewArgs args, ref Report report)
{
    import std.algorithm.iteration : filter, splitter;
    import std.array : join;
    import std.algorithm.sorting : sort;
    import flint_tool.project.manifest : closest, moduleRootOf, reservedRoot, starterPackages, validName;

    if (!validName(args.name))
        report.error("FLINT-E0106", "`" ~ args.name ~ "` is not a valid project name",
                "use lower-case letters, digits and hyphens, starting with a letter: flint new order-service");
    else if (reservedRoot(moduleRootOf(args.name)))
        report.error("FLINT-E0405", "the module root `" ~ moduleRootOf(args.name) ~ "` is reserved",
                "choose another name; `flint` belongs to the core libraries");
    if (args.type != "executable" && args.type != "library")
        report.error("FLINT-E0003", "--type is `executable` or `library`, not `" ~ args.type ~ "`",
                "flint new shop --type library");
    string[] starters;
    foreach (starter; args.starter.splitter(',').filter!(s => s.length))
    {
        if (starter in starterPackages)
        {
            starters ~= starter;
            continue;
        }
        auto known = starterPackages.keys;
        sort(known);
        const suggestion = closest(starter, known);
        report.error("FLINT-E0003", "unknown starter `" ~ starter ~ "`", suggestion.length
                ? "did you mean `" ~ suggestion ~ "`?" : "starters: " ~ known.join(", "));
    }
    return starters;
}

/// `flint new <name>`.
int commandNew(ref Session session, NewArgs args)
{
    import std.file : exists, mkdirRecurse, write;
    import std.path : absolutePath, buildNormalizedPath, buildPath, dirName;
    import flint_tool.project.lock : lockName, renderLock;
    import flint_tool.project.manifest : moduleRootOf;
    import flint_tool.project.resolve : resolve;
    import flint_tool.project.scaffold : ScaffoldFile, scaffold, scaffoldDependencies;

    Report report;
    NewPayload payload;
    payload.plan = args.plan;
    if (args.name.length == 0)
    {
        report.error("FLINT-E0002", "flint new needs a project name", "flint new shop");
        return finish(session, report, payload);
    }
    const starters = validateNew(args, report);
    if (!report.ok)
        return finish(session, report, payload);
    const directory = buildNormalizedPath(absolutePath(args.path.length ? args.path : args.name));
    if (exists(directory))
    {
        const fix = "flint new " ~ args.name ~ " --path <new directory>";
        report.error("FLINT-E0006", directory ~ " already exists", fix);
        return finish(session, report, payload);
    }
    auto files = scaffold(session.home, args.name, args.type, starters);
    payload.module_root = moduleRootOf(args.name);
    payload.dependencies = scaffoldDependencies(args.type, starters);
    payload.starters = starters.dup;
    payload.project = ProjectInfo(args.name, "0.1.0", display(directory), "project");
    // The lock is part of the scaffold: resolve the new manifest exactly as a build will.
    Manifest manifest;
    manifest.root = directory;
    import flint_tool.project.manifest : parseManifestText;

    if (!parseManifestText(files[0].content, session.home, manifest, report))
        return finish(session, report, payload);
    Resolution resolution;
    if (!resolve(session.home, manifest, resolution, report))
        return finish(session, report, payload);
    files ~= ScaffoldFile(lockName, renderLock(session.home, manifest, resolution));
    foreach (ref file; files)
        payload.files ~= file.path;
    if (!args.plan)
    {
        foreach (ref file; files)
        {
            const path = buildPath(directory, file.path);
            mkdirRecurse(dirName(path));
            write(path, file.content);
        }
        session.progress("Created", (args.type == "library"
                ? "library" : "executable") ~ " project `" ~ args.name ~ "` in " ~ display(directory));
        session.say("Next: cd " ~ display(directory) ~ " && flint build && flint run && flint test");
    }
    else if (!session.json)
    {
        foreach (ref file; files)
            session.say("--- " ~ file.path ~ "\n" ~ file.content);
    }
    return finish(session, report, payload);
}

// ---------------------------------------------------------------- build

/// One artifact in a command report.
struct ArtifactInfo
{
    /// Artifact path relative to the current directory.
    string path;
    /// Receipt path relative to the current directory.
    string receipt;
    /// The receipt's canonical verdict.
    bool canonical;
    /// Why not canonical.
    string[] non_canonical_reasons;
}

/// `flint.build/1`.
struct BuildPayload
{
    /// Schema.
    string schema = "flint.build/1";
    /// Success.
    bool ok;
    /// Exit code.
    int exit_code;
    /// Diagnostics.
    Diagnostic[] diagnostics;
    /// What was built.
    ProjectInfo project;
    /// Profile.
    string profile;
    /// Compiler.
    string compiler;
    /// The project artifact.
    ArtifactInfo artifact;
    /// Workspace packages.
    PackageRun[] packages;
    /// Sources the fast checks covered.
    long files_checked;
    /// Active waivers.
    string[] waivers;
}

private BuildRequest requestOf(string profile, string compiler, string[] dflags, string[] lflags,
        bool verify, bool locked, bool force)
{
    BuildRequest request;
    request.profile = profile;
    request.compiler = compiler == "ldc" ? "ldc2" : compiler;
    request.dflags = dflags;
    request.lflags = lflags;
    request.verify = verify;
    request.locked = locked;
    request.force = force;
    return request;
}

private bool validCompiler(string compiler, ref Report report)
{
    if (compiler.length == 0 || compiler == "dmd" || compiler == "ldc2" || compiler == "ldc")
        return true;
    report.error("FLINT-E0003", "unknown compiler `" ~ compiler ~ "`", "--compiler dmd or --compiler ldc2");
    return false;
}

/// `flint build`.
int commandBuild(ref Session session, BuildArgs args, string[] passthrough)
{
    Report report;
    BuildPayload payload;
    payload.profile = args.profile;
    Target target;
    if (!validCompiler(args.compiler, report) || !locate(session, args.project, target, report))
        return finish(session, report, payload);
    payload.project = info(session, target);
    auto request = requestOf(args.profile, args.compiler, args.dflags ~ passthrough, args.lflags,
            args.verify, args.locked, args.force);
    request.platformCache = !args.noPlatformCache;
    request.staticLink = args.staticLink;
    if (target.kind == TargetKind.workspace)
    {
        import flint_tool.home.policy : ProfileSpec;

        ProfileSpec spec;
        if (!session.home.profile(args.profile, spec))
        {
            report.error("FLINT-E0003", "unknown profile `" ~ args.profile ~ "`", "dev, release, size or sanitize");
            return finish(session, report, payload);
        }
        payload.compiler = request.compiler.length ? request.compiler : spec.compiler;
        payload.packages = workspaceRun(session, selectedPackages(session, args.packages, report),
                args.profile, [payload.compiler], false, request, report);
        if (!session.json && report.ok)
            session.progress("Finished", "built " ~ countText(payload.packages.length, "package"));
        return finish(session, report, payload);
    }
    BuildOutcome outcome;
    buildProject(session, target.manifest, target.resolution, request, outcome, report);
    payload.compiler = outcome.compiler;
    payload.files_checked = outcome.checks.files;
    payload.waivers = outcome.checks.waivers;
    if (outcome.ok)
    {
        payload.artifact = ArtifactInfo(display(outcome.artifact), display(outcome.receipt),
                outcome.canonical, outcome.reasons);
        announceArtifact(session, outcome);
    }
    return finish(session, report, payload);
}

private void announceArtifact(ref Session session, const ref BuildOutcome outcome)
{
    import std.array : join;

    if (session.json)
        return;
    foreach (waiver; outcome.checks.waivers)
        session.progress("Waived", waiver);
    session.progress("Finished", display(outcome.artifact) ~ (outcome.canonical
            ? " (canonical)" : " (" ~ paint("non-canonical", session.errorPalette,
            Tone.warning) ~ ": " ~ outcome.reasons.join("; ") ~ ")"));
}

private string countText(size_t count, string noun)
{
    import std.conv : to;

    return count.to!string ~ " " ~ noun ~ (count == 1 ? "" : "s");
}

/// Workspace packages named on the command line (all when none); unknown names are FLINT-E0001.
string[] selectedPackages(ref Session session, scope const(string)[] names, ref Report report)
{
    import flint_tool.project.manifest : closest;

    string[] known;
    foreach (ref item; session.home.packages)
        known ~= item.name;
    if (names.length == 0)
        return known;
    string[] selected;
    foreach (name; names)
    {
        const bare = name.length > 6 && name[0 .. 6] == "flint:" ? name[6 .. $] : name.length
            && name[0] == ':' ? name[1 .. $] : name;
        if (session.home.find(bare) is null)
        {
            const suggestion = closest(bare, known);
            report.error("FLINT-E0001", "`" ~ name ~ "` is not a workspace package", suggestion.length
                    ? "did you mean `" ~ suggestion ~ "`?" : "packages are listed in policy/packages.json");
        }
        else
            selected ~= bare;
    }
    return selected;
}

// ---------------------------------------------------------------- run

/// The program `flint run --json` ran.
struct ProgramInfo
{
    /// argv.
    string[] command;
    /// Exit code, or signal number.
    int exit_code;
    /// Killed by a signal.
    bool signalled;
    /// Standard output.
    string stdout_text;
    /// Standard error.
    string stderr_text;
}

/// `flint.run/1`.
struct RunPayload
{
    /// Schema.
    string schema = "flint.run/1";
    /// Success.
    bool ok;
    /// Exit code.
    int exit_code;
    /// Diagnostics.
    Diagnostic[] diagnostics;
    /// The project.
    ProjectInfo project;
    /// Profile.
    string profile;
    /// The artifact.
    ArtifactInfo artifact;
    /// The program run.
    ProgramInfo program;
}

/// `flint run [-- args]`.
int commandRun(ref Session session, RunArgs args, string[] passthrough)
{
    import std.conv : to;
    import flint_tool.support.process : Launch, capture;
    import flint_tool.sys.posix : replaceProcess;

    Report report;
    RunPayload payload;
    payload.profile = args.profile;
    Target target;
    if (!locate(session, args.project, target, report))
        return finish(session, report, payload);
    payload.project = info(session, target);
    if (target.kind == TargetKind.workspace || target.manifest.type != "executable")
    {
        report.error("FLINT-E0707", target.kind == TargetKind.workspace
                ? "the workspace has no executable" : target.manifest.name ~ " is a library",
                "flint run in an executable project");
        return finish(session, report, payload);
    }
    BuildOutcome outcome;
    auto request = requestOf(args.profile, null, args.dflags, null, args.verify, args.locked, false);
    request.debugger = args.debug_;
    if (!buildProject(session, target.manifest, target.resolution, request, outcome, report))
        return finish(session, report, payload);
    payload.artifact = ArtifactInfo(display(outcome.artifact), display(outcome.receipt),
            outcome.canonical, outcome.reasons);
    const argv = args.debug_ ? debuggerCommand(session, outcome.artifact, passthrough,
            report) : [outcome.artifact] ~ passthrough;
    if (!report.ok)
        return finish(session, report, payload);
    payload.program.command = argv.dup;
    if (!session.json)
    {
        foreach (item; report.items)
        {
            import flint_tool.diagnostics.report : renderHuman;
            import flint_tool.sys.posix : writeError;

            writeError(renderHuman([item], session.errorPalette));
        }
        session.progress(args.debug_ ? "Debugging" : "Running", display(outcome.artifact));
        const failure = replaceProcess(argv[0], argv, target.root);
        report.items = null;
        report.error("FLINT-E0707", "could not start " ~ outcome.artifact ~ " (errno " ~ failure.to!string ~ ")",
                "flint build --verbose");
        return finish(session, report, payload);
    }
    Launch launch;
    launch.directory = target.root;
    const program = capture(argv, launch);
    payload.program.exit_code = program.code;
    payload.program.signalled = program.signalled;
    payload.program.stdout_text = program.output;
    payload.program.stderr_text = program.errors;
    if (!program.ok)
        report.error("FLINT-E0703", program.started ? (program.signalled
                ? "the program was killed by signal " : "the program exited with status ") ~ program.code.to!string
                : program.failure, "see program.stderr_text");
    return finish(session, report, payload);
}

// ---------------------------------------------------------------- test

/// One test run in a report.
struct TestRun
{
    /// Project or workspace package.
    string name;
    /// Compiler.
    string compiler;
    /// Passed.
    bool ok;
    /// Unittest summary line.
    string summary;
    /// Test executable.
    string artifact;
    /// Its receipt.
    string receipt;
    /// Fixture peers the suite also ran against.
    string[] peers;
    /// Declared peers that could not start.
    string[] missing_peers;
    /// Unittest summary line of the run with peers.
    string peer_summary;
}

/// `flint.test/1`.
struct TestPayload
{
    /// Schema.
    string schema = "flint.test/1";
    /// Success.
    bool ok;
    /// Exit code.
    int exit_code;
    /// Diagnostics.
    Diagnostic[] diagnostics;
    /// What was tested.
    ProjectInfo project;
    /// Runs.
    TestRun[] runs;
    /// Passing runs.
    long passed;
    /// Failing runs.
    long failed;
}

/// Compilers `--compiler` selects for the test profile; empty after an E0003.
private string[] testCompilers(ref Session session, string option, ref Report report)
{
    import flint_tool.home.policy : ProfileSpec;

    ProfileSpec spec;
    session.home.profile("test", spec);
    switch (option)
    {
    case "":
        return [spec.compiler];
    case "both":
        return spec.compilers.dup;
    case "dmd":
        return ["dmd"];
    case "ldc":
    case "ldc2":
        return ["ldc2"];
    default:
        report.error("FLINT-E0003", "unknown compiler `" ~ option ~ "`", "--compiler dmd, ldc or both");
        return null;
    }
}

/// `flint test --sanitize` builds with LDC only, in a project; the workspace lane is tools/ci.py's.
private string[] sanitizeCompilers(string option, TargetKind kind, ref Report report)
{
    if (kind == TargetKind.workspace)
    {
        report.error("FLINT-E0004", "flint test --sanitize runs in a project",
                "the workspace sanitizer lane, with sanitized native providers: python3 tools/ci.py sanitizers");
        return null;
    }
    if (option.length == 0 || option == "ldc" || option == "ldc2")
        return ["ldc2"];
    report.error("FLINT-E0003", "--sanitize builds with LDC, not `" ~ option ~ "`", "flint test --sanitize");
    return null;
}

/// Build and run a project's unittest configuration with each compiler.
private TestRun[] testProject(ref Session session, const ref Target target,
        scope const(string)[] compilers, BuildRequest request, ref Report report)
{
    import flint_tool.engine.builder : unittestSummary;
    import flint_tool.support.process : Launch, capture;
    import flint_tool.sys.posix : writeOutput;

    TestRun[] runs;
    foreach (compiler; compilers)
    {
        request.compiler = compiler;
        request.test = true;
        BuildOutcome outcome;
        TestRun run;
        run.name = target.manifest.name;
        run.compiler = compiler;
        if (!buildProject(session, target.manifest, target.resolution, request, outcome, report))
            return runs ~ run;
        run.artifact = display(outcome.artifact);
        run.receipt = display(outcome.receipt);
        session.progress("Running", display(outcome.artifact));
        Launch launch;
        launch.directory = target.root;
        if (request.sanitize)
        {
            import flint_tool.engine.builder : sanitizerRunEnvironment;

            launch.environment = sanitizerRunEnvironment(session);
        }
        const result = capture([outcome.artifact], launch);
        run.summary = unittestSummary(result.combined());
        run.ok = result.ok;
        if (!session.json && result.combined().length)
            writeOutput(result.combined());
        if (!result.ok)
            report.error("FLINT-E0702", target.manifest.name ~ " tests failed with " ~ compiler,
                    "test output:\n" ~ tail(result.combined()));
        runs ~= run;
    }
    return runs;
}

/// The debugger command line of `flint run --debug`: gdb, else lldb, with Flint's pretty-printers loaded.
string[] debuggerCommand(ref Session session, string artifact, scope const string[] arguments, ref Report report)
{
    import std.path : buildPath;
    import flint_tool.support.process : which;

    if (session.json)
    {
        report.error("FLINT-E0004",
                "--debug starts an interactive debugger; it cannot report JSON", "flint run --debug");
        return null;
    }
    const printers = buildPath(session.home.root, "tools", "debug");
    const gdb = which("gdb");
    if (gdb.length)
        return [gdb, "-q", "-x", buildPath(printers, "flint_gdb.py"), "--args", artifact] ~ arguments;
    const lldb = which("lldb");
    if (lldb.length)
        return [
        lldb, "-o", "command script import " ~ buildPath(printers, "flint_lldb.py"), "--", artifact
    ] ~ arguments;
    report.error("FLINT-E0822", "no debugger: neither gdb nor lldb is on PATH",
            "install gdb (Linux) or lldb (macOS), then flint run --debug");
    return null;
}

/// `flint test`.
int commandTest(ref Session session, TestArgs args)
{
    Report report;
    TestPayload payload;
    Target target;
    if (!locate(session, args.project, target, report))
        return finish(session, report, payload);
    payload.project = info(session, target);
    const compilers = args.sanitize ? sanitizeCompilers(args.compiler, target.kind,
            report) : testCompilers(session, args.compiler, report);
    if (compilers.length == 0)
        return finish(session, report, payload);
    auto request = requestOf(args.sanitize ? "sanitize" : "test", null, null, null, args.verify,
            args.locked, args.force);
    request.sanitize = args.sanitize;
    if (target.kind == TargetKind.workspace)
    {
        const selected = selectedPackages(session, args.packages, report);
        auto runs = workspaceRun(session, selected, "test", compilers, true, request, report);
        if (args.scenarios)
        {
            import flint_tool.engine.builder : runScenarios;

            runs ~= runScenarios(session, selected, report);
        }
        foreach (run; runs)
        {
            payload.runs ~= TestRun(run.name, run.compiler, run.ok, run.summary, run.artifact,
                    run.receipt, run.peers.dup, run.missing_peers.dup, run.peer_summary);
            if (!session.json && run.ok)
                session.progress("Passed",
                        "flint:" ~ run.name ~ " (" ~ run.compiler ~ ") " ~ run.summary ~ (run.peers.length
                            ? "; with peers: " ~ run.peer_summary : ""));
        }
    }
    else
        payload.runs = testProject(session, target, compilers, request, report);
    foreach (ref run; payload.runs)
    {
        payload.passed += run.ok;
        payload.failed += !run.ok;
    }
    if (!session.json && report.ok)
        session.progress("Finished", countText(payload.runs.length, "test run") ~ " passed");
    return finish(session, report, payload);
}

// ---------------------------------------------------------------- check

/// `flint.check/1`.
struct CheckPayload
{
    /// Schema.
    string schema = "flint.check/1";
    /// Success.
    bool ok;
    /// Exit code.
    int exit_code;
    /// Diagnostics.
    Diagnostic[] diagnostics;
    /// What was checked.
    ProjectInfo project;
    /// Checks that ran.
    string[] checks;
    /// Sources the layout and safety rules covered.
    long files;
    /// REST handlers in src/.
    long handlers;
    /// `nothrow`, `@nogc`, `scope`, `pure`, `return` and `@trusted` on them (ADR-028 section 3).
    long handler_attributes;
    /// Embedded C sources clang-tidy covered.
    long c_files;
    /// Diagnostics suppressed by waivers.
    long waived;
    /// Active waivers.
    string[] waivers;
    /// The workspace structural gate, as tools/gates.py reports it.
    StructuralSummary structural;
    /// Formatting and lint, as tools/quality.py reports them.
    QualitySummary quality;
}

/// `flint check`.
int commandCheck(ref Session session, CheckArgs args)
{
    import std.path : buildPath;
    import flint_tool.check.quality : checkQuality, qualityFiles;
    import flint_tool.engine.cbuild : nativeSources, tidyNativeC;
    import flint_tool.project.layout : checkProject;
    import flint_tool.project.lock : checkLock, renderLock;
    import flint_tool.toolchain.toolchain : componentPath, toolchainDirectory;

    Report report;
    CheckPayload payload;
    Target target;
    if (args.gate.length && args.gate != "structural")
    {
        report.error("FLINT-E0003", "unknown gate `" ~ args.gate ~ "`", "flint check --gate structural");
        return finish(session, report, payload);
    }
    if (!locate(session, args.project, target, report))
        return finish(session, report, payload);
    payload.project = info(session, target);
    const tools = toolchainDirectory(session.home);
    const dfmt = componentPath(session.home, tools, "dfmt");
    const dscanner = componentPath(session.home, tools, "dscanner");
    if (target.kind == TargetKind.workspace)
    {
        checkWorkspace(session, args, dfmt, dscanner, payload, report);
        return finish(session, report, payload);
    }
    if (args.gate.length)
    {
        report.error("FLINT-E0004", "--gate structural applies to the Flint workspace", "flint check");
        return finish(session, report, payload);
    }
    payload.checks = ["lock", "layout", "safety", "configuration", "quality"];
    checkLock(target.root, renderLock(session.home, target.manifest, target.resolution), true, report);
    const summary = checkProject(session.home, target.manifest, target.resolution, true, report);
    payload.files = summary.files;
    payload.handlers = summary.handlers;
    payload.handler_attributes = summary.handlerAttributes;
    payload.waived = summary.waived;
    payload.waivers = summary.waivers.dup;
    const files = qualityFiles([buildPath(target.root, "src"), buildPath(target.root, "test")]);
    payload.quality = checkQuality(files, dfmt, dscanner, session.home.root, target.root, report);
    if (nativeSources(target.manifest).length)
    {
        payload.checks ~= "clang-tidy";
        payload.c_files = cast(long) nativeSources(target.manifest).length;
        tidyNativeC(session.home, target.manifest, report);
    }
    if (!session.json && report.ok)
        session.progress("Finished", target.manifest.name ~ ": " ~ countText(cast(size_t) summary.files,
                "file") ~ " checked, " ~ countText(summary.waivers.length, "waiver"));
    return finish(session, report, payload);
}

/// The packages of one repo of the split, for `flint check --gate structural --repo <name>`.
private string[] repoPackages(ref Session session, string repo, ref Report report)
{
    string[] names;
    bool known;
    foreach (ref policy; session.home.repos)
        known = known || policy.name == repo;
    if (!known)
    {
        report.error("FLINT-E0001", "`" ~ repo ~ "` is not a repo in policy/repos.json",
                "flint check --gate " ~ "structural --repo flint");
        return null;
    }
    foreach (ref item; session.home.packages)
    {
        if (item.repo == repo)
            names ~= item.name;
    }
    // A repo with no framework packages (boot) still runs the graph, repo-edge and Boot-layer checks.
    return names.length ? names : ["\0none"];
}

/// The workspace part of `flint check`: the structural gate and, unless restricted, dfmt and D-Scanner.
private void checkWorkspace(ref Session session, const ref CheckArgs args, string dfmt, string dscanner,
        ref CheckPayload payload, ref Report report)
{
    import std.path : buildPath;
    import flint_tool.check.quality : checkQuality, qualityFiles;
    import flint_tool.check.structural : structuralGate;
    import flint_tool.toolchain.toolchain : componentPath, toolchainDirectory;

    if (args.gate.length == 0 && (args.packages.length || args.repo.length))
    {
        report.error("FLINT-E0004", "--package restricts the structural gate",
                "flint check --gate structural --package cli");
        return;
    }
    const selected = args.packages.length ? selectedPackages(session, args.packages,
            report) : args.repo.length ? repoPackages(session, args.repo, report) : null;
    if (!report.ok)
        return;
    payload.checks ~= "structural";
    session.progress("Checking", "structural gate (" ~ countText(selected.length ? selected.length
            : session.home.packages.length, "package") ~ ")");
    const dmd = componentPath(session.home, toolchainDirectory(session.home), "dmd");
    payload.structural = structuralGate(session.home, selected, dmd, report);
    payload.structural.repo = args.repo;
    if (args.gate.length == 0)
    {
        payload.checks ~= "quality";
        string[] trees;
        foreach (name; ["packages", "apps", "benchmarks", "examples"])
            trees ~= buildPath(session.home.root, name);
        const files = qualityFiles(trees, true);
        session.progress("Checking", "dfmt and D-Scanner (" ~ countText(files.length, "file") ~ ")");
        payload.quality = checkQuality(files, dfmt, dscanner, session.home.root, session.home.root, report);
    }
    if (!session.json && report.ok && args.gate == "structural")
        session.say(gateJson(payload.structural));
    else if (!session.json && report.ok)
        session.progress("Finished", "workspace checks passed");
}

/// The structural summary exactly as `python3 tools/gates.py --gate structural` prints it.
string gateJson(const ref StructuralSummary summary)
{
    import std.conv : to;

    string tail;
    if (summary.repo.length)
        tail ~= ",\n  \"repo\": \"" ~ summary.repo ~ "\"";
    if (summary.pending_repo_edges.length)
    {
        tail ~= ",\n  \"pending_repo_edges\": [";
        foreach (index, edge; summary.pending_repo_edges)
            tail ~= (index ? "," : "") ~ "\n    \"" ~ edge ~ "\"";
        tail ~= "\n  ]";
    }
    return "{\n  \"packages\": " ~ summary.packages.to!string ~ ",\n  \"graph_nodes\": " ~ summary
        .graph_nodes.to!string ~ ",\n  \"generated_dependencies\": {\n    \"packages\": "
        ~ summary.generated_dependencies.packages.to!string ~ (summary.generated_dependencies.packages
                ? ",\n    \"compiler_profiles\": " ~ summary.generated_dependencies.compiler_profiles.to!string : "")
        ~ "\n  }" ~ tail ~ "\n}";
}

// ---------------------------------------------------------------- fmt

/// `flint.fmt/1`.
struct FmtPayload
{
    /// Schema.
    string schema = "flint.fmt/1";
    /// Success.
    bool ok;
    /// Exit code.
    int exit_code;
    /// Diagnostics.
    Diagnostic[] diagnostics;
    /// Files considered.
    long files;
    /// Files rewritten, or unformatted with --check.
    string[] changed;
    /// Report-only mode.
    bool check;
}

/// `flint fmt`.
int commandFmt(ref Session session, FmtArgs args)
{
    import std.path : buildPath;
    import flint_tool.check.quality : formatFiles, qualityFiles;
    import flint_tool.toolchain.toolchain : componentPath, toolchainDirectory;
    import flint_tool.support.process : capture;
    import std.file : read;

    Report report;
    FmtPayload payload;
    payload.check = args.check;
    Target target;
    if (!locate(session, args.project, target, report))
        return finish(session, report, payload);
    string[] trees;
    foreach (name; target.kind == TargetKind.workspace ? [
        "packages", "apps", "benchmarks", "examples"
    ] : ["src", "test"])
        trees ~= buildPath(target.root, name);
    const files = qualityFiles(trees, target.kind == TargetKind.workspace);
    payload.files = cast(long) files.length;
    const dfmt = componentPath(session.home, toolchainDirectory(session.home), "dfmt");
    if (args.check)
    {
        import flint_tool.check.quality : firstDifferentLine;

        foreach (file; files)
        {
            const formatted = capture([dfmt, "--config", session.home.root, file]);
            const source = cast(const(char)[]) read(file);
            if (!formatted.started)
            {
                report.error("FLINT-E0807", "dfmt is not installed at " ~ dfmt,
                        "python3 tools/install_quality_tools.py");
                break;
            }
            if (formatted.output != source)
            {
                payload.changed ~= display(file);
                report.add(at(diagnostic("FLINT-E0601", Severity.error, "formatter difference",
                        "flint fmt"), display(file), firstDifferentLine(source, formatted.output)));
            }
        }
    }
    else
    {
        foreach (file; formatFiles(files, dfmt, session.home.root, report))
        {
            payload.changed ~= display(file);
            session.progress("Formatted", display(file));
        }
        if (!session.json && report.ok)
            session.progress("Finished", countText(files.length,
                    "file") ~ ", " ~ countText(payload.changed.length, "change"));
    }
    return finish(session, report, payload);
}

// ---------------------------------------------------------------- lock

/// One locked package in a report.
struct LockedPackage
{
    /// Name.
    string name;
    /// Kind.
    string kind;
    /// "build" or "test".
    string scope_name;
    /// Content hash, when recorded.
    string content_sha256;
}

/// `flint.lock/1`.
struct LockPayload
{
    /// Schema.
    string schema = "flint.lock/1";
    /// Success.
    bool ok;
    /// Exit code.
    int exit_code;
    /// Diagnostics.
    Diagnostic[] diagnostics;
    /// Lock path.
    string path;
    /// "written", "unchanged", "current", "missing" or "stale".
    string state;
    /// Resolved packages.
    LockedPackage[] packages;
}

/// `flint lock`.
int commandLock(ref Session session, LockArgs args)
{
    import std.path : buildPath;
    import flint_tool.project.lock : LockState, checkLock, lockName, renderLock, writeLock;

    Report report;
    LockPayload payload;
    Target target;
    if (!locate(session, args.project, target, report))
        return finish(session, report, payload);
    if (target.kind == TargetKind.workspace)
    {
        report.error("FLINT-E0004", "the workspace is pinned by its commit and has no flint.lock",
                "flint lock in a project");
        return finish(session, report, payload);
    }
    payload.path = display(buildPath(target.root, lockName));
    foreach (ref item; target.resolution.packages)
        payload.packages ~= LockedPackage(item.name, item.kind, item.testOnly ? "test" : "build", item.contentSha256);
    const expected = renderLock(session.home, target.manifest, target.resolution);
    if (args.check)
    {
        const state = checkLock(target.root, expected, true, report);
        payload.state = state == LockState.current ? "current" : state == LockState.missing ? "missing" : "stale";
        if (!session.json && report.ok)
            session.progress("Verified", payload.path);
    }
    else
    {
        payload.state = writeLock(target.root, expected) ? "written" : "unchanged";
        session.progress(payload.state == "written" ? "Locked" : "Unchanged",
                payload.path ~ " (" ~ countText(payload.packages.length, "package") ~ ")");
    }
    return finish(session, report, payload);
}
