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
    /// "core", "path" (a Flint project), "remote" (a repository path), "dub" (a DUB package from the
    /// compatibility index) or "local" (a DUB package directory).
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
    /// SPDX licence expression from the dependency's flint.toml, or empty.
    string license;
    /// For DUB packages: findings of Flint's safety rules over their D sources.
    long safetyFindings;
    /// For DUB packages: the first findings.
    string[] safetySample;
    /// Native packages it needs, as name@version: a path or repository dependency's `[native]`, or the recipes an
    /// indexed DUB package's entry names.
    string[] nativeRecipes;
    /// For core packages, Boot libraries and starters: the checkout of their platform module, whose root
    /// dub.sdl lists them (ADR-023 amendment), and its version, `repo@version`.
    string repoRoot;
    /// ditto
    string platform;
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
    /// The native packages, resolved for the host target.
    imported!"flint_tool.project.native".NativeResolution natives;

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
    import std.path : absolutePath, buildNormalizedPath, filenameCmp, isDirSeparator;

    // filenameCmp ignores case where the file system does (Windows) and isDirSeparator accepts `\` there.
    const normalPath = buildNormalizedPath(absolutePath(path));
    const normalDirectory = buildNormalizedPath(absolutePath(directory));
    return filenameCmp(normalPath, normalDirectory) == 0 || (normalPath.length > normalDirectory.length
            && filenameCmp(normalPath[0 .. normalDirectory.length],
                normalDirectory) == 0 && isDirSeparator(normalPath[normalDirectory.length]));
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
    Requirement[] dubs;
    Requirement[] repositories;
    foreach (ref requirement; remotes)
    {
        if (requirement.path.length > 4 && requirement.path[0 .. 4] == "dub:")
            dubs ~= requirement;
        else
            repositories ~= requirement;
    }
    if (repositories.length && !resolveRemotes(home, manifest, repositories, found, resolution, report))
        return false;
    if (dubs.length && !resolveDub(home, manifest, dubs, found, report))
        return false;
    addCoreClosure(home, found, resolution.workspace);
    markScopes(found, resolution);
    import std.algorithm.sorting : sort;

    sort!((a, b) => a.name < b.name)(resolution.packages);
    checkRoots(manifest, resolution, report);
    if (report.errors() == before)
        resolveProjectNatives(home, manifest, resolution, report);
    return report.errors() == before;
}

/// The native packages of a build for `target`, with or without sanitizers: the locked host resolution, or a fresh
/// one for another target or variant (whose recipes and sources the lock still pins).
bool nativesFor(const ref Home home, const ref Manifest manifest, const ref Resolution resolution, string target,
        bool sanitize, out imported!"flint_tool.project.native".NativeResolution natives, ref Report report)
{
    import flint_tool.project.native : NativeRequirement, collectRequirements, resolveNatives;

    if (resolution.natives.packages.length == 0 || (resolution.natives.target == target && !sanitize))
    {
        natives = copyNatives(resolution.natives);
        return true;
    }
    string[][string] fromDependencies;
    foreach (ref item; resolution.packages)
    {
        if (item.nativeRecipes.length && !item.testOnly)
            fromDependencies[item.name] = item.nativeRecipes.dup;
    }
    NativeRequirement[] requirements;
    if (!collectRequirements(manifest, fromDependencies, requirements, report)
            || !resolveNatives(home, manifest, requirements, target, sanitize, natives, report))
        return false;
    foreach (ref package_; natives.packages)
    {
        foreach (ref locked; resolution.natives.packages)
        {
            if (locked.name == package_.name && (locked.recipeRevision != package_.recipeRevision
                    || locked.sourceSha256 != package_.sourceSha256))
            {
                const pinned = locked.recipeRevision;
                report.error("FLINT-E0202", "native package " ~ package_.name ~ " for " ~ target
                        ~ " resolved recipe " ~ package_.recipeRevision ~ " but flint.lock pins " ~ pinned,
                        "review the change, then run `flint lock` to accept it");
                return false;
            }
        }
    }
    return true;
}

private imported!"flint_tool.project.native".NativeResolution copyNatives(
        const ref imported!"flint_tool.project.native".NativeResolution source)
{
    import flint_tool.project.native : NativePackage, NativeResolution;

    NativeResolution copy;
    copy.target = source.target;
    copy.sanitize = source.sanitize;
    foreach (ref package_; source.packages)
        copy.packages ~= NativePackage(package_.name, package_.version_, package_.recipeRevision,
                package_.packageId, package_.packageRevision, package_.sourceSha256, package_.binarySha256,
                package_.license, package_.linkage, package_.folder, package_.direct,
                package_.requesters.dup, package_.dependencies.dup, package_.archives.dup);
    copy.linkFlags = source.linkFlags.dup;
    copy.includeDirs = source.includeDirs.dup;
    copy.nonPortable = source.nonPortable.dup;
    copy.bundled = source.bundled.dup;
    return copy;
}

/// Resolve the native packages of the project and its dependencies for the host target (the lock records them).
private void resolveProjectNatives(const ref Home home, const ref Manifest manifest,
        ref Resolution resolution, ref Report report)
{
    import flint_tool.engine.target : hostTarget;
    import flint_tool.project.native : NativeRequirement, collectRequirements, resolveNatives;

    string[][string] fromDependencies;
    foreach (ref item; resolution.packages)
    {
        if (item.nativeRecipes.length && !item.testOnly)
            fromDependencies[item.name] = item.nativeRecipes.dup;
    }
    NativeRequirement[] requirements;
    if (!collectRequirements(manifest, fromDependencies, requirements, report) || requirements.length == 0)
        return;
    resolveNatives(home, manifest, requirements, hostTarget(), false, resolution.natives, report);
}

/// Add every core package reachable from a direct, path or remote dependency.
private void addCoreClosure(const ref Home home, ref ResolvedPackage[string] found, bool workspace)
{
    addExtensions(home, found, workspace);
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

/// Add the starters and Flint Boot libraries that resolved packages depend on, transitively.
private void addExtensions(const ref Home home, ref ResolvedPackage[string] found, bool workspace)
{
    for (bool added = true; added;)
    {
        added = false;
        string[] wanted;
        foreach (name, ref item; found)
        {
            foreach (dependency; item.dependencies)
            {
                if (dependency.length > 6 && dependency[0 .. 6] == "flint:" && dependency !in found)
                    wanted ~= dependency;
            }
        }
        foreach (dependency; wanted)
        {
            auto extension = home.findStarter(dependency[6 .. $]);
            if (extension is null)
                extension = home.findBoot(dependency[6 .. $]);
            if (extension is null || dependency in found)
                continue;
            found[dependency] = starterPackage(home, *extension, workspace);
            added = true;
        }
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
    item.repoRoot = home.repoRoot(meta.repo);
    item.platform = home.platformVersion(meta.repo);
    item.directory = home.packagePath(meta.repo, buildPath("packages", name));
    item.moduleRoot = meta.module_;
    foreach (dependency; meta.dependencies)
        item.dependencies ~= "flint:" ~ dependency;
    if (!workspace)
        item.contentSha256 = contentHash(item.directory, ["dub.sdl", "source/**", "native/**"]);
    return item;
}

// A starter or a Flint Boot library resolves like a core package: a DUB subpackage of the Flint home, under
// starters/ or boot/.
private ResolvedPackage starterPackage(const ref Home home,
        const ref imported!"flint_tool.home.policy".CorePackage meta, bool workspace)
{
    import std.path : buildPath;

    ResolvedPackage item;
    item.name = "flint:" ~ meta.name;
    item.kind = "core";
    item.source = workspace ? "workspace" : "flint-home";
    // Boot libraries and starters resolve from the boot platform module, never by version selection.
    item.repoRoot = home.repoRoot(meta.repo);
    item.platform = home.platformVersion(meta.repo);
    item.directory = home.packagePath(meta.repo, meta.directory);
    item.moduleRoot = meta.module_;
    foreach (dependency; meta.dependencies)
        item.dependencies ~= "flint:" ~ dependency;
    if (!workspace)
        item.contentSha256 = contentHash(item.directory, ["dub.sdl", "source/**", "config.toml"]);
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
    case DependencyKind.dub:
        // Collected like repository paths; the compatibility index selects the versions.
        remotes ~= Requirement(active.length > 1 ? owner.name : null, spec.name, spec.version_);
        return spec.name;
    case DependencyKind.path:
        return resolvePath(home, owner, spec, found, active, remotes, report);
    }
}

/// Select DUB packages through the compatibility index, fetch them through the repository-path cache, verify the
/// pinned commit and tree hash, and scan them with Flint's safety rules.
private bool resolveDub(const ref Home home, const ref Manifest manifest,
        scope const(Requirement)[] requested, ref ResolvedPackage[string] found, ref Report report)
{
    import flint_tool.project.dubindex : DubEntry, DubRequirement, loadIndex, scanPackage, selectDub;
    import flint_tool.project.remote : Fetcher, RemoteModule;

    DubEntry[] entries;
    if (!loadIndex(home, entries, report))
        return false;
    DubRequirement[] roots;
    foreach (ref requirement; requested)
        roots ~= DubRequirement(requirement.from, requirement.path[4 .. $], requirement.version_);
    DubEntry[] selected;
    DubRequirement[] edges;
    if (!selectDub(entries, roots, selected, edges, report))
        return false;
    auto fetcher = Fetcher.forProject(home.root, manifest.root);
    foreach (ref entry; selected)
    {
        RemoteModule module_;
        if (!fetcher.materialize(entry.repository, entry.version_, module_, report))
            return false;
        if (module_.commit != entry.commit || module_.contentSha256 != entry.treeSha256)
        {
            const actual = "commit " ~ module_.commit ~ " with tree " ~ module_.contentSha256;
            const pinned = "commit " ~ entry.commit ~ " and tree " ~ entry.treeSha256;
            report.error("FLINT-E0309", "dub:" ~ entry.name ~ " " ~ entry.version_ ~ " from "
                    ~ entry.repository ~ " is " ~ actual ~ ", but the compatibility index pins " ~ pinned,
                    "the release tag moved or the source changed; do not use it until the index entry is reviewed");
            return false;
        }
        ResolvedPackage item;
        item.name = "dub:" ~ entry.name;
        item.kind = "dub";
        item.directory = module_.directory;
        item.declaredPath = entry.repository;
        item.manifestType = "library";
        item.version_ = entry.version_;
        item.commit = entry.commit;
        item.contentSha256 = entry.treeSha256;
        item.license = entry.license;
        item.nativeRecipes = entry.native.dup;
        foreach (dependency; entry.dependencies)
        {
            import std.string : indexOf;

            const at = dependency.indexOf('@');
            item.dependencies ~= "dub:" ~ (at > 0 ? dependency[0 .. at] : dependency);
        }
        const scan = scanPackage(item.directory, home.safety.maxTrustedLines);
        item.safetyFindings = scan.findings;
        item.safetySample = scan.sample.dup;
        found[item.name] = item;
    }
    return true;
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
        item.license = module_.license;
        item.nativeRecipes = module_.natives.dup;
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
    auto extension = home.findStarter(coreName);
    if (extension is null)
        extension = home.findBoot(coreName);
    if (extension !is null)
    {
        if (spec.name !in found)
            found[spec.name] = starterPackage(home, *extension, inside(owner.root, home.root));
        return spec.name;
    }
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
            import flint_tool.project.dubindex : scanPackage;

            item.kind = "local";
            item.contentSha256 = contentHash(directory, ["**"]);
            const scan = scanPackage(directory, home.safety.maxTrustedLines);
            item.safetyFindings = scan.findings;
            item.safetySample = scan.sample.dup;
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
    item.license = nested.license;
    foreach (ref native; nested.natives)
        item.nativeRecipes ~= native.name ~ "@" ~ native.version_;
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
