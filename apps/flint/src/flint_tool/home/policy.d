/// The Flint installation ("home") and the policy files flint enforces.
module flint_tool.home.policy;

import flint.arena : Error, Status;
import flint.config : ConfigOptions, ConfigurationProperties, Required, load;
import flint.serde : DecodeOptions, UnknownFields;
import flint.serde.json_visit : JsonMemberName, visitJsonObjectRanges;
import flint.serde.owned : deserialize;
import flint_tool.diagnostics.report : Report;

@safe:

/// One core package from policy/packages.json.
struct CorePackage
{
    /// DUB subpackage name, such as "wasm-bridge".
    string name;
    /// Architecture tier.
    long tier;
    /// Root D module, such as "flint.wasm_bridge".
    string module_;
    /// Direct dependencies by package name.
    string[] dependencies;
    /// Usable from BetterC.
    bool betterC;
    /// Home-relative directory: `packages/<name>`, or `starters/<domain>` for a starter.
    string directory;
    /// A starter (policy/boot.json): a code-free dependency bundle and a configuration section (ADR-029).
    bool starter;
    /// A Flint Boot library (policy/boot.json): the runner, an auto-configuration or the actuator (ADR-029).
    bool boot;
    /// For a starter: the configuration section it reads, and the one-line summary `flint add` shows.
    string section;
    /// For a starter: what it wires.
    string summary;
    /// For a starter: its auto-configuration lists, as `module:Symbol` (ADR-029 section 2).
    string[] autoconfiguration;
    /// The repo the package belongs to after the split (policy/repos.json, plan section 7): flint, framework, boot,
    /// or a portfolio repo.
    string repo;
}

/// A repo of the split and the repos it may depend on (policy/repos.json).
struct RepoPolicy
{
    /// Short name: flint, framework, boot, security, ...
    string name;
    /// Repos this repo's packages may depend on, besides its own.
    string[] mayDependOn;
}

/// A dependency that crosses repos the wrong way while the coordinator decides it.
struct PendingEdge
{
    /// The depending package.
    string from;
    /// The dependency.
    string to;
    /// Why it is pending.
    string reason;
}

/// The safety rules from policy/safety-policy.json.
struct SafetyPolicy
{
    /// Per package, the module prefixes allowed to contain @trusted and @system.
    string[][string] unsafePrefixes;
    /// Module prefixes allowed to contain string mixins.
    string[] generatorPrefixes;
    /// Longest permitted @trusted body in lines.
    long maxTrustedLines = 60;
}

/// One canonical build profile from policy/profiles.toml.
struct ProfileSpec
{
    /// What the profile is for.
    @Required string description;
    /// Default compiler executable name.
    @Required string compiler;
    /// Compilers `--compiler both` covers.
    string[] compilers;
    /// DUB build type.
    @Required string build_type;
    /// Compiler flags.
    string[] dflags;
    /// Linker flags.
    string[] lflags;
    /// The forked DMD's compile server may be used.
    bool compile_server;
    /// The forked DUB's parallel pipeline may be used.
    bool dub_pipeline;
    /// Native provider profile.
    string native_profile;
    /// Sanitizers of the native providers.
    string native_sanitize;
}

/// An independent copy of a profile.
ProfileSpec copyOf(const ProfileSpec spec)
{
    return ProfileSpec(spec.description, spec.compiler, spec.compilers.dup, spec.build_type,
            spec.dflags.dup, spec.lflags.dup, spec.compile_server, spec.dub_pipeline,
            spec.native_profile, spec.native_sanitize);
}

/// The closed set of canonical profiles.
@ConfigurationProperties("profile")
struct ProfilePolicy
{
    /// Development loop.
    ProfileSpec dev;
    /// Unit tests.
    ProfileSpec test;
    /// Optimised release.
    ProfileSpec release;
    /// Size-optimised release.
    ProfileSpec size;
    /// Sanitizer lane.
    ProfileSpec sanitize;
}

/// The platform identity from policy/platform.toml.
@ConfigurationProperties("platform")
struct PlatformPolicy
{
    /// Platform version a project pins with `flint = "x.y"`.
    @Required string flint;
    /// Flint release.
    @Required string release;
}

/// Profile names in policy order.
immutable string[] profileNames = ["dev", "test", "release", "size", "sanitize"];

/// A loaded Flint installation.
struct Home
{
    /// Absolute root of the Flint checkout.
    string root;
    /// Core packages in policy order.
    CorePackage[] packages;
    /// Flint Boot libraries from policy/boot.json, in policy order (ADR-029 section 8).
    CorePackage[] bootLibraries;
    /// Starters from policy/boot.json, in policy order (ADR-029 section 8).
    CorePackage[] starters;
    /// The repos of the split (policy/repos.json), and the edges pending a decision.
    RepoPolicy[] repos;
    /// ditto
    PendingEdge[] pendingEdges;
    /// Safety rules.
    SafetyPolicy safety;
    /// Pinned tool versions by name.
    string[string] versions;
    /// Canonical profiles.
    ProfilePolicy profiles;
    /// Platform identity.
    PlatformPolicy platform;
    /// SHA-256 of each policy file flint read, by repository-relative path.
    string[string] digests;

    /// The package named `name`, or null.
    const(CorePackage)* find(string name) const
    {
        foreach (ref item; packages)
        {
            if (item.name == name)
                return &item;
        }
        return null;
    }

    /// The package or starter owning module `name`, or null.
    const(CorePackage)* owner(string moduleName) const
    {
        foreach (ref item; packages)
        {
            if (moduleName == item.module_ || startsWithModule(moduleName, item.module_))
                return &item;
        }
        foreach (ref item; bootLibraries)
        {
            if (moduleName == item.module_ || startsWithModule(moduleName, item.module_))
                return &item;
        }
        return null;
    }

    /// The Flint Boot library named `name` (`boot-autoconfigure-web`), or null.
    const(CorePackage)* findBoot(string name) const
    {
        foreach (ref item; bootLibraries)
        {
            if (item.name == name)
                return &item;
        }
        return null;
    }

    /// The starter named `name` (`starter-web`), or null.
    const(CorePackage)* findStarter(string name) const
    {
        foreach (ref item; starters)
        {
            if (item.name == name)
                return &item;
        }
        return null;
    }

    /// The named profile; false when there is none.
    bool profile(string name, out ProfileSpec spec) const
    {
        switch (name)
        {
        case "dev":
            spec = copyOf(profiles.dev);
            return true;
        case "test":
            spec = copyOf(profiles.test);
            return true;
        case "release":
            spec = copyOf(profiles.release);
            return true;
        case "size":
            spec = copyOf(profiles.size);
            return true;
        case "sanitize":
            spec = copyOf(profiles.sanitize);
            return true;
        default:
            return false;
        }
    }

    /// Transitive dependency closure of `names`, including them, in dependency order.
    string[] closure(scope const(string)[] names) const
    {
        string[] ordered;
        bool[string] seen;
        void visit(string name)
        {
            if (name in seen)
                return;
            seen[name] = true;
            const item = find(name);
            if (item is null)
                return;
            foreach (dependency; item.dependencies)
                visit(dependency);
            ordered ~= name;
        }

        foreach (name; names)
            visit(name);
        return ordered;
    }
}

/// Whether `moduleName` is `prefix` or a module below it.
bool startsWithModule(scope const(char)[] moduleName, scope const(char)[] prefix)
{
    return moduleName == prefix || (moduleName.length > prefix.length
            && moduleName[0 .. prefix.length] == prefix && moduleName[prefix.length] == '.');
}

/// Whether `moduleName` matches any of the prefixes.
bool matchesAny(scope const(char)[] moduleName, scope const(string)[] prefixes)
{
    foreach (prefix; prefixes)
    {
        if (startsWithModule(moduleName, prefix))
            return true;
    }
    return false;
}

/// Locate the Flint home: FLINT_HOME, else the nearest ancestor of the flint executable holding the policy.
string findHome()
{
    import std.file : thisExePath;
    import std.path : absolutePath, buildNormalizedPath, dirName;
    import std.process : environment;

    const explicit = environment.get("FLINT_HOME", "");
    if (explicit.length)
        return isHome(explicit) ? buildNormalizedPath(absolutePath(explicit)) : null;
    string directory = dirName(thisExePath());
    while (true)
    {
        if (isHome(directory))
            return directory;
        const parent = dirName(directory);
        if (parent == directory)
            return null;
        directory = parent;
    }
}

/// Whether `directory` holds a Flint installation.
bool isHome(string directory)
{
    import std.file : exists;
    import std.path : buildPath;

    return exists(buildPath(directory, "policy", "packages.json")) && exists(buildPath(directory,
            "policy", "profiles.toml")) && exists(buildPath(directory, "packages"));
}

/// Load every policy file of the home at `root`. Problems are FLINT-E0809.
bool loadHome(string root, out Home home, ref Report report)
{
    home.root = root;
    bool ok = loadPackages(home, report);
    ok = loadStarters(home, report) && ok;
    ok = loadRepos(home, report) && ok;
    ok = loadSafety(home, report) && ok;
    ok = loadVersions(home, report) && ok;
    ok = loadProfiles(home, report) && ok;
    ok = loadPlatform(home, report) && ok;
    return ok;
}

private string policyText(ref Home home, string relative, ref Report report)
{
    import flint_tool.support.files : readIfPresent, sha256Hex;
    import std.path : buildPath;

    const text = readIfPresent(buildPath(home.root, relative));
    if (text is null)
    {
        report.error("FLINT-E0809", relative ~ " is missing from the Flint installation at " ~ home.root);
        return null;
    }
    home.digests[relative] = sha256Hex(cast(const(ubyte)[]) text);
    return text;
}

private DecodeOptions lenient()
{
    DecodeOptions options;
    options.unknownFields = UnknownFields.ignore;
    return options;
}

private bool loadPackages(ref Home home, ref Report report)
{
    const text = policyText(home, "policy/packages.json", report);
    if (text is null)
        return false;
    string failure;
    const top = objectMembers(text, failure);
    const packages = member(top, "packages");
    if (failure.length || packages is null)
        return invalid(report, "policy/packages.json", failure.length ? failure : "has no packages object");
    foreach (entry; objectMembers(packages, failure))
    {
        auto decoded = deserialize!PackageRecordJson(entry.value, lenient());
        if (!decoded.ok)
            return invalid(report, "policy/packages.json", entry.name ~ ": " ~ decoded.error.message);
        home.packages ~= CorePackage(entry.name, decoded.value.tier, decoded.value.module_,
                decoded.value.dependencies, decoded.value.better_c, "packages/" ~ entry.name);
        home.packages[$ - 1].repo = decoded.value.repo.length ? decoded.value.repo : "flint";
    }
    if (failure.length || home.packages.length == 0)
        return invalid(report, "policy/packages.json", failure.length ? failure : "lists no packages");
    return true;
}

// policy/boot.json: the Flint Boot libraries under boot/ and the code-free starters under starters/, each a DUB
// subpackage of the home (ADR-029 section 8).
private bool loadStarters(ref Home home, ref Report report)
{
    import std.file : exists;
    import std.path : buildPath;

    if (!exists(buildPath(home.root, "policy", "boot.json")))
        return true;
    const text = policyText(home, "policy/boot.json", report);
    string failure;
    const top = objectMembers(text, failure);
    foreach (group; ["libraries", "starters"])
    {
        const members = member(top, group);
        if (failure.length || members is null)
            return invalid(report, "policy/boot.json", failure.length ? failure : "has no " ~ group ~ " object");
        foreach (entry; objectMembers(members, failure))
        {
            auto decoded = deserialize!BootRecordJson(entry.value, lenient());
            if (!decoded.ok)
                return invalid(report, "policy/boot.json", entry.name ~ ": " ~ decoded.error.message);
            CorePackage item;
            item.name = entry.name;
            item.module_ = decoded.value.module_;
            item.dependencies = decoded.value.dependencies;
            item.directory = decoded.value.directory;
            item.section = decoded.value.section;
            item.summary = decoded.value.summary;
            item.autoconfiguration = decoded.value.autoconfiguration;
            item.repo = decoded.value.repo.length ? decoded.value.repo : "boot";
            item.starter = group == "starters";
            item.boot = !item.starter;
            item.tier = item.starter ? 6 : 5;
            if (item.starter)
                home.starters ~= item;
            else
                home.bootLibraries ~= item;
        }
    }
    return failure.length == 0 || invalid(report, "policy/boot.json", failure);
}

private struct BootRecordJson
{
    import flint.serde : JsonName;

    @JsonName("module") string module_;
    string directory;
    string[] dependencies;
    string section;
    string summary;
    string[] autoconfiguration;
    string repo;
}

private struct RepoRecordJson
{
    string[] may_depend_on;
}

private struct PendingEdgeJson
{
    string from;
    string to;
    string reason;
}

// policy/repos.json: the repos of the split and which may depend on which (plan section 7).
private bool loadRepos(ref Home home, ref Report report)
{
    import std.file : exists;
    import std.path : buildPath;

    if (!exists(buildPath(home.root, "policy", "repos.json")))
        return true;
    const text = policyText(home, "policy/repos.json", report);
    string failure;
    const top = objectMembers(text, failure);
    foreach (entry; objectMembers(member(top, "repos"), failure))
    {
        auto decoded = deserialize!RepoRecordJson(entry.value, lenient());
        if (!decoded.ok)
            return invalid(report, "policy/repos.json", entry.name ~ ": " ~ decoded.error.message);
        home.repos ~= RepoPolicy(entry.name, decoded.value.may_depend_on);
    }
    const pending = member(top, "pending_edges");
    if (pending !is null)
    {
        auto decoded = deserialize!(PendingEdgeJson[])(pending, lenient());
        if (!decoded.ok)
            return invalid(report, "policy/repos.json", "pending_edges: " ~ decoded.error.message);
        foreach (ref edge; decoded.value)
            home.pendingEdges ~= PendingEdge(edge.from, edge.to, edge.reason);
    }
    return failure.length == 0 || invalid(report, "policy/repos.json", failure);
}

private struct PackageRecordJson
{
    import flint.serde : JsonName;

    long tier;
    @JsonName("module") string module_;
    string[] dependencies;
    bool better_c;
    string repo;
}

private struct SafetyRecord
{
    string[] generator_module_prefixes;
    long max_trusted_lines;
}

private bool loadSafety(ref Home home, ref Report report)
{
    const text = policyText(home, "policy/safety-policy.json", report);
    if (text is null)
        return false;
    auto decoded = deserialize!SafetyRecord(text, lenient());
    if (!decoded.ok)
        return invalid(report, "policy/safety-policy.json", decoded.error.message);
    home.safety.generatorPrefixes = decoded.value.generator_module_prefixes;
    home.safety.maxTrustedLines = decoded.value.max_trusted_lines;
    string failure;
    const prefixes = member(objectMembers(text, failure), "unsafe_module_prefixes");
    if (failure.length || prefixes is null)
        return invalid(report, "policy/safety-policy.json", failure.length ? failure : "has no unsafe_module_prefixes");
    foreach (entry; objectMembers(prefixes, failure))
    {
        auto list = deserialize!(string[])(entry.value);
        if (!list.ok)
            return invalid(report, "policy/safety-policy.json", entry.name ~ ": " ~ list.error.message);
        home.safety.unsafePrefixes[entry.name] = list.value;
    }
    return failure.length == 0 || invalid(report, "policy/safety-policy.json", failure);
}

private bool loadVersions(ref Home home, ref Report report)
{
    const text = policyText(home, "policy/toolchains.json", report);
    if (text is null)
        return false;
    string failure;
    const versions = member(objectMembers(text, failure), "versions");
    if (failure.length || versions is null)
        return invalid(report, "policy/toolchains.json", failure.length ? failure : "has no versions object");
    foreach (entry; objectMembers(versions, failure))
    {
        auto value = deserialize!string(entry.value);
        if (!value.ok)
            return invalid(report, "policy/toolchains.json", entry.name ~ ": " ~ value.error.message);
        home.versions[entry.name] = value.value;
    }
    foreach (required; ["dmd", "ldc", "dub", "dfmt", "dscanner"])
    {
        if (required !in home.versions)
            return invalid(report, "policy/toolchains.json", "does not pin " ~ required);
    }
    return failure.length == 0 || invalid(report, "policy/toolchains.json", failure);
}

private ConfigOptions policyFile(string root, string baseName)
{
    import std.path : buildPath;

    ConfigOptions options;
    options.directory = buildPath(root, "policy");
    options.baseName = baseName;
    options.readEnvironment = false;
    options.profile = "canonical";
    return options;
}

private bool loadProfiles(ref Home home, ref Report report)
{
    if (policyText(home, "policy/profiles.toml", report) is null)
        return false;
    const options = policyFile(home.root, "profiles");
    auto loaded = load!ProfilePolicy(options);
    if (!loaded.ok)
        return invalid(report, "policy/profiles.toml", loaded.error.message);
    home.profiles = loaded.value;
    foreach (name; profileNames)
    {
        ProfileSpec spec;
        home.profile(name, spec);
        bool listed;
        foreach (compiler; spec.compilers)
            listed = listed || compiler == spec.compiler;
        if (!listed || (spec.compiler != "dmd" && spec.compiler != "ldc2"))
            return invalid(report, "policy/profiles.toml",
                    name ~ ": compiler must be dmd or ldc2 and listed in compilers");
    }
    return true;
}

private bool loadPlatform(ref Home home, ref Report report)
{
    if (policyText(home, "policy/platform.toml", report) is null)
        return false;
    const options = policyFile(home.root, "platform");
    auto loaded = load!PlatformPolicy(options);
    if (!loaded.ok)
        return invalid(report, "policy/platform.toml", loaded.error.message);
    home.platform = loaded.value;
    return true;
}

private bool invalid(ref Report report, string file, string message)
{
    report.error("FLINT-E0809", file ~ ": " ~ message,
            "restore the file from the Flint release: git checkout -- " ~ file);
    return false;
}

/// One member of a JSON object: its decoded name and its raw value text.
struct Member
{
    /// Decoded member name.
    string name;
    /// The member's JSON value, as written.
    string value;
}

/// The value of member `name`, or null.
string member(scope const Member[] members, string name)
{
    foreach (ref item; members)
    {
        if (item.name == name)
            return item.value;
    }
    return null;
}

/// Members of a JSON object in source order, through flint.serde's validating visitor.
Member[] objectMembers(string json, ref string failure)
{
    static struct Span
    {
        size_t name;
        size_t nameLength;
        size_t offset;
        size_t length;
    }

    auto spans = new Span[1024];
    auto names = new ubyte[64 * 1024];
    size_t count;
    size_t used;
    DecodeOptions options;
    options.maxBytes = 4 << 20;
    const error = visitJsonObjectRanges(cast(const(ubyte)[]) json, (scope JsonMemberName name,
            size_t offset, size_t length) @safe nothrow @nogc {
        if (count == spans.length || used + name.length > names.length)
            return Error(Status.resourceExhausted, "JSON object has too many members for flint's policy reader");
        if (!name.copyName(names[used .. used + name.length]))
            return Error(Status.invalidArgument, "invalid JSON member name");
        spans[count++] = Span(used, name.length, offset, length);
        used += name.length;
        return Error.init;
    }, options);
    if (error.code != Status.ok)
    {
        failure = error.message;
        return null;
    }
    Member[] members;
    foreach (ref span; spans[0 .. count])
        members ~= Member((cast(const(char)[]) names[span.name .. span.name + span.nameLength]).idup,
                json[span.offset .. span.offset + span.length]);
    return members;
}
