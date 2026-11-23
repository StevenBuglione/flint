/// Flint AOT as a step of `flint build` (ADR-030 section 3): the request from the project's resolution and the
/// toolchain, and the outcome as diagnostics and progress.
module flint_tool.engine.aot.step;

import flint_tool.diagnostics.report : Report;
import flint_tool.engine.session : Session;
import flint_tool.project.manifest : Manifest;
import flint_tool.project.resolve : Resolution;
import flint_tool.toolchain.toolchain : Toolchain;

@safe:

/// What the step tells the build.
struct AotStep
{
    /// The build may continue.
    bool ok;
    /// The recipe compiles `.flint/generated/aot`.
    bool active;
}

/// Run Flint AOT before the recipe is written.
AotStep runAotStep(ref Session session, const ref Manifest manifest, const ref Resolution resolution,
        const ref Toolchain toolchain, string compiler, ref Report report)
{
    import std.conv : to;
    import flint_tool.engine.aot.driver : AotOutcome, AotRequest, runAot;

    // Only applications whose closure has the AOT runtime are AOT applications; ADR-029 applications that use the
    // legacy @FlintApplication keep the scan module.
    bool runtime;
    foreach (ref item; resolution.packages)
        runtime = runtime || item.name == "flint:engine-aot";
    if (!runtime)
        return AotStep(true, false);
    AotRequest request;
    request.root = manifest.root;
    // The extraction compile runs on the forked DMD, whose compile server serves `-o-` compiles; LDC only when the
    // toolchain has no DMD.
    const dmd = toolchain.component("dmd");
    request.compiler = dmd.present ? dmd.path : toolchain.component(compiler).path;
    request.importPaths = importPaths(resolution);
    request.flags = ["-preview=dip1000"];
    foreach (ref item; resolution.packages)
        request.packageDirectories ~= item.directory;
    request.environmentKey = environmentKey(session, toolchain, request.compiler, resolution);
    request.sharedCache = sharedCache(session);
    auto outcome = runAot(request);
    if (!outcome.active)
        return AotStep(true, false);
    if (outcome.extractionErrors.length)
    {
        report.error("FLINT-E1100", "the Flint AOT extraction compile failed",
                "the compiler output follows:\n" ~ imported!"flint_tool.engine.builder".tail(outcome.extractionErrors));
        return AotStep(false, true);
    }
    reportDiagnostics(outcome, report);
    if (session.verbose)
    {
        foreach (removed; outcome.removed)
            session.progress("Removed", removed);
    }
    if (outcome.extracted || outcome.written)
        session.progress("Generated", outcome.generated.to!string ~ " Flint AOT modules for "
                ~ outcome.application ~ " (" ~ outcome.extracted.to!string ~ " extracted in "
                ~ outcome.extractMilliseconds.to!string ~ " ms, " ~ outcome.reused.to!string
                ~ " from the shared cache, " ~ outcome.written.to!string ~ " written, "
                ~ outcome.totalMilliseconds.to!string ~ " ms)");
    return AotStep(outcome.ok, true);
}

private void reportDiagnostics(const ref imported!"flint_tool.engine.aot.driver".AotOutcome outcome, ref Report report)
{
    import flint_tool.diagnostics.report : Severity, at, diagnostic;

    foreach (ref item; outcome.diagnostics)
        report.add(at(diagnostic(item.code, item.warning ? Severity.warning : Severity.error,
                item.message), item.file, item.line));
}

/// Import paths of the closure, as the language server computes them.
string[] importPaths(const ref Resolution resolution)
{
    import std.path : buildPath;

    string[] paths;
    foreach (ref item; resolution.packages)
    {
        if (item.kind == "core")
            paths ~= "-I" ~ buildPath(item.directory, "source");
        else if (item.kind == "dub" || item.kind == "local")
            paths ~= [
            "-I" ~ buildPath(item.directory, "source"), "-I" ~ buildPath(item.directory, "src")
        ];
        else
            paths ~= "-I" ~ buildPath(item.directory, "src");
    }
    return paths;
}

/// Everything that invalidates every cached model: the compiler, the platform and the closure.
/// `<cache>/aot`, beside the platform cache (FLINT_CACHE, else `<home>/.flint/cache`, as engine/builder.d's
/// platformCacheRoot): platform modules' models and class-presence answers, shared by every project.
private string sharedCache(ref Session session)
{
    import std.path : absolutePath, buildNormalizedPath, buildPath;
    import std.process : environment;

    const relocated = environment.get("FLINT_CACHE", "");
    const root = relocated.length
        ? buildNormalizedPath(absolutePath(relocated)) : buildPath(session.home.root, ".flint", "cache");
    return buildPath(root, "aot");
}

private string environmentKey(ref Session session, const ref Toolchain toolchain, string compiler,
        const ref Resolution resolution)
{
    import flint_tool.support.files : sha256Hex;

    string text = compiler ~ "\n" ~ toolchain.component("dmd").reported ~ "\n" ~ session.home.platform.release;
    foreach (ref item; resolution.packages)
        text ~= "\n" ~ item.name ~ "@" ~ item.contentSha256 ~ item.commit;
    return sha256Hex(cast(const(ubyte)[]) text);
}
