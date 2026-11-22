/// Repository-path dependencies, Go-style (ADR-021 section 4, ADR-023).
///
/// A dependency is a repository path with a minimum semantic version. Minimal version selection picks, for every
/// module reachable from the project, the highest of the minimums anyone requires: deterministic, offline-capable,
/// and independent of newer tags. Sources are fetched with git into a bare mirror, extracted once into a
/// content-addressed store under the Flint home, and verified against their hash on every use.
module flint_tool.project.remote;

import flint_tool.diagnostics.report : Report;
import flint_tool.home.policy : Home;
import flint_tool.project.manifest : DependencySpec;

@safe:

/// A parsed semantic version.
struct Semver
{
    /// Major version.
    long major;
    /// Minor version.
    long minor;
    /// Patch version.
    long patch;
    /// Prerelease identifiers, or empty.
    string pre;
    /// Canonical text without a leading "v".
    string text;
}

/// Parse `1.4.2`, `v1.4.2` or `1.4.2-rc.1`; build metadata is ignored.
bool parseSemver(string input, out Semver version_)
{
    import std.algorithm.searching : findSplit;
    import std.conv : ConvException, to;
    import flint_tool.project.manifest : semanticVersion;

    string text = input.length && input[0] == 'v' ? input[1 .. $] : input;
    if (!semanticVersion(text))
        return false;
    if (const plus = text.findSplit("+"))
        text = plus[0];
    string core = text;
    if (const dash = text.findSplit("-"))
    {
        core = dash[0];
        version_.pre = dash[2];
    }
    const parts = core.findSplit(".");
    const rest = parts[2].findSplit(".");
    try
    {
        version_.major = parts[0].to!long;
        version_.minor = rest[0].to!long;
        version_.patch = rest[2].to!long;
    }
    catch (ConvException)
        return false;
    version_.text = text;
    return true;
}

/// Semantic version precedence: -1, 0 or 1.
int compareSemver(const ref Semver a, const ref Semver b)
{
    foreach (pair; [[a.major, b.major], [a.minor, b.minor], [a.patch, b.patch]])
    {
        if (pair[0] != pair[1])
            return pair[0] < pair[1] ? -1 : 1;
    }
    if (a.pre == b.pre)
        return 0;
    if (a.pre.length == 0 || b.pre.length == 0)
        return a.pre.length == 0 ? 1 : -1;
    return a.pre < b.pre ? -1 : 1;
}

/// Compare two version texts; unparseable texts sort first.
int compareVersions(string a, string b)
{
    Semver left;
    Semver right;
    const okLeft = parseSemver(a, left);
    const okRight = parseSemver(b, right);
    if (!okLeft || !okRight)
        return okLeft == okRight ? 0 : okLeft ? 1 : -1;
    return compareSemver(left, right);
}

/// One remote module at one version, materialized from the cache or the vendor directory.
struct RemoteModule
{
    /// Repository path.
    string path;
    /// Selected version.
    string version_;
    /// Git commit of the version tag.
    string commit;
    /// Content hash of the source tree.
    string contentSha256;
    /// Directory holding the tree.
    string directory;
    /// The module's project name from its flint.toml.
    string projectName;
    /// The module's SPDX licence expression, or empty.
    string license;
    /// Its D module root.
    string moduleRoot;
    /// "library" or "executable".
    string type;
    /// Its own dependencies: remote and core.
    DependencySpec[] requirements;
}

/// Fetches and caches remote modules.
struct Fetcher
{
    /// Flint home root.
    string home;
    /// FLINT_PROXY base: a URL or path under which repositories are served, or empty for https://<path>.
    string proxy;
    /// No network: only the cache and the vendor directory.
    bool offline;
    /// The project's vendor directory, when `flint deps vendor` created one.
    string vendor;

    /// The fetcher for a project: FLINT_PROXY selects the source, FLINT_PROXY=off works offline.
    static Fetcher forProject(string homeRoot, string projectRoot)
    {
        import std.file : exists;
        import std.path : buildPath;
        import std.process : environment;

        Fetcher fetcher;
        fetcher.home = homeRoot;
        const proxy = environment.get("FLINT_PROXY", "");
        fetcher.offline = proxy == "off" || environment.get("FLINT_OFFLINE", "") == "1";
        fetcher.proxy = proxy == "off" ? null : proxy;
        if (projectRoot.length && exists(buildPath(projectRoot, "vendor", vendorIndexName)))
            fetcher.vendor = buildPath(projectRoot, "vendor");
        return fetcher;
    }

    /// Directory of the cache: FLINT_CACHE, else `<home>/.flint/cache`.
    string cache() const
    {
        import std.path : absolutePath, buildNormalizedPath, buildPath;
        import std.process : environment;

        const relocated = environment.get("FLINT_CACHE", "");
        return relocated.length ? buildNormalizedPath(absolutePath(relocated)) : buildPath(home, ".flint", "cache");
    }

    /// The repository URL for a path.
    string url(string path) const
    {
        import std.algorithm.searching : endsWith;

        if (proxy.length)
            return (proxy.endsWith("/") ? proxy : proxy ~ "/") ~ path;
        return "https://" ~ path;
    }

    /// Materialize `path` at `version_` and read its manifest.
    bool load(const ref Home flint, string path, string version_, string requiredBy,
            out RemoteModule module_, ref Report report)
    {
        return materialize(path, version_, module_, report) && readManifest(flint, module_, requiredBy, report);
    }

    /// Materialize the tree of `path` at tag `version_` from vendor/, the cache or the network, verified by hash.
    bool materialize(string path, string version_, out RemoteModule module_, ref Report report)
    {
        module_.path = path;
        module_.version_ = version_;
        if (fromVendor(module_, report) || fromCache(module_, report))
            return true;
        if (offline)
        {
            report.error("FLINT-E0307",
                    path ~ " " ~ version_ ~ " is not in the dependency cache and the build is " ~ "offline",
                    "fetch it once online, or run flint deps vendor while online");
            return false;
        }
        return fetch(module_, report);
    }

    private bool fromVendor(ref RemoteModule module_, ref Report report)
    {
        import std.path : buildPath;

        if (vendor.length == 0)
            return false;
        foreach (entry; readVendorIndex(vendor))
        {
            if (entry.path != module_.path || entry.version_ != module_.version_)
                continue;
            module_.commit = entry.commit;
            module_.directory = buildPath(vendor, module_.path);
            module_.contentSha256 = entry.contentSha256;
            return verify(module_, "vendor/" ~ module_.path, report);
        }
        return false;
    }

    private bool fromCache(ref RemoteModule module_, ref Report report)
    {
        import std.file : exists;
        import std.path : buildPath;
        import std.string : split, strip;
        import flint_tool.support.files : readIfPresent;

        const record = readIfPresent(indexPath(module_.path, module_.version_));
        if (record is null)
            return false;
        const fields = record.strip.split(" ");
        if (fields.length != 2 || !exists(buildPath(cache(), "content", fields[1])))
            return false;
        module_.commit = fields[0];
        module_.contentSha256 = fields[1];
        module_.directory = buildPath(cache(), "content", fields[1]);
        return verify(module_, module_.directory, report);
    }

    private bool verify(ref RemoteModule module_, string display, ref Report report)
    {
        import flint_tool.project.resolve : contentHash;

        const actual = contentHash(module_.directory, ["**"]);
        if (actual == module_.contentSha256)
            return true;
        report.error("FLINT-E0309", display ~ " (" ~ module_.path ~ " " ~ module_.version_
                ~ ") has content hash " ~ actual ~ " but was recorded as " ~ module_.contentSha256,
                "delete it and fetch again; never edit cached " ~ "or vendored sources");
        module_.directory = null;
        return false;
    }

    private string indexPath(string path, string version_) const
    {
        import std.path : buildPath;

        return buildPath(cache(), "index", key(path), version_);
    }

    private string mirrorPath(string path) const
    {
        import std.path : buildPath;

        return buildPath(cache(), "git", key(path) ~ ".git");
    }

    private bool fetch(ref RemoteModule module_, ref Report report)
    {
        const mirror = mirrorPath(module_.path);
        if (!ensureMirror(module_.path, mirror, report))
            return false;
        module_.commit = tagCommit(mirror, module_.version_);
        if (module_.commit.length == 0)
        {
            git(["--git-dir=" ~ mirror, "fetch", "--quiet", "--tags", "--force", "origin"]);
            module_.commit = tagCommit(mirror, module_.version_);
        }
        if (module_.commit.length == 0)
        {
            report.error("FLINT-E0308", module_.path ~ " has no tag v" ~ module_.version_ ~ " at " ~ url(module_.path),
                    "available versions: " ~ joinVersions(tags(module_.path, report)));
            return false;
        }
        return extract(module_, mirror, report);
    }

    private bool ensureMirror(string path, string mirror, ref Report report)
    {
        import std.file : exists, mkdirRecurse;
        import std.path : dirName;

        if (exists(mirror))
            return true;
        mkdirRecurse(dirName(mirror));
        const cloned = git(["clone", "--quiet", "--mirror", url(path), mirror]);
        if (cloned.length == 0)
            return true;
        report.error("FLINT-E0308", "cannot fetch " ~ path ~ " from " ~ url(path) ~ ": " ~ cloned,
                "check the repository path, or set FLINT_PROXY to a mirror that serves it");
        return false;
    }

    private bool extract(ref RemoteModule module_, string mirror, ref Report report)
    {
        import std.file : exists, mkdirRecurse, remove, rename, rmdirRecurse, write;
        import std.path : buildPath, dirName;
        import std.uuid : randomUUID;
        import flint.os : EnvVar;
        import flint_tool.project.resolve : contentHash;
        import flint_tool.support.process : Launch, capture;

        const staging = buildPath(cache(), "content", ".tmp-" ~ randomUUID().toString());
        mkdirRecurse(staging);
        Launch launch;
        launch.environment = [EnvVar("GIT_INDEX_FILE", staging ~ ".index")];
        const checkout = capture([
            "git", "--git-dir=" ~ mirror, "--work-tree=" ~ staging, "checkout", "--quiet",
            module_.commit, "--", "."
        ], launch);
        if (exists(staging ~ ".index"))
            remove(staging ~ ".index");
        if (!checkout.ok)
        {
            rmdirRecurse(staging);
            report.error("FLINT-E0308",
                    "cannot extract " ~ module_.path ~ " " ~ module_.version_ ~ ": " ~ checkout.combined(),
                    "delete " ~ mirror ~ " and fetch again");
            return false;
        }
        module_.contentSha256 = contentHash(staging, ["**"]);
        module_.directory = buildPath(cache(), "content", module_.contentSha256);
        if (exists(module_.directory))
            rmdirRecurse(staging);
        else
            rename(staging, module_.directory);
        const index = indexPath(module_.path, module_.version_);
        mkdirRecurse(dirName(index));
        write(index, module_.commit ~ " " ~ module_.contentSha256 ~ "\n");
        return true;
    }

    /// Release versions the repository tags, highest last.
    string[] tags(string path, ref Report report)
    {
        import std.algorithm.sorting : sort;
        import std.string : lineSplitter, strip;

        if (offline)
            return cachedVersions(path);
        const mirror = mirrorPath(path);
        if (!ensureMirror(path, mirror, report))
            return null;
        git(["--git-dir=" ~ mirror, "fetch", "--quiet", "--tags", "--force", "origin"]);
        string[] versions;
        foreach (line; gitOutput(["--git-dir=" ~ mirror, "tag", "--list", "v*"]).lineSplitter)
        {
            Semver parsed;
            if (parseSemver(line.strip.idup, parsed) && parsed.pre.length == 0)
                versions ~= parsed.text;
        }
        sort!((a, b) => compareVersions(a, b) < 0)(versions);
        return versions;
    }

    private string[] cachedVersions(string path)
    {
        import std.algorithm.sorting : sort;
        import std.path : baseName, buildPath;
        import flint_tool.support.files : findFiles;

        string[] versions;
        foreach (relative; findFiles(buildPath(cache(), "index", key(path)), "*"))
            versions ~= baseName(relative);
        sort!((a, b) => compareVersions(a, b) < 0)(versions);
        return versions;
    }

    private bool readManifest(const ref Home flint, ref RemoteModule module_, string requiredBy, ref Report report)
    {
        import flint_tool.project.manifest : DependencyKind, Manifest, manifestName, parseManifest;

        Manifest manifest;
        Report nested;
        if (!parseManifest(module_.directory, flint, manifest, nested))
        {
            if (manifest.platform.length && manifest.platform != flint.platform.flint)
            {
                report.error("FLINT-E0107",
                        module_.path ~ " " ~ module_.version_ ~ ", required by " ~ requiredBy ~ ", pins platform "
                        ~ manifest.platform ~ " but this Flint installation provides " ~ flint.platform.flint,
                        "use a version of " ~ module_.path ~ " built for platform " ~ flint.platform.flint);
                return false;
            }
            report.error("FLINT-E0302",
                    module_.path ~ " " ~ module_.version_ ~ " has no valid " ~ manifestName ~ (nested.items.length
                        ? ": " ~ nested.items[0].message : ""), "depend on a Flint library project");
            return false;
        }
        if (manifest.type != "library")
        {
            report.error("FLINT-E0302", module_.path ~ " " ~ module_.version_ ~ " is an executable project",
                    "depend on library projects");
            return false;
        }
        module_.projectName = manifest.name;
        module_.license = manifest.license;
        module_.moduleRoot = manifest.moduleRoot();
        module_.type = manifest.type;
        foreach (ref spec; manifest.dependencies)
        {
            if (spec.kind == DependencyKind.path)
            {
                report.error("FLINT-E0310",
                        module_.path ~ " " ~ module_.version_ ~ " has the path dependency `" ~ spec.name ~ "`",
                        "a published module may depend only on core packages and other repository paths");
                return false;
            }
            module_.requirements ~= spec;
        }
        return true;
    }

    private string git(string[] arguments)
    {
        import flint_tool.support.process : capture;

        const result = capture(["git"] ~ arguments);
        return result.ok ? null : (result.failure ~ result.combined()).idup;
    }

    private string gitOutput(string[] arguments)
    {
        import flint_tool.support.process : capture;

        const result = capture(["git"] ~ arguments);
        return result.ok ? result.output : null;
    }

    private string tagCommit(string mirror, string version_)
    {
        import std.string : strip;

        foreach (tag; ["v" ~ version_, version_])
        {
            const commit = gitOutput([
                "--git-dir=" ~ mirror, "rev-parse", "--verify", "--quiet",
                "refs/tags/" ~ tag ~ "^{commit}"
            ]).strip;
            if (commit.length)
                return commit.idup;
        }
        return null;
    }
}

/// Cache key of a repository path.
string key(string path)
{
    import flint_tool.support.files : sha256Hex;

    return sha256Hex(cast(const(ubyte)[]) path)[0 .. 32];
}

private string joinVersions(scope const(string)[] versions)
{
    import std.array : join;

    return versions.length ? versions.join(", ") : "none";
}

/// The vendor index file name.
enum vendorIndexName = "flint-vendor.toml";

/// One vendored module.
struct VendorEntry
{
    /// Repository path.
    string path;
    /// Version.
    string version_;
    /// Commit.
    string commit;
    /// Content hash.
    string contentSha256;
    /// "dub" for DUB packages from the compatibility index; empty for repository-path modules.
    string kind;
}

/// Read vendor/flint-vendor.toml.
VendorEntry[] readVendorIndex(string vendor)
{
    import std.path : buildPath;
    import flint.serde : DecodeOptions, UnknownFields;
    import flint.serde.owned : deserialize, readTomlEntries;
    import flint_tool.support.files : readIfPresent;

    static struct Row
    {
        string path;
        string version_number;
        string commit;
        string content_sha256;
        string kind;
    }

    const text = readIfPresent(buildPath(vendor, vendorIndexName));
    const entries = readTomlEntries(text);
    VendorEntry[] result;
    if (!entries.ok)
        return null;
    foreach (ref entry; entries.value)
    {
        if (entry.path.length != 1 || entry.path[0] != "module")
            continue;
        const rows = deserialize!(Row[])(entry.json);
        if (!rows.ok)
            return null;
        foreach (ref row; rows.value)
            result ~= VendorEntry(row.path, row.version_number, row.commit, row.content_sha256, row.kind);
    }
    return result;
}

/// A requirement edge in the module graph.
struct Requirement
{
    /// Requiring module ("" for the project).
    string from;
    /// Required repository path.
    string path;
    /// Minimum version required.
    string version_;
}

/// The result of minimal version selection.
struct Selection
{
    /// Selected modules by repository path.
    RemoteModule[string] modules;
    /// Every requirement edge seen, including those of versions not selected.
    Requirement[] edges;
}

/// Minimal version selection over every module reachable from `roots`. With a vendor directory, the vendored set is
/// the build list, as Go's -mod=vendor treats vendor/modules.txt; every requirement must be satisfied by it.
bool selectVersions(ref Fetcher fetcher, const ref Home home, scope const(Requirement)[] roots,
        out Selection selection, ref Report report)
{
    if (fetcher.vendor.length)
        return vendoredSelection(fetcher, home, roots, selection, report);
    RemoteModule[string] loaded;
    string[string] highest;
    Requirement[] queue = roots.dup;
    bool[string] visited;
    while (queue.length)
    {
        const requirement = queue[0];
        queue = queue[1 .. $];
        selection.edges ~= requirement;
        const node = requirement.path ~ "@" ~ requirement.version_;
        if (requirement.path !in highest || compareVersions(requirement.version_, highest[requirement.path]) > 0)
            highest[requirement.path] = requirement.version_;
        if (node in visited)
            continue;
        visited[node] = true;
        RemoteModule module_;
        if (!fetcher.load(home, requirement.path, requirement.version_, requester(requirement), module_, report))
            return false;
        loaded[node] = module_;
        foreach (ref spec; module_.requirements)
        {
            import flint_tool.project.manifest : DependencyKind;

            if (spec.kind == DependencyKind.remote)
                queue ~= Requirement(requirement.path, spec.name, spec.version_);
        }
    }
    foreach (path, version_; highest)
        selection.modules[path] = loaded[path ~ "@" ~ version_];
    return true;
}

private bool vendoredSelection(ref Fetcher fetcher, const ref Home home, scope const(Requirement)[] roots,
        out Selection selection, ref Report report)
{
    import flint_tool.project.manifest : DependencyKind;

    foreach (entry; readVendorIndex(fetcher.vendor))
    {
        // Vendored DUB packages are selected by the compatibility index, not by minimal version selection.
        if (entry.kind == "dub")
            continue;
        RemoteModule module_;
        if (!fetcher.load(home, entry.path, entry.version_, "vendor/" ~ vendorIndexName, module_, report))
            return false;
        selection.modules[entry.path] = module_;
    }
    Requirement[] all = roots.dup;
    foreach (path, ref module_; selection.modules)
    {
        foreach (ref spec; module_.requirements)
        {
            if (spec.kind == DependencyKind.remote)
                all ~= Requirement(path, spec.name, spec.version_);
        }
    }
    foreach (ref requirement; all)
    {
        selection.edges ~= requirement;
        const vendored = requirement.path in selection.modules;
        if (vendored is null || compareVersions(vendored.version_, requirement.version_) < 0)
        {
            report.error("FLINT-E0307", requester(requirement) ~ " requires " ~ requirement.path ~ " >= "
                    ~ requirement.version_ ~ " but vendor/ holds " ~ (vendored is null
                        ? "no copy" : vendored.version_), "run flint deps vendor again");
            return false;
        }
    }
    return true;
}

/// "the project" or the requiring module path.
string requester(const ref Requirement requirement)
{
    return requirement.from.length ? requirement.from : "the project";
}
