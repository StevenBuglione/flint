/// `flint config` and `flint mcp` (ADR-021 sections 2 and 6, ADR-027).
module flint_tool.commands.mcp;

import flint_tool.commands.output : finish, finishBare;
import flint_tool.commands.project : ProjectInfo;
import flint_tool.diagnostics.report : Diagnostic, Report;
import flint_tool.engine.session : Session;

@safe:

/// One resolved configuration key.
struct ConfigKey
{
    /// Dotted key, such as app.greeting.
    string key;
    /// Its value, as JSON.
    string value;
    /// Where it was set: file and line.
    string source;
}

/// `flint.config/1`.
struct ConfigPayload
{
    /// Schema.
    string schema = "flint.config/1";
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
    /// Files read, in precedence order.
    string[] files;
    /// Every key, sorted.
    ConfigKey[] keys;
}

/// `flint config [--profile P]`: every key config/application.toml and its profile file set, with the source.
int commandConfig(ref Session session, string project, string profile)
{
    import std.algorithm.sorting : sort;
    import std.path : buildPath;
    import flint_tool.commands.project : Target, TargetKind, info, locate;

    Report report;
    ConfigPayload payload;
    payload.profile = profile.length ? profile : "dev";
    Target target;
    if (!locate(session, project, target, report))
        return finish(session, report, payload);
    if (target.kind == TargetKind.workspace)
    {
        report.error("FLINT-E0004", "the workspace has no application configuration", "flint config -C <project>");
        return finish(session, report, payload);
    }
    payload.project = info(session, target);
    ConfigKey[string] keys;
    foreach (file; ["config/application.toml", "config/application-" ~ payload.profile ~ ".toml"])
    {
        if (readConfig(buildPath(target.root, file), file, keys, report))
            payload.files ~= file;
    }
    foreach (key; sort(keys.keys))
    {
        payload.keys ~= keys[key];
        session.say(key ~ " = " ~ keys[key].value ~ "    # " ~ keys[key].source);
    }
    return finish(session, report, payload);
}

private bool readConfig(string path, string display, ref ConfigKey[string] keys, ref Report report)
{
    import std.array : join;
    import std.conv : to;
    import flint.serde.owned : readTomlEntries;
    import flint_tool.diagnostics.report : positionOf;
    import flint_tool.support.files : readIfPresent;

    const text = readIfPresent(path);
    if (text is null)
        return false;
    const entries = readTomlEntries(text);
    if (!entries.ok)
    {
        report.error("FLINT-E0102", display ~ " is not valid TOML: " ~ entries.error.message, "fix the file");
        return false;
    }
    foreach (ref entry; entries.value)
    {
        const key = entry.path.join(".");
        keys[key] = ConfigKey(key, entry.json, display ~ ":" ~ positionOf(text, entry.offset).line.to!string);
    }
    return true;
}

/// `flint mcp [--log FILE]`: build flint-mcp (the ai repo's apps/flint-mcp) through flint (fast when current), then
/// become it, serving MCP
/// on stdio in the current directory.
int commandMcp(ref Session session, string log)
{
    import std.file : getcwd;
    import std.path : absolutePath, buildPath;
    import std.process : environment;
    import flint_tool.commands.project : Target, locate;
    import flint_tool.engine.builder : BuildOutcome, BuildRequest, buildProject;
    import flint_tool.sys.posix : replaceProcess;

    Report report;
    const directory = getcwd();
    Target server;
    // flint-mcp belongs to the ai repo (policy/apps.json): it is found through that repo's platform module.
    if (!locate(session, session.home.appDirectory("flint-mcp"), server, report))
        return finishBare(session, report, "flint.mcp/1");
    BuildRequest request;
    BuildOutcome outcome;
    // Standard output belongs to the protocol: the build reports on standard error only.
    const quiet = session.json;
    session.json = false;
    const built = buildProject(session, server.manifest, server.resolution, request, outcome, report);
    session.json = quiet;
    if (!built)
        return finishBare(session, report, "flint.mcp/1");
    environment["FLINT_EXECUTABLE"] = session.executable;
    if (log.length)
        environment["FLINT_MCP_LOG"] = absolutePath(log);
    replaceProcess(outcome.artifact, [outcome.artifact], directory);
    report.error("FLINT-E0814", "could not start " ~ outcome.artifact, "flint build -C " ~ server.root);
    return finishBare(session, report, "flint.mcp/1");
}
