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

/// One component as `flint deps audit` reports it.
struct AuditComponent
{
    /// Name.
    string name;
    /// Version.
    string version_number;
    /// Origin: flint, repository, path, dub, native, toolchain or embedded-c.
    string origin;
    /// SPDX licence expression, or empty when unknown.
    string license;
    /// static, bundled, dynamic or source.
    string linkage;
    /// Content hash.
    string sha256;
    /// `[unchecked]` waiver reason.
    string waiver;
}

/// A licence obligation the packaged executable carries.
struct Obligation
{
    /// Component name.
    string component;
    /// Its licence.
    string license;
    /// What distributing the executable requires.
    string obligation;
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
    /// Target the audit describes (audit).
    string target;
    /// Every component of the executable (audit).
    AuditComponent[] components;
    /// Hash checks that passed (audit).
    string[] verified;
    /// Licence obligations (audit).
    Obligation[] obligations;
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

/// `flint deps audit`: verify every hash, list every licence, and state the LGPL and AGPL obligations of
/// distributing the executable for `targetName` (default: the host).
int commandDepsAudit(ref Session session, string project, string targetName)
{
    import std.path : buildPath;
    import flint_tool.engine.cbuild : nativeSources;
    import flint_tool.engine.sbom : collect;
    import flint_tool.engine.target : hostTarget;
    import flint_tool.project.lock : checkLock, renderLock;
    import flint_tool.support.files : sha256File;

    Report report;
    DepsPayload payload;
    payload.action = "audit";
    Target target;
    if (!projectTarget(session, project, target, report))
        return finish(session, report, payload);
    payload.project = info(session, target);
    payload.target = targetName.length ? targetName : hostTarget();
    checkLock(target.root, renderLock(session.home, target.manifest, target.resolution), true, report);
    if (report.ok)
        payload.verified ~= "flint.lock matches the resolved graph and its content hashes";
    string[2][] sources;
    foreach (source; nativeSources(target.manifest))
        sources ~= [source, sha256File(buildPath(target.root, source))];
    const inventory = collect(session.home, target.manifest, target.resolution, payload.target, null, sources);
    foreach (ref component; inventory.components)
    {
        payload.components ~= AuditComponent(component.name, component.version_, component.origin,
                component.license, component.linkage, component.sha256, component.waiver);
        auditComponent(session, component.name, component.origin, component.license,
                component.linkage, component.waiver, payload, report);
    }
    verifiedRemotes(target.resolution, payload);
    session.say(target.manifest.name ~ " " ~ target.manifest.version_ ~ " for " ~ payload.target ~ ": " ~ countOf(
            payload.components.length, "component") ~ ", " ~ countOf(payload.obligations.length, "obligation"));
    foreach (line; payload.verified)
        session.say("  verified  " ~ line);
    foreach (ref obligation; payload.obligations)
        session.say("  " ~ obligation.component ~ " (" ~ obligation.license ~ "): " ~ obligation.obligation);
    return finish(session, report, payload);
}

private void auditComponent(ref Session session, string name, string origin, string license,
        string linkage, string waiver, ref DepsPayload payload, ref Report report)
{
    import flint_tool.diagnostics.report : Severity, diagnostic;

    if (waiver.length)
        report.add(diagnostic("FLINT-E0313", Severity.warning, name ~ " is used without the safety checks: " ~ waiver,
                "replace it with a checked Flint library, or keep the [unchecked] waiver"));
    if (license.length == 0)
    {
        if (origin != "embedded-c")
            report.add(diagnostic("FLINT-E0312", Severity.warning, name ~ " declares no licence",
                    "ask its author to set [project] license, or review its terms before distributing"));
        return;
    }
    const text = obligationOf(license, linkage);
    if (text.length)
        payload.obligations ~= Obligation(name, license, text);
}

/// What distributing an executable containing a component under `license`, linked `linkage`, requires: the LGPL
/// and AGPL obligations, and the copyleft of a plain GPL. Empty for permissive licences and GCC-exception runtimes.
string obligationOf(string license, string linkage)
{
    import std.algorithm.searching : canFind;

    if (license.canFind("AGPL"))
        return "users who interact with the program over a network must be offered its complete corresponding "
            ~ "source (AGPL-3.0 section 13), and the whole executable is distributed under the AGPL";
    if (license.canFind("LGPL"))
        return linkage == "static" ? "statically linked: distribute the object files or source needed to relink "
            ~ "the executable against a modified library (LGPL-2.1 section 6, LGPL-3.0 section 4), or use "
            ~ "linkage = \"bundled\"; ship its licence and notices"
            : "shared library: users may replace it; ship " ~ "its licence, notices and a source offer";
    if (license.canFind("GPL") && !license.canFind("exception"))
        return "copyleft: the whole executable must be distributed under GPL-compatible terms with its source";
    return null;
}

private void verifiedRemotes(const ref Resolution resolution, ref DepsPayload payload)
{
    foreach (ref item; resolution.packages)
    {
        // Resolution recomputes every repository module's tree hash before use (FLINT-E0309 otherwise).
        if (item.kind == "remote")
            payload.verified ~= item.name ~ " " ~ item.version_ ~ " tree sha256 " ~ item.contentSha256;
    }
}

private string countOf(size_t count, string noun)
{
    import std.conv : to;

    return count.to!string ~ " " ~ noun ~ (count == 1 ? "" : "s");
}
