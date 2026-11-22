/// `flint deps tree|why|update|vendor`: inspect and change the dependency graph (ADR-021 section 1, ADR-023).
module flint_tool.commands.deps;

import flint_tool.commands.output : finish;
import flint_tool.commands.project : ProjectInfo, Target, TargetKind, info, locate;
import flint_tool.diagnostics.report : Diagnostic, Report;
import flint_tool.engine.session : Session;
import flint_tool.project.resolve : Resolution;

@safe:

/// One node of the dependency tree.
struct DepNode
{
    /// Package name.
    string name;
    /// "core", "path", "remote" or "local".
    string kind;
    /// Selected version, for remote modules.
    string version_number;
    /// Depth below the project.
    long depth;
    /// "build" or "test".
    string scope_name;
}

/// `flint.deps/1`.
struct DepsPayload
{
    /// Schema.
    string schema = "flint.deps/1";
    /// Success.
    bool ok;
    /// Exit code.
    int exit_code;
    /// Diagnostics.
    Diagnostic[] diagnostics;
    /// tree, why, update or vendor.
    string action;
    /// The project.
    ProjectInfo project;
    /// The tree, in depth-first order (tree).
    DepNode[] nodes;
    /// Paths from the project to the package, each a list of names (why).
    string[][] paths;
    /// Changes made, such as "github.com/acme/x 1.2.0 -> 1.3.0" (update, vendor).
    string[] changes;
}

private bool projectTarget(ref Session session, string project, out Target target, ref Report report)
{
    if (!locate(session, project, target, report))
        return false;
    if (target.kind == TargetKind.workspace)
    {
        report.error("FLINT-E0004", "the workspace has no dependency graph of its own", "run flint deps in a project");
        return false;
    }
    return true;
}

/// `flint deps tree`.
int commandDepsTree(ref Session session, string project)
{
    Report report;
    DepsPayload payload;
    payload.action = "tree";
    Target target;
    if (!projectTarget(session, project, target, report))
        return finish(session, report, payload);
    payload.project = info(session, target);
    bool[string] printed;
    void walk(string name, long depth)
    {
        const item = target.resolution.find(name);
        if (item is null)
            return;
        payload.nodes ~= DepNode(name, item.kind, item.version_, depth, item.testOnly ? "test" : "build");
        session.say(indentation(depth) ~ name ~ (item.version_.length ? " " ~ item.version_
                : "") ~ "  (" ~ item.kind ~ (name in printed ? ", see above)" : ")"));
        if (name in printed)
            return;
        printed[name] = true;
        foreach (dependency; item.dependencies)
            walk(dependency, depth + 1);
    }

    session.say(target.manifest.name ~ " " ~ target.manifest.version_);
    foreach (name; target.resolution.direct ~ target.resolution.directTest)
        walk(name, 1);
    return finish(session, report, payload);
}

private string indentation(long depth)
{
    string text;
    foreach (_; 0 .. depth)
        text ~= "  ";
    return text;
}

/// `flint deps why <package>`: every shortest path from the project to the package.
int commandDepsWhy(ref Session session, string project, string name)
{
    import std.array : join;

    Report report;
    DepsPayload payload;
    payload.action = "why";
    Target target;
    if (name.length == 0)
    {
        report.error("FLINT-E0002", "flint deps why needs a package name",
                "flint deps why github.com/acme/flint-stripe");
        return finish(session, report, payload);
    }
    if (!projectTarget(session, project, target, report))
        return finish(session, report, payload);
    payload.project = info(session, target);
    if (target.resolution.find(name) is null)
    {
        report.error("FLINT-E0311", name ~ " is not in the dependency graph of " ~ target.manifest.name,
                "flint deps tree lists every package");
        return finish(session, report, payload);
    }
    payload.paths = shortestPaths(target.resolution, name);
    foreach (path; payload.paths)
        session.say(target.manifest.name ~ " -> " ~ path.join(" -> "));
    foreach (ref requirement; target.resolution.requirements)
    {
        if (requirement.path == name)
            session.say("  " ~ (requirement.from.length ? requirement.from
                    : target.manifest.name) ~ " requires " ~ name ~ " >= " ~ requirement.version_);
    }
    return finish(session, report, payload);
}

/// Shortest paths from the project's direct dependencies to `name`, breadth first.
string[][] shortestPaths(const ref Resolution resolution, string name)
{
    string[][] frontier;
    foreach (direct; resolution.direct ~ resolution.directTest)
        frontier ~= [direct];
    bool[string] seen;
    while (frontier.length)
    {
        string[][] found;
        string[][] next;
        foreach (path; frontier)
        {
            if (path[$ - 1] == name)
                found ~= path;
        }
        if (found.length)
            return found;
        foreach (path; frontier)
        {
            seen[path[$ - 1]] = true;
            const item = resolution.find(path[$ - 1]);
            if (item is null)
                continue;
            foreach (dependency; item.dependencies)
            {
                if (dependency !in seen)
                    next ~= path ~ dependency;
            }
        }
        frontier = next;
    }
    return null;
}

/// `flint deps update [package...]`: raise repository-path requirements to their latest release, then relock.
int commandDepsUpdate(ref Session session, string project, scope const(string)[] names)
{
    import std.path : buildPath;
    import flint_tool.project.lock : renderLock, writeLock;
    import flint_tool.project.manifest : DependencyKind, manifestName, parseManifest;
    import flint_tool.project.remote : Fetcher, compareVersions;
    import flint_tool.project.resolve : resolve;
    import flint_tool.support.files : writeIfChanged;

    Report report;
    DepsPayload payload;
    payload.action = "update";
    Target target;
    if (!projectTarget(session, project, target, report))
        return finish(session, report, payload);
    payload.project = info(session, target);
    auto fetcher = Fetcher.forProject(session.home.root, target.root);
    string text = target.manifest.text;
    foreach (ref spec; target.manifest.dependencies ~ target.manifest.testDependencies)
    {
        if (spec.kind != DependencyKind.remote || (names.length && !contains(names, spec.name)))
            continue;
        const versions = fetcher.tags(spec.name, report);
        if (versions.length == 0 || compareVersions(versions[$ - 1], spec.version_) <= 0)
            continue;
        text = replaceRequirement(text, spec.name, spec.version_, versions[$ - 1]);
        payload.changes ~= spec.name ~ " " ~ spec.version_ ~ " -> " ~ versions[$ - 1];
        session.progress("Updating", spec.name ~ " " ~ spec.version_ ~ " -> " ~ versions[$ - 1]);
    }
    if (!report.ok || payload.changes.length == 0)
    {
        if (report.ok)
            session.progress("Current", "every repository-path dependency is at its latest release");
        return finish(session, report, payload);
    }
    writeIfChanged(buildPath(target.root, manifestName), text);
    Target updated;
    if (parseManifest(target.root, session.home, updated.manifest, report) && resolve(session.home,
            updated.manifest, updated.resolution, report))
        writeLock(target.root, renderLock(session.home, updated.manifest, updated.resolution));
    return finish(session, report, payload);
}

/// Replace the version of one `"<path>" = "<old>"` requirement in manifest text.
string replaceRequirement(string text, string path, string oldVersion, string newVersion)
{
    import std.array : replace;

    return text.replace("\"" ~ path ~ "\" = \"" ~ oldVersion ~ "\"", "\"" ~ path ~ "\" = \"" ~ newVersion ~ "\"");
}

private bool contains(scope const(string)[] list, string value)
{
    foreach (item; list)
    {
        if (item == value)
            return true;
    }
    return false;
}

/// `flint deps vendor`: copy every selected remote module into vendor/, which later builds use offline.
int commandDepsVendor(ref Session session, string project)
{
    import std.file : copy, exists, mkdirRecurse, rmdirRecurse;
    import std.path : buildPath, dirName;
    import flint_tool.project.remote : vendorIndexName;
    import flint_tool.project.resolve : contentHash;
    import flint_tool.support.files : findFiles, writeIfChanged;

    Report report;
    DepsPayload payload;
    payload.action = "vendor";
    Target target;
    if (!projectTarget(session, project, target, report))
        return finish(session, report, payload);
    payload.project = info(session, target);
    const vendor = buildPath(target.root, "vendor");
    string index = "# Generated by `flint deps vendor`.\n"
        ~ "# Builds take these modules from vendor/ and verify their hashes.\n";
    foreach (ref item; target.resolution.packages)
    {
        if (item.kind != "remote")
            continue;
        const destination = buildPath(vendor, item.name);
        if (exists(destination))
            rmdirRecurse(destination);
        foreach (relative; findFiles(item.directory, "**"))
        {
            mkdirRecurse(dirName(buildPath(destination, relative)));
            copy(buildPath(item.directory, relative), buildPath(destination, relative));
        }
        if (contentHash(destination, ["**"]) != item.contentSha256)
            report.error("FLINT-E0309", "vendor/" ~ item.name ~ " does not reproduce its content hash",
                    "delete vendor/ and run flint deps vendor again");
        index ~= "\n[[module]]\npath = \"" ~ item.name ~ "\"\nversion_number = \"" ~ item.version_
            ~ "\"\ncommit = \"" ~ item.commit ~ "\"\ncontent_sha256 = \"" ~ item.contentSha256 ~ "\"\n";
        payload.changes ~= item.name ~ " " ~ item.version_;
        session.progress("Vendored", item.name ~ " " ~ item.version_);
    }
    writeIfChanged(buildPath(vendor, vendorIndexName), index);
    return finish(session, report, payload);
}
