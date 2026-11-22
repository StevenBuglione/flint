/// Native (C and C++) packages: `[native]` in flint.toml, resolved by Flint's native resolver (ADR-021 section 4,
/// ADR-023).
///
/// flint collects every requirement (the project's `[native]`, its path and repository dependencies' `[native]` and
/// the native recipes of indexed DUB packages), refuses two versions of one package by naming both requesters, and
/// hands the rest to tools/native_resolver.py, which drives an isolated Conan against Flint's recipe index and
/// answers in JSON. Conan itself never appears in flint's output. `system = true` takes the host's library through
/// pkg-config instead, and marks the build non-portable.
module flint_tool.project.native;

import flint_tool.diagnostics.report : Report;
import flint_tool.home.policy : Home;
import flint_tool.project.manifest : Manifest;

@safe:

/// One native requirement and who made it.
struct NativeRequirement
{
    /// Recipe name.
    string name;
    /// Exact version.
    string version_;
    /// "the project" or the requiring dependency.
    string requester;
}

/// One resolved native package.
struct NativePackage
{
    /// Recipe name.
    string name;
    /// Version.
    string version_;
    /// Recipe revision in Flint's index.
    string recipeRevision;
    /// Binary package ID (settings, options and dependencies).
    string packageId;
    /// Binary package revision.
    string packageRevision;
    /// SHA-256 of the pinned source archive.
    string sourceSha256;
    /// Content hash of the binary package.
    string binarySha256;
    /// SPDX licence expression.
    string license;
    /// "static", "bundled" or "system".
    string linkage = "static";
    /// Absolute package directory.
    string folder;
    /// Requested by the project itself, rather than only through a dependency.
    bool direct;
    /// Who requires it.
    string[] requesters;
    /// Native packages it depends on.
    string[] dependencies;
    /// Absolute static archives, for static and bundled packages.
    string[] archives;
}

/// The native packages of one build.
struct NativeResolution
{
    /// Target they were resolved for.
    string target;
    /// Built with ASan and UBSan.
    bool sanitize;
    /// Packages in dependency order.
    NativePackage[] packages;
    /// Linker flags: archives, bundled libraries and system libraries.
    string[] linkFlags;
    /// Header directories, for embedded C.
    string[] includeDirs;
    /// Why the build is not portable (system packages).
    string[] nonPortable;
    /// Packages linked as bundled shared libraries.
    string[] bundled;
}

/// Collect native requirements: the project's `[native]` and each dependency's (`dependencyNatives` maps a
/// dependency name to its name@version list). Two versions of one package are FLINT-E0320.
bool collectRequirements(const ref Manifest manifest, const string[][string] dependencyNatives,
        out NativeRequirement[] requirements, ref Report report)
{
    import std.algorithm.sorting : sort;
    import std.string : indexOf;

    foreach (ref native; manifest.natives)
        requirements ~= NativeRequirement(native.name, native.version_, "the project");
    foreach (name; sort(dependencyNatives.keys.dup))
    {
        foreach (text; dependencyNatives[name])
        {
            const at = text.indexOf('@');
            if (at > 0)
                requirements ~= NativeRequirement(text[0 .. at], text[at + 1 .. $], name);
        }
    }
    foreach (i, ref first; requirements)
    {
        foreach (ref second; requirements[i + 1 .. $])
        {
            if (first.name == second.name && first.version_ != second.version_)
            {
                report.error("FLINT-E0320", "native package " ~ first.name ~ " is required at two versions: "
                        ~ first.requester ~ " needs " ~ first.version_ ~ " and " ~ second.requester
                        ~ " needs " ~ second.version_,
                        "make both require the same version; flint never picks one silently");
                return false;
            }
        }
    }
    return true;
}

/// Resolve `requirements` for `target`: system packages through pkg-config, the rest through the resolver.
bool resolveNatives(const ref Home home, const ref Manifest manifest, scope const NativeRequirement[] requirements,
        string target, bool sanitize, out NativeResolution resolution, ref Report report)
{
    resolution.target = target;
    resolution.sanitize = sanitize;
    string[] references;
    bool[string] seen;
    foreach (ref requirement; requirements)
    {
        if (requirement.name in seen)
            continue;
        seen[requirement.name] = true;
        if (systemPackage(manifest, requirement.name))
            continue;
        references ~= requirement.name ~ "/" ~ requirement.version_;
    }
    if (references.length && !runResolver(home, target, sanitize, references, resolution, report))
        return false;
    foreach (ref package_; resolution.packages)
    {
        foreach (ref requirement; requirements)
        {
            if (requirement.name != package_.name)
                continue;
            package_.requesters ~= requirement.requester;
            package_.direct = package_.direct || requirement.requester == "the project";
        }
        package_.linkage = linkageOf(manifest, package_.name);
    }
    foreach (ref native; manifest.natives)
    {
        if (native.system && !systemLibrary(native.name, native.version_, resolution, report))
            return false;
    }
    return true;
}

private bool systemPackage(const ref Manifest manifest, string name)
{
    foreach (ref native; manifest.natives)
    {
        if (native.name == name)
            return native.system;
    }
    return false;
}

private string linkageOf(const ref Manifest manifest, string name)
{
    foreach (ref native; manifest.natives)
    {
        if (native.name == name)
            return native.linkage;
    }
    return "static";
}

/// The JSON tools/native_resolver.py prints.
private struct ResolverPackage
{
    string name;
    string version_number;
    string recipe_revision;
    string package_id;
    string package_revision;
    string source_sha256;
    string binary_sha256;
    string license;
    string package_folder;
    string[] dependencies;
}

private struct ResolverError
{
    string code;
    string message;
    string fix;
}

private struct ResolverOutput
{
    bool ok;
    ResolverError error;
    ResolverPackage[] packages;
    string[] include_dirs;
    string[] link_flags;
}

private bool runResolver(const ref Home home, string target, bool sanitize,
        scope const string[] references, ref NativeResolution resolution, ref Report report)
{
    import std.array : replace;
    import std.path : buildPath;
    import flint.serde : DecodeOptions, UnknownFields;
    import flint.serde.owned : deserialize;
    import flint_tool.support.process : capture;

    string[] argv = [
        "python3", buildPath(home.root, "tools", "native_resolver.py"), "resolve", "--target", target
    ];
    foreach (reference; references)
        argv ~= ["--require", reference];
    if (sanitize)
        argv ~= "--sanitize";
    const result = capture(argv);
    DecodeOptions lenient;
    lenient.unknownFields = UnknownFields.ignore;
    // The resolver's "version" key is a D keyword.
    const decoded = deserialize!ResolverOutput(result.output.replace(`"version":`, `"version_number":`), lenient);
    if (!decoded.ok)
    {
        report.error("FLINT-E0819", "the native resolver gave no answer", result.combined());
        return false;
    }
    if (!decoded.value.ok)
    {
        report.error(decoded.value.error.code, decoded.value.error.message, decoded.value.error.fix);
        return false;
    }
    foreach (ref item; decoded.value.packages)
    {
        NativePackage package_;
        package_.name = item.name;
        package_.version_ = item.version_number;
        package_.recipeRevision = item.recipe_revision;
        package_.packageId = item.package_id;
        package_.packageRevision = item.package_revision;
        package_.sourceSha256 = item.source_sha256;
        package_.binarySha256 = item.binary_sha256;
        package_.license = item.license;
        package_.folder = item.package_folder;
        package_.dependencies = item.dependencies.dup;
        resolution.packages ~= package_;
    }
    foreach (flag; decoded.value.link_flags)
    {
        if (flag.length && flag[0] != '-')
            archiveOwner(resolution, flag);
        resolution.linkFlags ~= flag;
    }
    resolution.includeDirs = decoded.value.include_dirs.dup;
    return true;
}

private void archiveOwner(ref NativeResolution resolution, string archive)
{
    import std.algorithm.searching : startsWith;

    foreach (ref package_; resolution.packages)
    {
        if (archive.startsWith(package_.folder ~ "/"))
            package_.archives ~= archive;
    }
}

/// `system = true`: the host's library through pkg-config, recorded and marked non-portable (FLINT-E0321 when
/// pkg-config does not know it or it is older than the version written).
private bool systemLibrary(string name, string version_, ref NativeResolution resolution, ref Report report)
{
    import std.array : split;
    import std.string : strip;
    import flint_tool.support.process : capture;

    const found = capture(["pkg-config", "--modversion", name]);
    if (!found.ok)
    {
        report.error("FLINT-E0321", "system = true: the host has no " ~ name ~ " that pkg-config can find",
                "install its development package, or drop `system = true` to build Flint's pinned " ~ name);
        return false;
    }
    const libs = capture(["pkg-config", "--libs", name]);
    const cflags = capture(["pkg-config", "--cflags-only-I", name]);
    NativePackage package_;
    package_.name = name;
    package_.version_ = found.output.strip.idup;
    package_.linkage = "system";
    package_.direct = true;
    package_.requesters = ["the project"];
    resolution.packages ~= package_;
    foreach (flag; libs.output.strip.split(" "))
    {
        if (flag.length)
            resolution.linkFlags ~= flag;
    }
    foreach (flag; cflags.output.strip.split(" "))
    {
        if (flag.length > 2)
            resolution.includeDirs ~= flag[2 .. $];
    }
    resolution.nonPortable ~= "uses the host's " ~ name ~ " " ~ package_.version_ ~ " (system = true)";
    if (version_.length && compareLoose(package_.version_, version_) < 0)
    {
        report.error("FLINT-E0321",
                "system = true: the host's " ~ name ~ " is " ~ package_.version_ ~ ", older than " ~ version_,
                "install a newer " ~ name ~ ", or drop `system = true`");
        return false;
    }
    return true;
}

private int compareLoose(string left, string right)
{
    import std.algorithm.iteration : splitter;
    import std.array : array;
    import std.conv : ConvException, to;

    auto a = left.splitter('.').array;
    auto b = right.splitter('.').array;
    foreach (i; 0 .. a.length < b.length ? a.length : b.length)
    {
        long x;
        long y;
        try
        {
            x = a[i].to!long;
            y = b[i].to!long;
        }
        catch (ConvException)
            return 0;
        if (x != y)
            return x < y ? -1 : 1;
    }
    return 0;
}

/// Turn bundled packages into shared libraries in `libraryDirectory` and rewrite the link flags to use them,
/// with the run path `$ORIGIN/../lib` (executables live in bin/ and their bundled libraries in lib/).
bool bundle(ref NativeResolution resolution, string clang, string libraryDirectory, ref Report report)
{
    import std.algorithm.searching : canFind;
    import std.file : mkdirRecurse;
    import std.path : buildPath;
    import flint_tool.support.process : capture;

    string[] removed;
    string[] added;
    foreach (ref package_; resolution.packages)
    {
        if (package_.linkage != "bundled")
            continue;
        mkdirRecurse(libraryDirectory);
        const soname = "lib" ~ package_.name ~ "-flint.so";
        const output = buildPath(libraryDirectory, soname);
        string[] argv = [
            clang, "-shared", "-fPIC", "-o", output, "-Wl,-soname," ~ soname, "-Wl,--whole-archive"
        ] ~ package_.archives ~ ["-Wl,--no-whole-archive"];
        foreach (ref dependency; resolution.packages)
        {
            if (package_.dependencies.canFind(dependency.name))
                argv ~= dependency.archives;
        }
        argv ~= ["-lpthread", "-ldl", "-lm"];
        const linked = capture(argv);
        if (!linked.ok)
        {
            report.error("FLINT-E0819",
                    "native package " ~ package_.name ~ " cannot be bundled as a shared library", linked.combined());
            return false;
        }
        removed ~= package_.archives;
        added ~= ["-L" ~ libraryDirectory, "-l" ~ package_.name ~ "-flint"];
        resolution.bundled ~= output;
    }
    if (resolution.bundled.length == 0)
        return true;
    string[] flags = added ~ "-rpath=$ORIGIN/../lib";
    foreach (flag; resolution.linkFlags)
    {
        if (!removed.canFind(flag))
            flags ~= flag;
    }
    resolution.linkFlags = flags;
    return true;
}
