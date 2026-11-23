/// The DUB compatibility index (ADR-021 sections 4 and 5, ADR-023): curated DUB package versions that Flint
/// projects may use as `"dub:<name>" = "<version>"`.
///
/// Each entry pins the package's repository, release tag, tag commit and tree hash, its licence, the exact index
/// versions of the DUB packages it needs and the Flint native recipes that replace its `libs`/`systemDependencies`.
/// Packages are fetched through the repository-path cache and checked with Flint's safety rules; one that fails
/// them builds only with an `[unchecked]` waiver.
module flint_tool.project.dubindex;

import flint_tool.diagnostics.report : Report;
import flint_tool.home.policy : Home;

@safe:

/// The curated index, relative to the Flint home.
enum indexFile = "policy/dub-index.toml";

/// One indexed DUB package version.
struct DubEntry
{
    /// DUB package name.
    string name;
    /// Version.
    string version_;
    /// Repository path, such as github.com/dlang-community/tinyendian.
    string repository;
    /// The release tag's commit.
    string commit;
    /// Tree hash of the checkout (flint's content hash).
    string treeSha256;
    /// SPDX licence expression.
    string license;
    /// Required index packages, as name@version.
    string[] dependencies;
    /// Flint native recipes the package links, as name@version.
    string[] native;
    /// Where the entry came from: the policy file, or FLINT_DUB_INDEX.
    string source;
}

/// Load the curated index and, when FLINT_DUB_INDEX names one, an additional private index.
bool loadIndex(const ref Home home, out DubEntry[] entries, ref Report report)
{
    import std.path : buildPath;
    import std.process : environment;

    if (!readIndex(buildPath(home.root, indexFile), indexFile, entries, report))
        return false;
    const extra = environment.get("FLINT_DUB_INDEX", "");
    return extra.length == 0 || readIndex(extra, extra, entries, report);
}

private bool readIndex(string path, string display, ref DubEntry[] entries, ref Report report)
{
    import flint.serde : DecodeOptions, JsonName, UnknownFields;
    import flint.serde.owned : deserialize, readTomlEntries;
    import flint_tool.support.files : readIfPresent;

    static struct Row
    {
        string name;
        @JsonName("version")
        string version_;
        string repository;
        string commit;
        string tree_sha256;
        string license;
        string[] dependencies;
        string[] native;
    }

    const text = readIfPresent(path);
    if (text is null)
    {
        report.error("FLINT-E0809", display ~ " is missing", "restore it, or unset FLINT_DUB_INDEX");
        return false;
    }
    const parsed = readTomlEntries(text);
    if (!parsed.ok)
    {
        report.error("FLINT-E0809", display ~ ": " ~ parsed.error.message, "fix the index file");
        return false;
    }
    foreach (ref entry; parsed.value)
    {
        if (entry.path.length != 1 || entry.path[0] != "package")
            continue;
        const rows = deserialize!(Row[])(entry.json);
        if (!rows.ok)
        {
            report.error("FLINT-E0809", display ~ ": " ~ rows.error.message,
                    "each [[package]] has name, version, " ~ "repository, commit, tree_sha256 and license");
            return false;
        }
        foreach (ref row; rows.value)
            entries ~= DubEntry(row.name, row.version_, row.repository, row.commit,
                    row.tree_sha256, row.license, row.dependencies.dup, row.native.dup, display);
    }
    return true;
}

/// The entry for `name` at `version_`, or null.
const(DubEntry)* find(const DubEntry[] entries, string name, string version_)
{
    foreach (ref entry; entries)
    {
        if (entry.name == name && entry.version_ == version_)
            return &entry;
    }
    return null;
}

/// Versions of `name` the index lists.
string[] versionsOf(scope const DubEntry[] entries, string name)
{
    string[] found;
    foreach (ref entry; entries)
    {
        if (entry.name == name)
            found ~= entry.version_;
    }
    return found;
}

/// One DUB package requirement: who asked for which version.
struct DubRequirement
{
    /// Requester: empty for the project, else `dub:<name>`.
    string from;
    /// DUB package name, without the `dub:` prefix.
    string name;
    /// Exact version.
    string version_;
}

/// The exact versions the requirements select, transitively through the index. Two different versions of one
/// package are a conflict that names both requesters (FLINT-E0315); an unlisted version is FLINT-E0314.
bool selectDub(const DubEntry[] entries, scope const DubRequirement[] roots, out DubEntry[] selected,
        out DubRequirement[] edges, ref Report report)
{
    import std.array : join;
    import std.string : indexOf;

    DubRequirement[] queue = roots.dup;
    DubRequirement[string] chosen;
    while (queue.length)
    {
        const requirement = queue[0];
        queue = queue[1 .. $];
        edges ~= requirement;
        if (auto previous = requirement.name in chosen)
        {
            if (previous.version_ != requirement.version_)
            {
                report.error("FLINT-E0315", "dub:" ~ requirement.name ~ " is required at two versions: " ~ who(
                        *previous) ~ " needs " ~ previous.version_ ~ " and " ~ who(
                        requirement) ~ " needs " ~ requirement.version_,
                        "require one version; the index lists: " ~ versionsOf(entries, requirement.name).join(", "));
                return false;
            }
            continue;
        }
        const entry = find(entries, requirement.name, requirement.version_);
        if (entry is null)
        {
            const listed = versionsOf(entries, requirement.name);
            report.error("FLINT-E0314", "dub:" ~ requirement.name ~ " " ~ requirement.version_ ~ " (required by " ~ who(
                    requirement) ~ ") is not in the DUB compatibility index", listed.length
                    ? "the index lists: " ~ listed.join(", ") : "propose it for "
                    ~ indexFile ~ " with its repository, " ~ "tag commit, tree hash and licence");
            return false;
        }
        chosen[requirement.name] = requirement;
        selected ~= DubEntry(entry.name, entry.version_, entry.repository, entry.commit,
                entry.treeSha256, entry.license, entry.dependencies.dup, entry.native.dup, entry.source);
        foreach (dependency; entry.dependencies)
        {
            const at = dependency.indexOf('@');
            if (at > 0)
                queue ~= DubRequirement("dub:" ~ requirement.name, dependency[0 .. at], dependency[at + 1 .. $]);
        }
    }
    return true;
}

private string who(const ref DubRequirement requirement)
{
    return requirement.from.length ? requirement.from : "the project";
}

/// The result of Flint's safety rules over a DUB package's D sources.
struct SafetyScan
{
    /// D files scanned.
    long files;
    /// Findings.
    long findings;
    /// The first few findings, as "file:line: message".
    string[] sample;
}

/// Run Flint's D safety rules (module `@safe:` defaults, `@trusted` confinement and rationale, string mixins,
/// the ffi boundary) over the D sources of a DUB package checkout.
SafetyScan scanPackage(string directory, long maxTrustedLines)
{
    import std.algorithm.searching : canFind, startsWith;
    import std.conv : to;
    import std.file : readText;
    import std.path : buildPath;
    import flint_tool.check.rules : SourceScan, checkAnnotations, checkDefault, checkMixin, scanSource;
    import flint_tool.diagnostics.report : Report;
    import flint_tool.support.files : findFiles;

    SafetyScan result;
    foreach (relative; findFiles(directory, "**/*.d"))
    {
        if (!(relative.startsWith("source/") || relative.startsWith("src/")))
            continue;
        result.files++;
        Report found;
        SourceScan scan;
        if (scanSource(relative, readText(buildPath(directory, relative)), scan, found))
        {
            const low = scan.moduleName.canFind(".ffi") || scan.moduleName.canFind(".sys")
                || scan.moduleName.canFind(".c.");
            checkDefault(scan, low, found);
            checkMixin(scan, [], found);
            checkAnnotations(scan, low, maxTrustedLines, found);
        }
        foreach (item; found.items)
        {
            result.findings++;
            if (result.sample.length < 3)
                result.sample ~= relative ~ ":" ~ item.line.to!string ~ ": " ~ item.message;
        }
    }
    return result;
}
