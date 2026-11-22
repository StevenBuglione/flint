/// Dependency resolution: Flint core packages, path dependencies and repository-path dependencies resolved by
/// minimal version selection (ADR-023). Native providers are resolved separately.
module flint_tool.project.resolve;

import flint_tool.diagnostics.report : Report, Severity, at, diagnostic;
import flint_tool.home.policy : Home;
import flint_tool.project.manifest : DependencyKind, DependencySpec, Manifest, manifestName, parseManifest;
import flint_tool.project.remote : Requirement;

@safe:

/// One package in the resolved graph.
struct ResolvedPackage
{
    /// Name: `flint:<package>` or the declared dependency name.
    string name;
    /// "core", "path" (a Flint project), "remote" (a repository path) or "local" (a DUB package directory).
    string kind;
    /// For core packages: "workspace" when the project lives in the Flint checkout, else "flint-home".
    string source;
    /// Absolute directory.
    string directory;
    /// Path as declared, relative to the declaring project.
    string declaredPath;
    /// D module root, when known.
    string moduleRoot;
    /// Direct dependencies by resolved name.
    string[] dependencies;
    /// Content hash, or null when the checkout's commit pins the package.
    string contentSha256;
    /// Needed only by tests.
    bool testOnly;
    /// For path projects: the dependency's manifest.
    string manifestType;
    /// For remote modules: the selected version.
    string version_;
    /// For remote modules: the tag's commit.
    string commit;
}

/// The resolved graph of one project.
struct Resolution
{
    /// Every package, sorted by name.
    ResolvedPackage[] packages;
    /// Direct build dependencies by resolved name.
    string[] direct;
    /// Direct test dependencies by resolved name.
    string[] directTest;
    /// The project lives inside the Flint checkout, whose commit pins core packages.
    bool workspace;
    /// Every repository-path requirement seen during minimal version selection.
    Requirement[] requirements;

    /// The package named `name`, or null.
    const(ResolvedPackage)* find(string name) const
    {
        foreach (ref item; packages)
        {
            if (item.name == name)
                return &item;
        }
        return null;
    }
}

/// Whether `path` lies inside `directory`.
bool inside(string path, string directory)
{
    import std.path : absolutePath, buildNormalizedPath;

    const normalPath = buildNormalizedPath(absolutePath(path));
    const normalDirectory = buildNormalizedPath(absolutePath(directory));
    return normalPath == normalDirectory || (normalPath.length > normalDirectory.length
            && normalPath[0 .. normalDirectory.length] == normalDirectory && normalPath[normalDirectory.length] == '/');
}

/// Resolve the manifest's dependencies.
bool resolve(const ref Home home, const ref Manifest manifest, out Resolution resolution, ref Report report)
{
    const before = report.errors();
    resolution.workspace = inside(manifest.root, home.root);
    ResolvedPackage[string] found;
    string[] active = [manifest.root];
    Requirement[] remotes;
    foreach (testScope; [false, true])
    {
        const list = testScope ? manifest.testDependencies : manifest.dependencies;
        foreach (ref spec; list)
        {
            const name = resolveOne(home, manifest, spec, found, active, remotes, report);
            if (name is null)
                continue;
            if (testScope)
                resolution.directTest ~= name;
            else
                resolution.direct ~= name;
        }
    }
    if (remotes.length && !resolveRemotes(home, manifest, remotes, found, resolution, report))
        return false;
    addCoreClosure(home, found, resolution.workspace);
    markScopes(found, resolution);
    import std.algorithm.sorting : sort;

    sort!((a, b) => a.name < b.name)(resolution.packages);
    checkRoots(manifest, resolution, report);
    return report.errors() == before;
}

/// Add every core package reachable from a direct, path or remote dependency.
private void addCoreClosure(const ref Home home, ref ResolvedPackage[string] found, bool workspace)
{
    string[] coreRoots;
    foreach (name, ref item; found)
    {
        if (item.kind == "core")
            coreRoots ~= item.name[6 .. $];
        foreach (dependency; item.dependencies)
        {
            if (dependency.length > 6 && dependency[0 .. 6] == "flint:")
                coreRoots ~= dependency[6 .. $];
        }
    }
    foreach (coreName; home.closure(coreRoots))
    {
        const key = "flint:" ~ coreName;
        if (key !in found)
            found[key] = corePackage(home, coreName, workspace);
    }
}

/// A package is test-only unless a build dependency reaches it; collect the packages.
private void markScopes(ref ResolvedPackage[string] found, ref Resolution resolution)
{
    bool[string] build;
    void mark(string name)
    {
        if (name in build || name !in found)
            return;
        build[name] = true;
        foreach (dependency; found[name].dependencies)
            mark(dependency);
    }

    foreach (name; resolution.direct)
        mark(name);
    foreach (name, ref item; found)
    {
        item.testOnly = name !in build;
        resolution.packages ~= item;
    }
}

private ResolvedPackage corePackage(const ref Home home, string name, bool workspace)
{
    import std.path : buildPath;

    const meta = home.find(name);
    ResolvedPackage item;
    item.name = "flint:" ~ name;
    item.kind = "core";
    item.source = workspace ? "workspace" : "flint-home";
    item.directory = buildPath(home.root, "packages", name);
    item.moduleRoot = meta.module_;
    foreach (dependency; meta.dependencies)
        item.dependencies ~= "flint:" ~ dependency;
    if (!workspace)
        item.contentSha256 = contentHash(item.directory, ["dub.sdl", "source/**", "native/**"]);
    return item;
}

private string resolveOne(const ref Home home, const ref Manifest owner, const ref DependencySpec spec,
        ref ResolvedPackage[string] found, ref string[] active, ref Requirement[] remotes, ref Report report)
{
    final switch (spec.kind)
    {
    case DependencyKind.core:
        return resolveCore(home, owner, spec, found, report);
    case DependencyKind.remote:
        // Collected here; minimal version selection runs once over every requirement.
        remotes ~= Requirement(active.length > 1 ? owner.name : null, spec.name, spec.version_);
        return spec.name;
    case DependencyKind.path:
        return resolvePath(home, owner, spec, found, active, remotes, report);
    }
}

/// Run minimal version selection and add the selected modules to the graph.
private bool resolveRemotes(const ref Home home, const ref Manifest manifest,
        scope const(Requirement)[] remotes, ref ResolvedPackage[string] found, ref Resolution resolution,
        ref Report report)
{
    import flint_tool.project.remote : Fetcher, Selection, selectVersions;

    auto fetcher = Fetcher.forProject(home.root, manifest.root);
    Selection selection;
    if (!selectVersions(fetcher, home, remotes, selection, report))
        return false;
    resolution.requirements = selection.edges;
    foreach (path, ref module_; selection.modules)
    {
        ResolvedPackage item;
        item.name = path;
        item.kind = "remote";
        item.directory = module_.directory;
        item.moduleRoot = module_.moduleRoot;
        item.manifestType = module_.type;
        item.version_ = module_.version_;
        item.commit = module_.commit;
        item.contentSha256 = module_.contentSha256;
        foreach (ref spec; module_.requirements)
            item.dependencies ~= spec.name;
        found[path] = item;
    }
    return true;
}

private string resolveCore(const ref Home home, const ref Manifest owner, const ref DependencySpec spec,
        ref ResolvedPackage[string] found, ref Report report)
{
    import flint_tool.project.manifest : closest;

    const coreName = spec.name[6 .. $];
    if (home.find(coreName) is null)
    {
        string[] names;
        foreach (ref item; home.packages)
            names ~= "flint:" ~ item.name;
        const suggestion = closest(spec.name, names);
        report.add(at(diagnostic("FLINT-E0301", Severity.error, "`" ~ spec.name ~ "` is not a Flint core package",
                suggestion.length
                ? "did you mean `" ~ suggestion ~ "`?" : "core packages are listed in policy/packages.json"),
                displayManifest(owner), spec.line, 0, owner.text));
        return null;
    }
    if (spec.name !in found)
        found[spec.name] = corePackage(home, coreName, inside(owner.root, home.root));
    return spec.name;
}

private string resolvePath(const ref Home home, const ref Manifest owner, const ref DependencySpec spec,
        ref ResolvedPackage[string] found, ref string[] active, ref Requirement[] remotes, ref Report report)
{
    import std.file : exists;
    import std.path : absolutePath, buildNormalizedPath, buildPath;

    string failed(string code, string message, string fix)
    {
        report.add(at(diagnostic(code, Severity.error, message, fix), displayManifest(owner),
                spec.line, 0, owner.text));
        return null;
    }

    const directory = buildNormalizedPath(absolutePath(spec.path, owner.root));
    foreach (ancestor; active)
    {
        if (ancestor == directory)
            return failed("FLINT-E0304",
                    "path dependency `" ~ spec.name ~ "` leads back to " ~ directory, "break the cycle");
    }
    if (spec.name in found)
        return spec.name;
    ResolvedPackage item;
    item.name = spec.name;
    item.directory = directory;
    item.declaredPath = spec.path;
    if (exists(buildPath(directory, "dub.sdl")) || exists(buildPath(directory, "dub.json")))
    {
        if (!exists(buildPath(directory, manifestName)))
        {
            item.kind = "local";
            item.contentSha256 = contentHash(directory, ["**"]);
            found[spec.name] = item;
            return spec.name;
        }
    }
    if (!exists(buildPath(directory, manifestName)))
        return failed("FLINT-E0302", "`" ~ spec.path ~ "` holds no flint.toml, dub.sdl or dub.json",
                "point `path` at the dependency's directory");
    Manifest nested;
    Report nestedReport;
    if (!parseManifest(directory, home, nested, nestedReport))
        return failed("FLINT-E0302", "path dependency `" ~ spec.name ~ "` has an invalid flint.toml",
                "run `flint check` in " ~ spec.path);
    item.kind = "path";
    item.moduleRoot = nested.moduleRoot();
    item.manifestType = nested.type;
    item.contentSha256 = contentHash(directory, ["flint.toml", "src/**", "native/**"]);
    found[spec.name] = item;
    active ~= directory;
    string[] dependencies;
    foreach (ref nestedSpec; nested.dependencies)
    {
        const name = resolveOne(home, nested, nestedSpec, found, active, remotes, report);
        if (name !is null)
            dependencies ~= name;
    }
    active = active[0 .. $ - 1];
    found[spec.name].dependencies = dependencies;
    return spec.name;
}

private string displayManifest(const ref Manifest manifest)
{
    import flint_tool.support.files : relativeTo;
    import std.file : getcwd;
    import std.path : buildPath;

    return relativeTo(buildPath(manifest.root, manifestName), getcwd());
}

private void checkRoots(const ref Manifest manifest, const ref Resolution resolution, ref Report report)
{
    string[string] roots;
    roots[manifest.moduleRoot()] = manifest.name;
    foreach (ref item; resolution.packages)
    {
        if ((item.kind != "path" && item.kind != "remote") || item.moduleRoot.length == 0)
            continue;
        if (item.moduleRoot in roots)
        {
            const message = "`" ~ item.name ~ "` and `" ~ roots[item.moduleRoot]
                ~ "` share the module root `" ~ item.moduleRoot ~ "`";
            report.error("FLINT-E0306", message, "rename one of the projects");
        }
        else
            roots[item.moduleRoot] = item.name;
    }
}

/// Deterministic hash of the files under `directory` matching `patterns`: SHA-256 over sorted
/// "relative-path NUL file-sha256 LF" records. Build and cache directories are excluded.
string contentHash(string directory, scope const(string)[] patterns)
{
    import std.algorithm.sorting : sort;
    import std.algorithm.iteration : uniq;
    import std.array : array;
    import std.path : buildPath;
    import flint_tool.support.files : findFiles, sha256File, sha256Hex, skipped;

    string[] files;
    foreach (pattern; patterns)
    {
        foreach (relative; findFiles(directory, pattern))
        {
            if (!skipped(relative) && !excluded(relative))
                files ~= relative;
        }
    }
    sort(files);
    string records;
    foreach (relative; files.uniq.array)
        records ~= relative ~ "\0" ~ sha256File(buildPath(directory, relative)) ~ "\n";
    return sha256Hex(cast(const(ubyte)[]) records);
}

private bool excluded(string relative)
{
    import std.algorithm.iteration : splitter;
    import std.algorithm.searching : canFind, startsWith;

    foreach (part; relative.splitter('/'))
    {
        if (part == ".git" || part == "__pycache__")
            return true;
    }
    // DUB's test executables next to package recipes.
    return !relative.canFind('/') && relative.startsWith("flint-") && relative.canFind("-test-");
}
