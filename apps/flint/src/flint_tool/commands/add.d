/// `flint add <starter>...`: wire starters into a project (ADR-021 section 3, ADR-028 section 2).
///
/// Adding a starter declares `flint:starter-<name>` under [dependencies], appends the starter's configuration
/// section (its documented defaults) to config/application.toml when the section is missing, and relocks.
module flint_tool.commands.add;

import flint_tool.commands.output : finish;
import flint_tool.commands.project : ProjectInfo;
import flint_tool.diagnostics.report : Diagnostic, Report;
import flint_tool.engine.session : Session;

@safe:

/// `flint.add/1`.
struct AddPayload
{
    /// Schema.
    string schema = "flint.add/1";
    /// Success.
    bool ok;
    /// Exit code.
    int exit_code;
    /// Diagnostics.
    Diagnostic[] diagnostics;
    /// The project.
    ProjectInfo project;
    /// Starters added to [dependencies].
    string[] added;
    /// Starters that were already declared.
    string[] present;
    /// Configuration sections appended to config/application.toml.
    string[] sections;
    /// Nothing was written.
    bool plan;
}

/// `flint add`.
int commandAdd(ref Session session, scope const string[] names, string project, bool plan)
{
    import flint_tool.commands.project : Target, TargetKind, info, locate;

    Report report;
    AddPayload payload;
    payload.plan = plan;
    Target target;
    if (!locate(session, project, target, report))
        return finish(session, report, payload);
    if (target.kind == TargetKind.workspace)
    {
        report.error("FLINT-E0004", "starters are added to a project",
                "flint add -C <project> " ~ (names.length ? names[0] : "web"));
        return finish(session, report, payload);
    }
    payload.project = info(session, target);
    if (names.length == 0)
    {
        report.error("FLINT-E0009", "name a starter", "flint add " ~ starterList(session));
        return finish(session, report, payload);
    }
    string configuration = readConfiguration(target.root);
    if (!collect(session, target, names, payload, configuration, report))
        return finish(session, report, payload);
    if (plan)
    {
        foreach (dependency; payload.added)
            session.say("+++ flint.toml [dependencies]: \"" ~ dependency ~ "\" = {}");
        foreach (section; payload.sections)
            session.say("+++ config/application.toml: [" ~ section ~ "]");
        return finish(session, report, payload);
    }
    apply(session, target, payload, configuration, report);
    return finish(session, report, payload);
}

/// Record what adding each starter changes; false on an unknown name.
private bool collect(ref Session session, const ref imported!"flint_tool.commands.project".Target target,
        scope const string[] names, ref AddPayload payload, ref string configuration, ref Report report)
{
    foreach (name; names)
    {
        const starter = session.home.findStarter(starterName(name));
        if (starter is null)
        {
            report.error("FLINT-E0009", "`" ~ name ~ "` is not a starter", "flint add " ~ starterList(session));
            return false;
        }
        const dependency = "flint:" ~ starter.name;
        if (declared(target.manifest, dependency) || alreadyListed(payload.added, dependency))
            payload.present ~= dependency;
        else
            payload.added ~= dependency;
        if (starter.section.length && !hasSection(configuration, starter.section))
        {
            const separator = configuration.length == 0 ? "" : configuration[$ - 1] == '\n' ? "\n" : "\n\n";
            configuration ~= separator ~ sectionTemplate(session.home.root, starter.directory);
            payload.sections ~= starter.section;
        }
    }
    return true;
}

private void apply(ref Session session, const ref imported!"flint_tool.commands.project".Target target,
        const ref AddPayload payload, string configuration, ref Report report)
{
    import std.path : buildPath;
    import flint_tool.commands.generate : withDependencies;
    import flint_tool.project.lock : renderLock, writeLock;
    import flint_tool.project.manifest : Manifest, manifestName, parseManifest;
    import flint_tool.project.resolve : Resolution, resolve;
    import flint_tool.support.files : writeIfChanged;

    if (payload.sections.length)
    {
        writeIfChanged(buildPath(target.root, "config", "application.toml"), configuration);
        foreach (section; payload.sections)
            session.progress("Configured", "[" ~ section ~ "] in config/application.toml");
    }
    if (payload.added.length)
        writeIfChanged(buildPath(target.root, manifestName), withDependencies(target.manifest.text, payload.added));
    Manifest updated;
    Resolution resolution;
    if (parseManifest(target.root, session.home, updated, report) && resolve(session.home, updated, resolution, report))
        writeLock(target.root, renderLock(session.home, updated, resolution));
    foreach (dependency; payload.added)
        session.progress("Added", dependency ~ " to flint.toml, and relocked");
    foreach (dependency; payload.present)
        session.progress("Present", dependency ~ " was already a dependency");
}

/// `web` and `starter-web` both name flint:starter-web.
string starterName(string name)
{
    import std.algorithm.searching : startsWith;

    const bare = name.startsWith("flint:") ? name[6 .. $] : name;
    return bare.startsWith("starter-") ? bare : "starter-" ~ bare;
}

/// Whether TOML text has the table `[section]` or a table below it.
bool hasSection(string text, string section)
{
    import std.algorithm.searching : startsWith;
    import std.string : lineSplitter, strip;

    foreach (line; text.lineSplitter)
    {
        const trimmed = line.strip;
        if (trimmed == "[" ~ section ~ "]" || trimmed.startsWith("[" ~ section ~ "."))
            return true;
    }
    return false;
}

private string sectionTemplate(string home, string directory)
{
    import std.path : buildPath;
    import flint_tool.support.files : readIfPresent;

    return readIfPresent(buildPath(home, directory, "config.toml"));
}

private string readConfiguration(string root)
{
    import std.path : buildPath;
    import flint_tool.support.files : readIfPresent;

    return readIfPresent(buildPath(root, "config", "application.toml"));
}

private string starterList(ref Session session)
{
    import std.algorithm.searching : startsWith;

    string names;
    foreach (ref starter; session.home.starters)
    {
        if (starter.name.startsWith("starter-"))
            names ~= (names.length ? "|" : "") ~ starter.name["starter-".length .. $];
    }
    return names.length ? names : "web";
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

private bool alreadyListed(scope const string[] names, string name)
{
    foreach (candidate; names)
    {
        if (candidate == name)
            return true;
    }
    return false;
}

unittest
{
    assert(starterName("web") == "starter-web" && starterName("starter-data") == "starter-data");
    assert(starterName("flint:starter-security") == "starter-security");
    assert(hasSection("[app]\nx = 1\n[database.pool]\n", "database"));
    assert(hasSection("[server]\n", "server") && !hasSection("[servers]\n", "server"));
}
