/// `flint generate <kind> <Name>`: canonical components and AGENTS.md (ADR-021 sections 1, 2 and 6, ADR-026).
module flint_tool.commands.generate;

import flint_tool.commands.output : finish;
import flint_tool.commands.project : ProjectInfo;
import flint_tool.diagnostics.report : Diagnostic, Report;
import flint_tool.engine.session : Session;
import flint_tool.project.generators : GeneratedFile;

@safe:

/// `flint.generate/1`.
struct GeneratePayload
{
    /// Schema.
    string schema = "flint.generate/1";
    /// Success.
    bool ok;
    /// Exit code.
    int exit_code;
    /// Diagnostics.
    Diagnostic[] diagnostics;
    /// The project.
    ProjectInfo project;
    /// Generator.
    string kind;
    /// Component name.
    string name;
    /// Files written (or that would be, with --plan).
    GeneratedFile[] files;
    /// Core packages added to [dependencies].
    string[] dependencies_added;
    /// The suggested next step.
    string next;
    /// Nothing was written.
    bool plan;
}

/// `flint generate`.
int commandGenerate(ref Session session, string kind, string name, string project, bool plan)
{
    import std.algorithm.searching : canFind;
    import std.array : join;
    import std.file : exists;
    import std.path : buildPath;
    import flint_tool.commands.project : Target, TargetKind, info, locate;
    import flint_tool.project.generators : Generation, agentsGuide, generate;
    import flint_tool.support.files : findFiles;

    Report report;
    GeneratePayload payload;
    payload.kind = kind;
    payload.name = name;
    payload.plan = plan;
    Target target;
    if (!validRequest(kind, name, report) || !locate(session, project, target, report)
            || !inProject(target.kind == TargetKind.workspace, report))
        return finish(session, report, payload);
    payload.project = info(session, target);
    const root = target.manifest.moduleRoot();
    Generation generation;
    if (kind == "agents")
        generation.files = [
        GeneratedFile("AGENTS.md", agentsGuide(target.manifest.name, root, target.manifest.type))
    ];
    else
        generation = generate(kind, name, root, nextMigration(target.root), findFiles(target.root, "src/**"));
    foreach (ref file; generation.files)
        file.content = formatted(session, file.path, file.content);
    payload.files = generation.files;
    payload.next = generation.next;
    foreach (ref file; generation.files)
    {
        if (kind != "agents" && exists(buildPath(target.root, file.path)))
        {
            report.error("FLINT-E0008", file.path ~ " already exists",
                    "generators never overwrite; choose another name");
            return finish(session, report, payload);
        }
    }
    foreach (package_; generation.packages)
    {
        if (!declared(target.manifest, "flint:" ~ package_))
            payload.dependencies_added ~= "flint:" ~ package_;
    }
    if (plan)
    {
        foreach (ref file; payload.files)
            session.say("--- " ~ file.path ~ "\n" ~ file.content);
        foreach (dependency; payload.dependencies_added)
            session.say("+++ flint.toml [dependencies]: \"" ~ dependency ~ "\" = {}");
        return finish(session, report, payload);
    }
    write(session, target, payload, report);
    return finish(session, report, payload);
}

private void write(ref Session session, const ref imported!"flint_tool.commands.project".Target target,
        const ref GeneratePayload payload, ref Report report)
{
    import std.path : buildPath;
    import flint_tool.project.lock : renderLock, writeLock;
    import flint_tool.project.manifest : Manifest, manifestName, parseManifest;
    import flint_tool.project.resolve : Resolution, resolve;
    import flint_tool.support.files : writeIfChanged;

    foreach (ref file; payload.files)
    {
        writeIfChanged(buildPath(target.root, file.path), file.content);
        session.progress("Generated", file.path);
    }
    if (payload.dependencies_added.length == 0)
    {
        if (payload.next.length)
            session.progress("Next", payload.next);
        return;
    }
    writeIfChanged(buildPath(target.root, manifestName), withDependencies(target.manifest.text,
            payload.dependencies_added));
    Manifest updated;
    Resolution resolution;
    if (parseManifest(target.root, session.home, updated, report) && resolve(session.home, updated, resolution, report))
        writeLock(target.root, renderLock(session.home, updated, resolution));
    foreach (dependency; payload.dependencies_added)
        session.progress("Added", dependency ~ " to flint.toml, and relocked");
    if (payload.next.length)
        session.progress("Next", payload.next);
}

private bool declared(const ref imported!"flint_tool.project.manifest".Manifest manifest, string name)
{
    foreach (ref dependency; manifest.dependencies)
    {
        if (dependency.name == name)
            return true;
    }
    return false;
}

private bool validRequest(string kind, string name, ref Report report)
{
    import std.algorithm.searching : canFind;
    import std.array : join;
    import flint_tool.project.generators : generatorKinds, validTypeName;

    if (!generatorKinds.canFind(kind))
        report.error("FLINT-E0003", "unknown generator `" ~ kind ~ "`", "choose one of: " ~ generatorKinds.join(", "));
    else if (kind != "agents" && !validTypeName(name))
    {
        const fix = "flint generate " ~ kind ~ " Order";
        report.error("FLINT-E0003", "`" ~ name ~ "` is not a PascalCase type name", fix);
    }
    return report.ok;
}

private bool inProject(bool workspace, ref Report report)
{
    if (workspace)
        report.error("FLINT-E0004", "generators write into a project, not the workspace",
                "flint generate -C <project>");
    return !workspace;
}

/// D sources pass through the pinned dfmt, so generated code is already in the one canonical format.
private string formatted(ref Session session, string path, string content)
{
    import std.algorithm.searching : endsWith;
    import std.file : exists, remove, tempDir, write;
    import std.path : buildPath;
    import std.uuid : randomUUID;
    import flint_tool.support.process : capture;
    import flint_tool.toolchain.toolchain : componentPath, toolchainDirectory;

    const dfmt = componentPath(session.home, toolchainDirectory(session.home), "dfmt");
    if (!path.endsWith(".d") || !exists(dfmt))
        return content;
    const scratch = buildPath(tempDir(), "flint-generate-" ~ randomUUID().toString() ~ ".d");
    write(scratch, content);
    scope (exit)
        remove(scratch);
    const result = capture([dfmt, "--config", session.home.root, scratch]);
    return result.ok && result.output.length ? result.output : content;
}

/// Insert `"flint:x" = {}` lines at the top of [dependencies], creating the table when missing.
string withDependencies(string text, scope const(string)[] names)
{
    import std.string : indexOf;

    string lines;
    foreach (name; names)
        lines ~= "\"" ~ name ~ "\" = {}\n";
    const header = "[dependencies]\n";
    const at = text.indexOf(header);
    if (at < 0)
        return text ~ (text.length && text[$ - 1] != '\n' ? "\n" : "") ~ "\n" ~ header ~ lines;
    return text[0 .. at + header.length] ~ lines ~ text[at + header.length .. $];
}

/// The next free migration number in resources/migrations (V000001__name.sql).
long nextMigration(string root)
{
    import std.conv : ConvException, to;
    import std.path : baseName, buildPath;
    import flint_tool.support.files : findFiles;

    long highest;
    foreach (relative; findFiles(buildPath(root, "resources", "migrations"), "*.sql"))
    {
        const name = baseName(relative);
        if (name.length < 9 || name[0] != 'V' || name[7 .. 9] != "__")
            continue;
        try
        {
            const number = name[1 .. 7].to!long;
            highest = number > highest ? number : highest;
        }
        catch (ConvException)
            continue;
    }
    return highest + 1;
}
