/// Embedded C: compile a project's `native/` sources with the pinned clang and the hardening policy
/// (ADR-021 section 5, ADR-023).
///
/// Objects are cached by content: the key covers the compiler binary, every flag and the preprocessed
/// translation unit, so a changed header, define or compiler rebuilds exactly the objects it affects.
module flint_tool.engine.cbuild;

import flint_tool.diagnostics.report : Report, Severity, at, diagnostic;
import flint_tool.engine.session : Session;
import flint_tool.home.policy : Home;
import flint_tool.project.manifest : Manifest;

@safe:

/// policy/native-c.toml: the one C configuration every project uses.
struct NativeCPolicy
{
    /// Compiler path template (`{toolchain}` is the toolchain directory).
    string compiler;
    /// clang-tidy path template.
    string clang_tidy;
    /// Accepted `-std=` values.
    string[] standards;
    /// The standard when a project names none.
    string default_standard;
    /// Warning flags; warnings are errors.
    string[] warnings;
    /// Code-generation hardening.
    string[] hardening;
    /// Linker hardening for dynamic executables, as linker arguments.
    string[] link_hardening;
    /// Flags of `flint test --sanitize` builds instead of `hardening`.
    string[] sanitize;
    /// The fixed clang-tidy check list.
    string clang_tidy_checks;
}

/// The compiled C of one build.
struct CBuild
{
    /// Absolute object paths, in source order.
    string[] objects;
    /// Project-relative sources.
    string[] sources;
    /// Objects compiled now rather than taken from the cache.
    long compiled;
    /// The complete flag list, for receipts.
    string[] flags;
    /// SHA-256 of the compiler binary.
    string compilerSha256;
    /// SHA-256 of policy/native-c.toml.
    string policySha256;
}

/// Directory of the C object cache, relative to the project root.
enum objectCache = ".flint/cache/c";

/// Project-relative C sources: `[native.c] sources` globs, or `native/**/*.c`.
string[] nativeSources(const ref Manifest manifest)
{
    import std.algorithm.sorting : sort;
    import std.algorithm.iteration : uniq;
    import std.array : array;
    import std.path : buildPath;
    import flint_tool.support.files : findFiles;

    string[] found;
    const patterns = manifest.nativeC.sources.length ? manifest.nativeC.sources : ["native/**/*.c"];
    foreach (pattern; patterns)
    {
        foreach (relative; findFiles(manifest.root, pattern))
            found ~= relative;
    }
    sort(found);
    return found.uniq.array;
}

/// Load policy/native-c.toml with `{toolchain}` expanded.
bool loadNativeCPolicy(const ref Home home, out NativeCPolicy policy, out string digest, ref Report report)
{
    import std.array : replace;
    import std.path : buildPath;
    import flint.config : ConfigOptions, load;
    import flint_tool.support.files : readIfPresent, sha256Hex;
    import flint_tool.toolchain.toolchain : toolchainDirectory;

    const text = readIfPresent(buildPath(home.root, "policy", "native-c.toml"));
    if (text is null)
    {
        report.error("FLINT-E0809", "policy/native-c.toml is missing from the Flint installation at " ~ home.root,
                "git checkout -- policy/native-c.toml");
        return false;
    }
    digest = sha256Hex(cast(const(ubyte)[]) text);
    ConfigOptions options;
    options.directory = buildPath(home.root, "policy");
    options.baseName = "native-c";
    options.readEnvironment = false;
    options.profile = "canonical";
    static struct File
    {
        NativeCPolicy c;
    }

    auto loaded = load!File(options);
    if (!loaded.ok)
    {
        report.error("FLINT-E0809", "policy/native-c.toml: " ~ loaded.error.message,
                "git checkout -- policy/native-c.toml");
        return false;
    }
    policy = loaded.value.c;
    const directory = toolchainDirectory(home);
    policy.compiler = policy.compiler.replace("{toolchain}", directory);
    policy.clang_tidy = policy.clang_tidy.replace("{toolchain}", directory);
    return true;
}

/// Verify that an executable the C build needs is installed.
bool cToolPresent(string path, string what, ref Report report)
{
    import std.file : exists;

    if (exists(path))
        return true;
    report.error("FLINT-E0816", what ~ " is not installed (" ~ path ~ ")", "flint toolchain install");
    return false;
}

/// The compile flags of one project, without `-c`, input or output.
string[] compileFlags(const ref NativeCPolicy policy, const ref Manifest manifest, bool sanitize, ref Report report)
{
    import std.algorithm.searching : canFind;
    import std.array : join;
    import std.path : buildPath;

    const standard = manifest.nativeC.standard.length ? manifest.nativeC.standard : policy.default_standard;
    if (!policy.standards.canFind(standard))
    {
        report.error("FLINT-E0105", "[native.c] standard `" ~ standard ~ "` is not supported",
                "standard = one of: " ~ policy.standards.join(", "));
        return null;
    }
    string[] flags = ["-std=" ~ standard] ~ policy.warnings.dup ~ (sanitize ? policy.sanitize : policy.hardening).dup;
    foreach (directory; manifest.nativeC.includeDirs)
        flags ~= "-I" ~ buildPath(manifest.root, directory);
    foreach (definition; manifest.nativeC.defines)
        flags ~= "-D" ~ definition;
    return flags;
}

/// Compile every embedded C source of a project, reusing cached objects. True when nothing failed.
bool compileNativeC(ref Session session, const ref Manifest manifest, bool sanitize,
        scope const(string)[] targetFlags, out CBuild unit, ref Report report)
{
    import std.file : exists, mkdirRecurse, rename;
    import std.path : buildPath;
    import flint_tool.support.files : sha256File;

    unit.sources = nativeSources(manifest);
    if (unit.sources.length == 0)
        return true;
    NativeCPolicy policy;
    if (!loadNativeCPolicy(session.home, policy, unit.policySha256, report)
            || !cToolPresent(policy.compiler, "the pinned C compiler", report))
        return false;
    unit.flags = targetFlags.dup ~ compileFlags(policy, manifest, sanitize, report);
    if (!report.ok)
        return false;
    unit.compilerSha256 = sha256File(policy.compiler);
    const cache = buildPath(manifest.root, objectCache);
    mkdirRecurse(cache);
    foreach (relative; unit.sources)
    {
        const source = buildPath(manifest.root, relative);
        string key;
        if (!objectKey(policy.compiler, unit, source, key, report))
            return false;
        const object = buildPath(cache, key ~ ".o");
        if (!exists(object))
        {
            const partial = object ~ ".partial";
            if (!runCompiler(policy.compiler, unit.flags ~ ["-c", source, "-o", partial], relative, report))
                return false;
            rename(partial, object);
            unit.compiled++;
        }
        unit.objects ~= object;
    }
    session.progress("C", (unit.compiled
            ? "compiled " : "reused ") ~ countText(unit.sources.length) ~ (sanitize ? " with ASan and UBSan" : ""));
    return true;
}

private string countText(size_t count)
{
    import std.conv : to;

    return count.to!string ~ (count == 1 ? " C source" : " C sources");
}

/// The cache key of one object: compiler identity, flags and the preprocessed translation unit.
private bool objectKey(string compiler, const ref CBuild build, string source, out string key, ref Report report)
{
    import std.array : join;
    import flint_tool.support.files : sha256Hex;
    import flint_tool.support.process : capture;

    const preprocessed = capture([compiler] ~ build.flags ~ ["-E", source]);
    if (!preprocessed.ok)
    {
        report.error("FLINT-E0708", source ~ " does not preprocess", "the compiler said:\n" ~ preprocessed.combined());
        return false;
    }
    const material = "flint-c-object/1\n" ~ build.compilerSha256 ~ "\n" ~ build.flags.join(
            "\x1f") ~ "\n" ~ preprocessed.output;
    key = sha256Hex(cast(const(ubyte)[]) material);
    return true;
}

private bool runCompiler(string compiler, scope const(string)[] arguments, string relative, ref Report report)
{
    import flint_tool.support.process : capture;

    const result = capture([compiler] ~ arguments);
    if (result.ok)
        return true;
    report.error("FLINT-E0708", relative ~ " failed to compile",
            "C warnings are errors; the compiler said:\n" ~ result.combined());
    return false;
}

/// One clang-tidy finding.
struct TidyFinding
{
    /// Project-relative file.
    string file;
    /// One-based line.
    size_t line;
    /// One-based column.
    size_t column;
    /// The message with its check name.
    string message;
}

/// Parse `path:line:column: warning|error: message [check]`; false for any other line.
bool parseTidyLine(string text, string root, out TidyFinding finding)
{
    import std.algorithm.searching : startsWith;
    import std.conv : ConvException, to;
    import std.string : indexOf, split;

    foreach (kind; [": warning: ", ": error: "])
    {
        const found = text.indexOf(kind);
        if (found < 0)
            continue;
        const location = text[0 .. found].split(":");
        if (location.length < 3)
            return false;
        try
        {
            finding.line = location[$ - 2].to!size_t;
            finding.column = location[$ - 1].to!size_t;
        }
        catch (ConvException)
            return false;
        string file = text[0 .. found - location[$ - 1].length - location[$ - 2].length - 2];
        if (file.startsWith(root ~ "/"))
            file = file[root.length + 1 .. $];
        finding.file = file;
        finding.message = text[found + kind.length .. $];
        return true;
    }
    return false;
}

/// Run clang-tidy's fixed profile over the project's C sources. Each finding is a FLINT-E0603 error.
long tidyNativeC(const ref Home home, const ref Manifest manifest, ref Report report)
{
    import std.path : buildPath;
    import std.string : lineSplitter, strip;
    import flint_tool.support.process : capture;

    const sources = nativeSources(manifest);
    if (sources.length == 0)
        return 0;
    NativeCPolicy policy;
    string digest;
    if (!loadNativeCPolicy(home, policy, digest, report) || !cToolPresent(policy.clang_tidy, "clang-tidy", report))
        return 0;
    const flags = compileFlags(policy, manifest, false, report);
    if (!report.ok)
        return 0;
    long findings;
    foreach (relative; sources)
    {
        const result = capture([
            policy.clang_tidy, "--quiet", "--checks=" ~ policy.clang_tidy_checks,
            "--warnings-as-errors=*", buildPath(manifest.root, relative), "--"
        ] ~ flags);
        foreach (line; result.output.lineSplitter)
        {
            TidyFinding finding;
            if (!parseTidyLine(line.strip.idup, manifest.root, finding))
                continue;
            findings++;
            report.add(at(diagnostic("FLINT-E0603", Severity.error, finding.message,
                    "fix the finding; the profile is fixed by policy/native-c.toml"),
                    finding.file, finding.line, finding.column));
        }
        if (!result.ok && findings == 0)
            report.error("FLINT-E0603", relative ~ ": clang-tidy failed", result.combined());
    }
    return findings;
}
