/// Build receipts (ADR-018): the identities, profile, flags and output hashes behind every artifact.
module flint_tool.engine.receipt;

import flint_tool.diagnostics.report : Report, Severity, diagnostic;

@safe:

/// Receipt schema identifier.
enum receiptSchema = "flint.receipt/1";

/// The flint executable that produced the artifact.
struct ToolRecord
{
    /// Always "flint".
    string name = "flint";
    /// Flint release.
    string release;
    /// Platform version.
    string platform;
    /// SHA-256 of the flint executable.
    string sha256;
}

/// What was built.
struct ProjectRecord
{
    /// Project or workspace package name.
    string name;
    /// Project version.
    string version_number;
    /// "project" or "workspace".
    string kind;
    /// SHA-256 of flint.toml, for projects.
    string manifest_sha256;
    /// SHA-256 of flint.lock, for projects.
    string lock_sha256;
}

/// Where the sources came from.
struct SourceRecord
{
    /// git is available and the root is in a repository.
    bool available;
    /// HEAD commit.
    string commit;
    /// Uncommitted changes exist.
    bool dirty;
}

/// One toolchain component.
struct ComponentRecord
{
    /// Tool name.
    string name;
    /// Pinned version.
    string version_number;
    /// First line of --version.
    string reported;
    /// SHA-256 of the executable.
    string sha256;
}

/// The toolchain identity.
struct ToolchainRecord
{
    /// Components the build used.
    ComponentRecord[] components;
    /// The fork's receipt verified.
    bool verified;
    /// DMD fork patch hash in the checkout.
    string dmd_patch_sha256;
    /// DUB fork patch hash in the checkout.
    string dub_patch_sha256;
}

/// The native provider install the build could link.
struct NativeRecord
{
    /// Target triple name.
    string target;
    /// The install receipt exists.
    bool present;
    /// SHA-256 of the install receipt.
    string receipt_sha256;
}

/// The resolved profile and the exact flags.
struct ProfileRecord
{
    /// Profile name.
    string name;
    /// SHA-256 of policy/profiles.toml.
    string policy_sha256;
    /// Compiler executable name.
    string compiler;
    /// DUB build type.
    string build_type;
    /// Canonical flags from policy.
    string[] dflags;
    /// Flags actually passed.
    string[] effective_dflags;
    /// Linker flags actually passed.
    string[] effective_lflags;
}

/// Flags added on top of the profile.
struct AdditionsRecord
{
    /// From [profile.<name>] in flint.toml.
    string[] manifest_dflags;
    /// From [profile.<name>] in flint.toml.
    string[] manifest_lflags;
    /// From --dflags and the `--` pass-through.
    string[] command_dflags;
    /// From --lflags.
    string[] command_lflags;
}

/// One environment variable that changes builds.
struct EnvironmentRecord
{
    /// Variable name.
    string name;
    /// Value.
    string value;
}

/// One output file.
struct OutputRecord
{
    /// Path relative to the project or workspace root.
    string path;
    /// SHA-256.
    string sha256;
    /// Size in bytes.
    long bytes;
}

/// Embedded C compiled into the artifact (ADR-023).
struct EmbeddedCRecord
{
    /// Project-relative sources with their SHA-256.
    OutputRecord[] sources;
    /// Complete compile flags.
    string[] flags;
    /// SHA-256 of the pinned compiler.
    string compiler_sha256;
    /// SHA-256 of policy/native-c.toml.
    string policy_sha256;
}

/// One native package linked into the artifact (ADR-023).
struct NativePackageRecord
{
    /// Recipe name.
    string name;
    /// Version.
    string version_number;
    /// static, bundled or system.
    string linkage;
    /// Recipe revision in Flint's index.
    string recipe_revision;
    /// Binary package ID.
    string package_id;
    /// Pinned source archive hash.
    string source_sha256;
    /// Binary package content hash.
    string binary_sha256;
}

/// One platform module linked from the platform cache (ADR-030 section 5).
struct PlatformArchiveRecord
{
    /// DUB name, such as flint:web.
    string name;
    /// Cache key: toolchain, flags, target, settings, sources and dependencies' keys.
    string key;
    /// SHA-256 of the archive.
    string sha256;
}

/// Where a build's wall time went, in milliseconds (ADR-030 section 5's build budget). `compile` is the critical
/// path of the parallel compile jobs, not their sum. `compile` and `link` are -1 when DUB did not report them, and
/// `plan` then holds the whole DUB process. `flint` is what is left: flint's own work.
struct PhasesRecord
{
    /// From flint's session start to the receipt.
    long total;
    /// flint's own work: total minus the other phases.
    long flint;
    /// The Flint AOT step.
    long aot;
    /// The DUB process apart from compile and link: start, recipe load, plan, archiving, exit.
    long plan;
    /// From the first compile job's start to the last one's end.
    long compile = -1;
    /// The final link.
    long link = -1;
}

/// A complete build receipt.
struct Receipt
{
    /// Schema identifier.
    string schema = receiptSchema;
    /// The producing tool.
    ToolRecord tool;
    /// The built project.
    ProjectRecord project;
    /// Source identity.
    SourceRecord source;
    /// Toolchain identity.
    ToolchainRecord toolchain;
    /// Native provider identity.
    NativeRecord native;
    /// Profile and flags.
    ProfileRecord profile;
    /// The artifact may be used for measurement and gates.
    bool canonical;
    /// Why it is not canonical.
    string[] non_canonical_reasons;
    /// Added flags.
    AdditionsRecord additions;
    /// Active waivers.
    string[] waivers;
    /// DUB packages used under `[unchecked]` waivers, with their reasons.
    string[] unchecked;
    /// The build command.
    string[] command;
    /// Environment that affects the build.
    EnvironmentRecord[] environment;
    /// Output files.
    OutputRecord[] outputs;
    /// Embedded C, when the project has any.
    EmbeddedCRecord embedded_c;
    /// Build target, such as linux-x86_64-musl.
    string target;
    /// Native packages.
    NativePackageRecord[] native_packages;
    /// The artifact builds the same on every machine: no `system = true` packages.
    bool portable = true;
    /// Why it does not.
    string[] non_portable_reasons;
    /// Platform modules linked from the platform cache; empty when they were compiled from source.
    PlatformArchiveRecord[] platform_archives;
    /// Where the build's time went.
    PhasesRecord phases_ms;
}

/// Receipt path for an artifact.
string receiptPath(string artifact)
{
    return artifact ~ ".receipt.json";
}

/// Write a receipt as stable, readable JSON.
void writeReceipt(string path, const ref Receipt receipt)
{
    import flint.serde.owned : serialize;
    import flint_tool.support.files : writeIfChanged;

    auto text = serialize(receipt);
    assert(text.ok, "receipt serialization failed: " ~ text.error.message);
    writeIfChanged(path, text.value ~ "\n");
}

/// Read a receipt; FLINT-E0901 or FLINT-E0905 on failure.
bool readReceipt(string path, out Receipt receipt, ref Report report)
{
    import flint.serde.owned : deserialize;
    import flint_tool.support.files : readIfPresent;

    const text = readIfPresent(path);
    if (text is null)
    {
        report.error("FLINT-E0901", "no receipt at " ~ path, "rebuild the artifact with flint build");
        return false;
    }
    auto decoded = deserialize!Receipt(text);
    if (!decoded.ok || decoded.value.schema != receiptSchema)
    {
        report.error("FLINT-E0905", path ~ ": " ~ (decoded.ok ? "unknown schema " ~ decoded.value.schema
                : decoded.error.message), "rebuild the artifact with flint build");
        return false;
    }
    receipt = decoded.value;
    return true;
}

/// Hash one output file, in full: outputs are the project's own files, which never enter the digest log.
OutputRecord outputRecord(string path, string display)
{
    import std.file : getSize;
    import flint_tool.support.files : sha256File;

    return OutputRecord(display, sha256File(path), cast(long) getSize(path));
}

/// Check an artifact against its receipt, and the receipt's toolchain against `current` (when given).
/// With `requireCanonical`, a non-canonical receipt is refused.
bool verifyArtifact(string artifact, const ref Receipt receipt, scope const ComponentRecord[] current,
        bool requireCanonical, ref Report report)
{
    import flint_tool.support.files : sha256File;
    import std.path : baseName;

    const before = report.errors();
    const actual = sha256File(artifact);
    bool matched;
    foreach (ref output; receipt.outputs)
    {
        if (baseName(output.path) == baseName(artifact))
        {
            matched = true;
            if (output.sha256 != actual)
                report.error("FLINT-E0902",
                        artifact ~ " has SHA-256 " ~ actual ~ " but its receipt records " ~ output.sha256,
                        "rebuild it with flint build");
        }
    }
    if (!matched)
        report.error("FLINT-E0905", "the receipt lists no output named " ~ baseName(artifact),
                "rebuild it with flint build");
    foreach (ref now; current)
    {
        foreach (ref then; receipt.toolchain.components)
        {
            if (then.name == now.name && then.sha256.length && now.sha256.length && then.sha256 != now.sha256)
                report.error("FLINT-E0903",
                        now.name ~ " is now " ~ now.sha256 ~ "; the artifact was built with " ~ then.sha256,
                        "rebuild it with the current toolchain");
        }
    }
    if (requireCanonical && !receipt.canonical)
    {
        import std.array : join;

        report.error("FLINT-E0904",
                "the receipt marks the artifact non-canonical: " ~ receipt.non_canonical_reasons.join("; "),
                "rebuild without extra flags or profile overrides, with a verified toolchain");
    }
    return report.errors() == before;
}

/// The current source identity of `root`.
SourceRecord sourceIdentity(string root)
{
    import std.string : strip;
    import flint_tool.support.process : Launch, capture;

    SourceRecord record;
    Launch launch;
    launch.directory = root;
    const head = capture(["git", "rev-parse", "HEAD"], launch);
    if (!head.ok)
        return record;
    record.available = true;
    record.commit = head.output.strip.idup;
    const status = capture(["git", "status", "--porcelain", "--untracked-files=normal", "--", "."], launch);
    record.dirty = !status.ok || status.output.strip.length != 0;
    return record;
}

/// The native install for the host target.
NativeRecord nativeIdentity(string home)
{
    import std.path : buildPath;
    import flint_tool.engine.target : glibcTarget, hostTarget;
    import flint_tool.support.files : sha256File;

    NativeRecord record;
    // Linux glibc and musl hosts both build the glibc provider install of their architecture; macOS builds its own.
    version (OSX)
        record.target = hostTarget();
    else version (Windows)
        record.target = hostTarget();
    else version (AArch64)
        record.target = "linux-aarch64-glibc";
    else
        record.target = glibcTarget;
    const receipt = buildPath(home, ".native", "install", record.target, "flint-native-install.json");
    record.receipt_sha256 = sha256File(receipt);
    record.present = record.receipt_sha256.length != 0;
    return record;
}
