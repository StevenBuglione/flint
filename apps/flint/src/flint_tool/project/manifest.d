/// flint.toml, the only manifest of a Flint project (ADR-021 section 2).
module flint_tool.project.manifest;

import flint.serde : DecodeOptions, UnknownFields;
import flint.serde.owned : TomlEntry, deserialize, readTomlEntries;
import flint_tool.diagnostics.report : Report, Severity, at, diagnostic, positionOf;
import flint_tool.home.policy : Home, profileNames;

@safe:

/// The manifest file name.
enum manifestName = "flint.toml";

/// How a dependency is resolved.
enum DependencyKind : ubyte
{
    /// A Flint core package, versioned by the platform.
    core,
    /// A directory holding a Flint project or a local DUB package.
    path,
    /// A repository path with a semantic version (Milestone 8).
    remote
}

/// One declared dependency.
struct DependencySpec
{
    /// Name as written: `flint:log`, or the dependency's own name.
    string name;
    /// Resolution kind.
    DependencyKind kind;
    /// Path as written, for path dependencies.
    string path;
    /// Version as written, for remote dependencies.
    string version_;
    /// One-based manifest line.
    long line;
}

/// Flags a project adds on top of a canonical profile.
struct ProfileOverride
{
    /// Profile name.
    string name;
    /// Added compiler flags.
    string[] dflags;
    /// Added linker flags.
    string[] lflags;
}

/// A waiver of one rule for one file.
struct Waiver
{
    /// The waived code, `FLINT-Ennnn`.
    string rule;
    /// Project-relative file.
    string file;
    /// Why the rule does not apply.
    string reason;
}

/// A local DUB dependency used without passing Flint's safety checks.
struct Unchecked
{
    /// Dependency name.
    string name;
    /// Why it is used anyway.
    string reason;
}

/// A parsed flint.toml.
struct Manifest
{
    /// Absolute project directory.
    string root;
    /// Manifest text.
    string text;
    /// Project name.
    string name;
    /// Project version.
    string version_;
    /// Platform version.
    string platform;
    /// "executable" or "library".
    string type = "executable";
    /// Summary.
    string description;
    /// Executable name override from [build].
    string executable;
    /// Starters, in manifest order.
    string[] starters;
    /// Build dependencies.
    DependencySpec[] dependencies;
    /// Test-only dependencies.
    DependencySpec[] testDependencies;
    /// Profile additions.
    ProfileOverride[] overrides;
    /// Build targets.
    string[] targets;
    /// Rule waivers.
    Waiver[] waivers;
    /// Unchecked local DUB dependencies.
    Unchecked[] unchecked;

    /// D module root: the name with hyphens replaced by underscores.
    string moduleRoot() const
    {
        return moduleRootOf(name);
    }

    /// File name of the built executable or library stem.
    string artifactName() const
    {
        return executable.length ? executable : name;
    }

    /// The additions for `profile`, or an empty override.
    ProfileOverride overrideFor(string profile) const
    {
        foreach (ref item; overrides)
        {
            if (item.name == profile)
                return ProfileOverride(item.name, item.dflags.dup, item.lflags.dup);
        }
        return ProfileOverride(profile);
    }
}

/// The module root of a project name.
string moduleRootOf(string name)
{
    import std.array : replace;

    return name.replace("-", "_");
}

/// Starters and the core packages each scaffolds until starters ship (Milestone 10).
immutable string[][string] starterPackages;

shared static this()
{
    starterPackages = [
        "web": ["web", "http", "di", "config", "log", "serde", "validate"],
        "data": ["data", "sql", "migrate", "config", "log"],
        "security": ["security", "http", "config"],
        "cache": ["cache", "config"],
        "messaging": ["mq", "config", "log"],
        "mail": ["mail", "config"],
        "storage": ["storage", "config"],
        "ai": ["ai", "config"],
        "mcp": ["mcp", "config"],
        "cli": ["cli", "config", "log"],
        "tui": ["tui", "widgets", "style", "term", "prompt"],
        "desktop": ["desktop", "config"],
        "observability": ["actuator", "log"],
    ];
}

/// Targets this release builds.
immutable string[] supportedTargets = ["linux-x86_64-glibc"];

/// Every target name Flint knows.
immutable string[] knownTargets = [
    "linux-x86_64-glibc", "linux-aarch64-glibc", "linux-x86_64-musl", "linux-aarch64-musl",
    "macos-arm64", "windows-x86_64", "wasm32"
];

private immutable string[] sections = [
    "project", "build", "starters", "dependencies", "test-dependencies", "profile", "targets",
    "waivers", "unchecked"
];

private immutable string[] projectKeys = ["name", "version", "flint", "type", "description"];

/// Find the nearest directory at or above `start` holding flint.toml, or null.
string findProjectRoot(string start)
{
    import std.file : exists;
    import std.path : absolutePath, buildNormalizedPath, buildPath, dirName;

    string directory = buildNormalizedPath(absolutePath(start));
    while (true)
    {
        if (exists(buildPath(directory, manifestName)))
            return directory;
        const parent = dirName(directory);
        if (parent == directory)
            return null;
        directory = parent;
    }
}

/// Whether a manifest describes the Flint workspace (a `[workspace]` table) rather than a project.
bool isWorkspaceManifest(string text)
{
    auto entries = readTomlEntries(text);
    if (!entries.ok)
        return false;
    foreach (ref entry; entries.value)
    {
        if (entry.path.length && entry.path[0] == "workspace")
            return true;
    }
    return false;
}

/// Parse and validate flint.toml in `root`.
bool parseManifest(string root, const ref Home home, out Manifest manifest, ref Report report)
{
    import std.file : readText;
    import std.path : buildPath;

    manifest.root = root;
    manifest.text = readText(buildPath(root, manifestName));
    return parseManifestText(manifest.text, home, manifest, report);
}

/// Parse and validate manifest text; `manifest.root` must already be set.
bool parseManifestText(string text, const ref Home home, ref Manifest manifest, ref Report report)
{
    manifest.text = text;
    const before = report.errors();
    const parsed = readTomlEntries(text);
    if (!parsed.ok)
    {
        const where = positionOf(text, parsed.error.offset);
        report.add(at(diagnostic("FLINT-E0102", Severity.error, parsed.error.message,
                "fix the TOML syntax at the location shown"), manifestName, where.line, where.column, text));
        return false;
    }
    Reader reader;
    reader.text = text;
    bool sawProject;
    foreach (ref entry; parsed.value)
    {
        if (entry.path[0] == "project")
            sawProject = true;
        reader.entry(entry, manifest);
    }
    report.merge(reader.found);
    foreach (key; ["name", "version", "flint"])
    {
        const present = key == "name" ? manifest.name.length : key == "version"
            ? manifest.version_.length : manifest.platform.length;
        if (!present)
            report.add(at(diagnostic("FLINT-E0104", Severity.error, "[project] has no `" ~ key ~ "`",
                    "add `" ~ key ~ " = ...` under [project]"), manifestName, sawProject ? 1 : 0));
    }
    if (manifest.platform.length && home.platform.flint.length && manifest.platform != home.platform.flint)
        report.add(at(diagnostic("FLINT-E0107", Severity.error, "the project pins platform "
                ~ manifest.platform ~ " but this Flint installation provides " ~ home.platform.flint,
                "set `flint = \"" ~ home.platform.flint ~ "\"` or use a Flint release providing " ~ manifest.platform),
                manifestName, reader.lineOf("flint"), 0, text));
    return report.errors() == before;
}

private struct WaiverJson
{
    string rule;
    string file;
    string reason;
}

private struct Reader
{
    string text;
    Report found;
    long[string] keyLines;

    long lineOf(string key)
    {
        return key in keyLines ? keyLines[key] : 0;
    }

    void fail(string code, size_t offset, string message, string fix)
    {
        const where = positionOf(text, offset);
        found.add(at(diagnostic(code, Severity.error, message, fix), manifestName, where.line, where.column, text));
    }

    bool str(ref const TomlEntry entry, out string value)
    {
        const decoded = deserialize!string(entry.json);
        if (decoded.ok)
        {
            value = decoded.value;
            return true;
        }
        fail("FLINT-E0105", entry.offset, "`" ~ dotted(entry.path) ~ "` must be a string", "quote the value");
        return false;
    }

    bool strings(ref const TomlEntry entry, out string[] values)
    {
        const decoded = deserialize!(string[])(entry.json);
        if (decoded.ok)
        {
            values = decoded.value.dup;
            return true;
        }
        fail("FLINT-E0105", entry.offset, "`" ~ dotted(entry.path) ~ "` must be an array of strings",
                dotted(entry.path) ~ " = [\"...\"]");
        return false;
    }

    void unknown(ref const TomlEntry entry, string key, scope const(string)[] known, string where)
    {
        const suggestion = closest(key, known);
        fail("FLINT-E0103", entry.offset, "unknown key `" ~ key ~ "` in " ~ where, suggestion.length
                ? "did you mean `" ~ suggestion ~ "`?" : "known keys: " ~ joined(known));
    }

    void entry(ref const TomlEntry entry, ref Manifest manifest)
    {
        const line = positionOf(text, entry.offset).line;
        switch (entry.path[0])
        {
        case "project":
            return project(entry, manifest, line);
        case "build":
            return build(entry, manifest);
        case "starters":
            return starter(entry, manifest);
        case "dependencies":
            return dependency(entry, manifest.dependencies, line);
        case "test-dependencies":
            return dependency(entry, manifest.testDependencies, line);
        case "profile":
            return profile(entry, manifest);
        case "targets":
            return targets(entry, manifest);
        case "waivers":
            return waivers(entry, manifest);
        case "unchecked":
            return unchecked(entry, manifest);
        default:
            unknown(entry, entry.path[0], sections, "flint.toml");
        }
    }

    void build(ref const TomlEntry entry, ref Manifest manifest)
    {
        if (entry.path.length != 2 || entry.path[1] != "executable")
            return unknown(entry, entry.path[$ - 1], ["executable"], "[build]");
        string value;
        if (!str(entry, value))
            return;
        if (!validName(value))
            return fail("FLINT-E0105", entry.offset,
                    "`build.executable` must be a valid file name", "executable = \"shop\"");
        manifest.executable = value;
    }

    void starter(ref const TomlEntry entry, ref Manifest manifest)
    {
        if (entry.path.length < 2)
            return fail("FLINT-E0105", entry.offset, "[starters] must be a table", "[starters]\nweb = {}");
        if (entry.path[1]!in starterPackages)
            return unknown(entry, entry.path[1], starterPackages.keys, "[starters]");
        if (!contains(manifest.starters, entry.path[1]))
            manifest.starters ~= entry.path[1];
    }

    void targets(ref const TomlEntry entry, ref Manifest manifest)
    {
        if (entry.path.length != 2 || entry.path[1] != "default")
            return unknown(entry, entry.path[$ - 1], ["default"], "[targets]");
        string[] values;
        if (!strings(entry, values))
            return;
        foreach (target; values)
        {
            if (!contains(knownTargets, target))
                fail("FLINT-E0110", entry.offset, "unknown target `" ~ target ~ "`",
                        "known targets: " ~ joined(knownTargets));
            else if (!contains(supportedTargets, target))
                fail("FLINT-E0110", entry.offset, "target `" ~ target ~ "` is not built by this release yet",
                        "default = [\"linux-x86_64-glibc\"]");
        }
        manifest.targets = values;
    }

    void unchecked(ref const TomlEntry entry, ref Manifest manifest)
    {
        if (entry.path.length != 2)
            return fail("FLINT-E0109", entry.offset, "[unchecked] maps a dependency name to a reason",
                    "[unchecked]\nlegacy-parser = \"vendored, audited in #12\"");
        string reason;
        if (!str(entry, reason))
            return;
        if (reason.length == 0)
            fail("FLINT-E0109", entry.offset, "[unchecked] `" ~ entry.path[1] ~ "` gives no reason",
                    "state why the dependency is used unchecked");
        manifest.unchecked ~= Unchecked(entry.path[1], reason);
    }

    void project(ref const TomlEntry entry, ref Manifest manifest, long line)
    {
        if (entry.path.length != 2)
            return unknown(entry, dotted(entry.path[1 .. $]), projectKeys, "[project]");
        string value;
        if (!contains(projectKeys, entry.path[1]))
            return unknown(entry, entry.path[1], projectKeys, "[project]");
        if (!str(entry, value))
            return;
        keyLines[entry.path[1]] = line;
        if (entry.path[1] == "name")
            return projectName(entry, manifest, value);
        projectValue(entry, manifest, value);
    }

    void projectValue(ref const TomlEntry entry, ref Manifest manifest, string value)
    {
        switch (entry.path[1])
        {
        case "version":
            if (!semanticVersion(value))
                return fail("FLINT-E0105", entry.offset, "`" ~ value ~ "` is not a semantic version",
                        "version = \"0.1.0\"");
            manifest.version_ = value;
            return;
        case "flint":
            if (!platformVersion(value))
            {
                const message = "`" ~ value ~ "` is not a platform version";
                return fail("FLINT-E0105", entry.offset, message, "flint = \"1.0\"");
            }
            manifest.platform = value;
            return;
        case "type":
            if (value != "executable" && value != "library")
                return fail("FLINT-E0105", entry.offset, "`type` is `executable` or `library`",
                        "type = \"executable\"");
            manifest.type = value;
            return;
        default:
            manifest.description = value;
        }
    }

    void projectName(ref const TomlEntry entry, ref Manifest manifest, string value)
    {
        if (!validName(value))
            return fail("FLINT-E0106", entry.offset, "`" ~ value ~ "` is not a valid project name",
                    "use lower-case letters, digits and hyphens, starting with a letter: name = \"order-service\"");
        if (reservedRoot(moduleRootOf(value)))
            return fail("FLINT-E0405", entry.offset, "the module root `" ~ moduleRootOf(value) ~ "` is reserved",
                    "choose another name; `flint` belongs to the core libraries");
        manifest.name = value;
    }

    void dependency(ref const TomlEntry entry, ref DependencySpec[] list, long line)
    {
        if (entry.path.length < 2)
            return fail("FLINT-E0105", entry.offset, "dependencies are a table of named entries",
                    "[dependencies]\n\"flint:log\" = {}");
        const name = entry.path[1];
        if (declaredTwice(list, name))
            return fail("FLINT-E0105", entry.offset, "dependency `" ~ name ~ "` is declared twice", "keep one entry");
        const core = name.length > 6 && name[0 .. 6] == "flint:";
        if (!core && !validName(name))
            return fail("FLINT-E0105", entry.offset, "`" ~ name ~ "` is not a valid dependency name",
                    "use lower-case letters, digits and hyphens");
        if (entry.path.length == 2)
            return versioned(entry, list, name, core, line);
        if (entry.path.length != 3 || entry.path[2] != "path")
            return unknown(entry, entry.path[$ - 1], ["path"], "dependency `" ~ name ~ "`");
        string path;
        if (!str(entry, path))
            return;
        if (core)
            return fail("FLINT-E0305", entry.offset,
                    "core package `" ~ name ~ "` cannot be redirected to a path", "\"" ~ name ~ "\" = {}");
        if (path.length == 0)
            return fail("FLINT-E0302", entry.offset, "`" ~ name ~ "` has an empty path", "path = \"../" ~ name ~ "\"");
        list ~= DependencySpec(name, DependencyKind.path, path, null, line);
    }

    static bool declaredTwice(scope const DependencySpec[] list, string name)
    {
        foreach (ref existing; list)
        {
            if (existing.name == name)
                return true;
        }
        return false;
    }

    /// A dependency written as `{}` (core) or as a version string (core: error; others: Milestone 8).
    void versioned(ref const TomlEntry entry, ref DependencySpec[] list, string name, bool core, long line)
    {
        if (entry.json == "{}")
        {
            if (!core)
                return fail("FLINT-E0302", entry.offset, "`" ~ name ~ "` gives no path",
                        "\"" ~ name ~ "\" = { path = \"../" ~ name ~ "\" }");
            list ~= DependencySpec(name, DependencyKind.core, null, null, line);
            return;
        }
        string versionText;
        if (!str(entry, versionText))
            return;
        if (core)
            return fail("FLINT-E0305", entry.offset,
                    "`" ~ name ~ "` = \"" ~ versionText ~ "\": core packages take no version", "\"" ~ name ~ "\" = {}");
        fail("FLINT-E0303", entry.offset,
                "`" ~ name ~ "` = \"" ~ versionText ~ "\" needs the remote resolver of Milestone 8",
                "\"" ~ name ~ "\" = { path = \"../" ~ name ~ "\" }");
    }

    void profile(ref const TomlEntry entry, ref Manifest manifest)
    {
        if (entry.path.length != 3)
            return fail("FLINT-E0105", entry.offset, "profile additions are [profile.<name>] dflags and lflags",
                    "[profile.release]\ndflags = [\"-mcpu=native\"]");
        const name = entry.path[1];
        if (!contains(profileNames, name))
        {
            const suggestion = closest(name, profileNames);
            return fail("FLINT-E0108", entry.offset, "unknown profile `" ~ name ~ "`", suggestion.length
                    ? "did you mean `" ~ suggestion ~ "`?" : "profiles: " ~ joined(profileNames));
        }
        if (entry.path[2] != "dflags" && entry.path[2] != "lflags")
            return unknown(entry, entry.path[2], ["dflags", "lflags"], "[profile." ~ name ~ "]");
        string[] values;
        if (!strings(entry, values))
            return;
        size_t index = manifest.overrides.length;
        foreach (i, ref existing; manifest.overrides)
        {
            if (existing.name == name)
                index = i;
        }
        if (index == manifest.overrides.length)
            manifest.overrides ~= ProfileOverride(name);
        if (entry.path[2] == "dflags")
            manifest.overrides[index].dflags = values;
        else
            manifest.overrides[index].lflags = values;
    }

    void waivers(ref const TomlEntry entry, ref Manifest manifest)
    {
        import flint_tool.diagnostics.catalog : lookup;

        DecodeOptions options;
        options.unknownFields = UnknownFields.reject;
        const decoded = deserialize!(WaiverJson[])(entry.json, options);
        if (entry.path.length != 1 || !decoded.ok)
            return fail("FLINT-E0109", entry.offset, "waivers are [[waivers]] tables with rule, file and reason",
                    "[[waivers]]\nrule = \"FLINT-E0502\"\nfile = \"src/shop/legacy.d\"\nreason = \"...\"");
        foreach (waiver; decoded.value)
        {
            if (lookup(waiver.rule) is null)
                fail("FLINT-E0109", entry.offset, "waiver names unknown rule `" ~ waiver.rule ~ "`",
                        "flint explain --list");
            else if (waiver.file.length == 0 || waiver.reason.length == 0)
                fail("FLINT-E0109", entry.offset, "waiver of " ~ waiver.rule ~ " needs a file and a reason",
                        "file = \"src/...\"\nreason = \"...\"");
            else
                manifest.waivers ~= Waiver(lookup(waiver.rule).code, waiver.file, waiver.reason);
        }
    }
}

/// Whether a project or executable name is valid.
bool validName(scope const(char)[] name)
{
    if (name.length == 0 || name.length > 64 || !(name[0] >= 'a' && name[0] <= 'z') || name[$ - 1] == '-')
        return false;
    foreach (i, ch; name)
    {
        if (!((ch >= 'a' && ch <= 'z') || (ch >= '0' && ch <= '9') || ch == '-'))
            return false;
        if (ch == '-' && i && name[i - 1] == '-')
            return false;
    }
    return true;
}

/// Whether a module root is reserved: the core libraries' root or a D keyword.
bool reservedRoot(scope const(char)[] root)
{
    static immutable string[] keywords = [
        "flint", "abstract", "alias", "align", "asm", "assert", "auto", "body", "bool", "break",
        "byte", "case", "cast", "catch", "cdouble", "cent", "cfloat", "char", "class", "const",
        "continue", "creal", "dchar", "debug", "default", "delegate", "delete", "deprecated",
        "do", "double", "else", "enum", "export", "extern", "false", "final", "finally", "float",
        "for", "foreach", "foreach_reverse", "function", "goto", "idouble", "if", "ifloat",
        "immutable", "import", "in", "inout", "int", "interface", "invariant", "ireal", "is",
        "lazy", "long", "macro", "mixin", "module", "new", "nothrow", "null", "out", "override",
        "package", "pragma", "private", "protected", "public", "pure", "real", "ref", "return",
        "scope", "shared", "short", "static", "struct", "super", "switch", "synchronized",
        "template", "this", "throw", "true", "try", "typeid", "typeof", "ubyte", "ucent", "uint",
        "ulong", "union", "unittest", "ushort", "version", "void", "wchar", "while", "with",
        "core", "std", "etc", "object"
    ];
    foreach (keyword; keywords)
    {
        if (root == keyword)
            return true;
    }
    return false;
}

/// Whether `text` is a semantic version.
bool semanticVersion(string text)
{
    import std.regex : ctRegex, matchFirst;

    enum pattern = ctRegex!`^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$`;
    return !matchFirst(text, pattern).empty;
}

/// Whether `text` is a platform version `major.minor`.
bool platformVersion(string text)
{
    import std.regex : ctRegex, matchFirst;

    enum pattern = ctRegex!`^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$`;
    return !matchFirst(text, pattern).empty;
}

/// The known word closest to `word`, when it is plausibly a typo.
string closest(string word, scope const(string)[] known)
{
    import std.algorithm.comparison : levenshteinDistance;

    string best;
    size_t bestDistance = size_t.max;
    foreach (candidate; known)
    {
        const distance = levenshteinDistance(word, candidate);
        if (distance < bestDistance)
        {
            bestDistance = distance;
            best = candidate;
        }
    }
    return bestDistance <= (word.length > 4 ? 2 : 1) ? best : null;
}

private bool contains(scope const(string)[] list, scope const(char)[] value)
{
    foreach (item; list)
    {
        if (item == value)
            return true;
    }
    return false;
}

private string joined(scope const(string)[] list)
{
    import std.algorithm.sorting : sort;
    import std.array : join;

    auto copy = list.dup;
    sort(copy);
    return copy.join(", ");
}

private string dotted(scope const(string)[] path)
{
    import std.array : join;

    return path.join(".");
}
