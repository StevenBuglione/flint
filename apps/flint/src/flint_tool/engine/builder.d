/// Building and testing projects and workspace packages through the forked DUB, with receipts.
module flint_tool.engine.builder;

import flint.os : EnvVar;
import flint_tool.engine.receipt : AdditionsRecord, ComponentRecord, EnvironmentRecord, OutputRecord, ProfileRecord,
    Receipt, ToolchainRecord, nativeIdentity, outputRecord, receiptPath, sourceIdentity, writeReceipt;
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

/// Environment for DUB: flint's own, without DFLAGS, with the pinned toolchain first on PATH.
EnvVar[] buildEnvironment(ref Session session, const ref Toolchain toolchain, const ref ProfileSpec spec,
        string dubHome, string dflags)
{
    import std.path : dirName;
    import std.process : environment;

    EnvVar[] variables;
    foreach (name, value; environment.toAA())
    {
        if (name == "DFLAGS" || name == "DUB_HOME" || name == "PATH")
            continue;
        const disabledServer = name == "FLINT_DMD_SERVER" && !spec.compile_server;
        if (disabledServer || (name == "FLINT_DUB_PIPELINE" && !spec.dub_pipeline))
            continue;
        variables ~= EnvVar(name, value);
    }
    variables ~= EnvVar("PATH", dirName(toolchain.dmd.path) ~ ":" ~ dirName(
            toolchain.ldc2.path) ~ ":" ~ environment.get("PATH", "/usr/bin:/bin"));
    variables ~= EnvVar("DUB_HOME", dubHome);
    if (dflags.length)
        variables ~= EnvVar("DFLAGS", dflags);
    if (!spec.compile_server)
        variables ~= EnvVar("FLINT_DMD_SERVER", "0");
    if (!spec.dub_pipeline)
        variables ~= EnvVar("FLINT_DUB_PIPELINE", "0");
    return variables;
}

/// Variables that change builds, as recorded in receipts.
EnvironmentRecord[] influentialEnvironment()
{
    import std.algorithm.sorting : sort;
    import std.process : environment;

    EnvironmentRecord[] records;
    foreach (name; [
        "FLINT_DMD_SERVER", "FLINT_DUB_PIPELINE", "FLINT_DMD_DIRECT_LINK", "FLINT_LINK_THREADS", "CC",
        "LD"
    ])
    {
        const value = environment.get(name, null);
        if (value !is null)
            records ~= EnvironmentRecord(name, value);
    }
    sort!((a, b) => a.name < b.name)(records);
    return records;
}

/// Run DUB, streaming its output when verbose and capturing it otherwise.
bool runDub(ref Session session, scope const(string)[] argv, EnvVar[] env, string cwd, out string output)
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
            writeError(text);
    });
    output = collected;
    if (!outcome.started)
        output = outcome.failure;
    return outcome.ok;
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

/// Build a project with a profile: lock, toolchain, fast checks, recipe, DUB, receipt.
bool buildProject(ref Session session, const ref Manifest manifest, const ref Resolution resolution,
        BuildRequest request, out BuildOutcome result, ref Report report)
{
    import std.array : join;
    import std.path : buildPath;
    import flint_tool.engine.recipe : recipeDirectory;

    ProfileSpec spec;
    if (!selectProfile(session, request.profile, spec, report))
        return false;
    const compiler = request.compiler.length ? request.compiler : spec.compiler;
    result.compiler = compiler;
    if (!prepareLock(session, manifest, resolution, request.locked, report))
        return false;
    Toolchain toolchain;
    if (!usableToolchain(session, compiler, request.verify, toolchain, report))
        return false;
    result.checks = checkProject(session.home, manifest, resolution, false, report);
    if (!report.ok || !writeRecipes(session, manifest, resolution, report))
        return false;

    const flags = composeFlags(spec, manifest.overrideFor(request.profile), request);
    const command = projectCommand(toolchain, compiler, manifest.root, request);
    result.command = command.dup;
    const dubHome = buildPath(manifest.root, ".flint", "dub");
    auto environment = buildEnvironment(session, toolchain, spec, dubHome, flags.dflags.join(" "));
    const label = request.test ? "test" : request.profile;
    session.progress(request.test ? "Compiling" : "Building",
            manifest.name ~ " " ~ manifest.version_ ~ " (" ~ label ~ ", " ~ compiler ~ ")");
    if (!runDub(session, command, environment, manifest.root, result.output))
    {
        report.error("FLINT-E0701", request.test ? "the test build failed" : "the build failed",
                "the compiler output follows:\n" ~ tail(result.output));
        return false;
    }
    result.artifact = artifactPath(manifest, request);
    if (!artifactExists(result.artifact, report))
        return false;
    auto receipt = projectReceipt(session, manifest, toolchain, request, flags, result);
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
}

private Flags composeFlags(const ref ProfileSpec spec, ProfileOverride additions, const ref BuildRequest request)
{
    Flags flags;
    // A "plain" profile's flags are the complete flag set (through DFLAGS). Other build types, such as the
    // test profile's, apply only to the project: its unittest configuration adds -unittest, so dependencies
    // are not rebuilt with their own unittests.
    if (spec.build_type == "plain")
        flags.dflags = spec.dflags.dup;
    flags.dflags ~= additions.dflags ~ request.dflags;
    flags.lflags = spec.lflags.dup ~ additions.lflags ~ request.lflags;
    foreach (flag; flags.lflags)
        flags.dflags ~= "-L" ~ flag;
    flags.manifestDflags = additions.dflags;
    flags.manifestLflags = additions.lflags;
    return flags;
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

private bool writeRecipes(ref Session session, const ref Manifest manifest,
        const ref Resolution resolution, ref Report report)
{
    import std.path : buildPath;
    import flint_tool.engine.recipe : dependencyRecipeDirectory, recipeDirectory,
        renderDependencyRecipe, renderRecipe;
    import flint_tool.support.files : writeIfChanged;

    writeIfChanged(buildPath(manifest.root, recipeDirectory, "dub.sdl"), renderRecipe(session.home,
            manifest, resolution));
    foreach (ref item; resolution.packages)
    {
        if (item.kind != "path")
            continue;
        if (item.manifestType != "library")
        {
            report.error("FLINT-E0302", "path dependency `" ~ item.name ~ "` is an executable project",
                    "depend on library projects; set type = \"library\" in its flint.toml");
            return false;
        }
        writeIfChanged(buildPath(manifest.root, dependencyRecipeDirectory(item.name), "dub.sdl"),
                renderDependencyRecipe(session.home, item, resolution));
    }
    return true;
}

private string artifactPath(const ref Manifest manifest, const ref BuildRequest request)
{
    import std.path : buildPath;

    const name = manifest.artifactName();
    if (request.test)
        return buildPath(manifest.root, ".flint", "build", "test", name ~ "-test");
    const file = manifest.type == "library" ? "lib" ~ name ~ ".a" : name;
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
    receipt.source = sourceIdentity(sourceRoot);
    receipt.toolchain = toolchainRecord(toolchain, components);
    receipt.native = nativeIdentity(session.home.root);
    receipt.environment = influentialEnvironment();
    return receipt;
}

private Receipt projectReceipt(ref Session session, const ref Manifest manifest, const ref Toolchain toolchain,
        const ref BuildRequest request, const ref Flags flags, const ref BuildOutcome result)
{
    import std.path : buildPath;
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
    receipt.command = result.command.dup;
    receipt.outputs = [outputRecord(result.artifact, display(result.artifact))];
    string[] reasons;
    if (flags.manifestDflags.length || flags.manifestLflags.length)
        reasons ~= "flint.toml adds flags to the " ~ request.profile ~ " profile";
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
}

/// Build (`test == false`) or test workspace packages with DUB, writing a receipt per artifact.
PackageRun[] workspaceRun(ref Session session, scope const(string)[] packages, string profileName,
        scope const(string)[] compilers, bool test, BuildRequest request, ref Report report)
{
    import std.algorithm.searching : canFind;
    import flint_tool.check.structural : structuralGate;

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
    const artifact = test ? buildPath(session.home.root, "packages", name, "flint-" ~ name ~ "-test-unittest")
        : libraryPath(session.home.root, name);
    if (!exists(artifact))
        return run;
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

/// Per-package test environment, as tools/ci.py run_tests sets it. The CI closure builds desktop's SDL
/// canvas backend, whose pinned SDL has no Wayland driver (ADR-020), so its suite runs on SDL's offscreen
/// driver; the WebKitGTK backend is tested on a real display by its own profile.
EnvVar[] packageEnvironment(string name, bool test)
{
    if (test && name == "desktop")
        return [EnvVar("SDL_VIDEODRIVER", "offscreen")];
    return null;
}

private string libraryPath(string root, string name)
{
    import std.array : replace;
    import std.path : buildPath;

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
