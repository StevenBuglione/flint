/// The pinned toolchain: where it lives, what it reports, and whether it matches policy and its receipt.
module flint_tool.toolchain.toolchain;

import flint_tool.diagnostics.report : Report, Severity, diagnostic;
import flint_tool.home.policy : Home;

@safe:

/// The receipt `flint toolchain install` writes into the toolchain directory.
enum receiptName = "flint-toolchain.json";

/// One installed tool.
struct Component
{
    /// Tool name: dmd, dub, ldc2, dfmt or dscanner.
    string name;
    /// Absolute executable path.
    string path;
    /// Version pinned by policy/toolchains.json.
    string expected;
    /// First line the tool prints for --version.
    string reported;
    /// SHA-256 of the executable, when hashed.
    string sha256;
    /// The executable exists.
    bool present;
    /// The reported version contains the pinned one.
    bool versionMatches;
}

/// The fork's provenance.
struct ForkState
{
    /// dmd.upstream and dub.upstream sit beside the forked executables.
    bool installed;
    /// The toolchain receipt exists and parses.
    bool receiptPresent;
    /// Receipt path.
    string receiptPath;
    /// SHA-256 of toolchain/dmd-2.114.0-flint.patch in this checkout.
    string dmdPatch;
    /// SHA-256 of toolchain/dub-1.43.0-flint.patch in this checkout.
    string dubPatch;
    /// Patch hashes recorded at installation.
    string recordedDmdPatch;
    /// Patch hashes recorded at installation.
    string recordedDubPatch;
    /// Receipt present, patches equal, binaries equal.
    bool verified;
}

/// The toolchain as found on disk.
struct Toolchain
{
    /// Toolchain directory.
    string directory;
    /// Forked DMD.
    Component dmd;
    /// Forked DUB.
    Component dub;
    /// Pinned LDC.
    Component ldc2;
    /// Pinned dfmt.
    Component dfmt;
    /// Pinned D-Scanner.
    Component dscanner;
    /// Fork provenance.
    ForkState fork;

    /// The component named `name`.
    Component component(string name) const
    {
        switch (name)
        {
        case "dmd":
            return dmd;
        case "dub":
            return dub;
        case "ldc2":
            return ldc2;
        case "dfmt":
            return dfmt;
        default:
            return dscanner;
        }
    }
}

/// Receipt schema `flint.toolchain/1`.
struct ToolchainReceipt
{
    /// Schema identifier.
    string schema = "flint.toolchain/1";
    /// SHA-256 of tools/install_toolchains.py that installed it.
    string installer_sha256;
    /// DMD and the fork.
    ReceiptDmd dmd;
    /// LDC.
    ReceiptTool ldc;
}

/// The DMD part of the receipt.
struct ReceiptDmd
{
    /// Pinned version.
    string version_number;
    /// SHA-256 of the upstream archive.
    string archive_sha256;
    /// SHA-256 of the installed dmd.
    string binary_sha256;
    /// SHA-256 of the installed dub.
    string dub_sha256;
    /// SHA-256 of the DMD fork patch.
    string dmd_patch_sha256;
    /// SHA-256 of the DUB fork patch.
    string dub_patch_sha256;
    /// SHA-256 of the compile server prelude list.
    string prelude_sha256;
    /// DMD was built with profile-guided optimisation.
    bool pgo;
}

/// One plain pinned tool in the receipt.
struct ReceiptTool
{
    /// Pinned version.
    string version_number;
    /// SHA-256 of the upstream archive.
    string archive_sha256;
    /// SHA-256 of the installed executable.
    string binary_sha256;
}

/// The toolchain directory: FLINT_TOOLCHAIN_DIR, else `<home>/.tools`.
string toolchainDirectory(const ref Home home, string overrideDirectory = null)
{
    import std.path : absolutePath, buildNormalizedPath, buildPath;
    import std.process : environment;

    if (overrideDirectory.length)
        return buildNormalizedPath(absolutePath(overrideDirectory));
    const fromEnvironment = environment.get("FLINT_TOOLCHAIN_DIR", "");
    if (fromEnvironment.length)
        return buildNormalizedPath(absolutePath(fromEnvironment));
    return buildPath(home.root, ".tools");
}

/// Executable path of a component inside `directory`.
string componentPath(const ref Home home, string directory, string name)
{
    import std.path : buildPath;

    switch (name)
    {
    case "dmd":
    case "dub":
        return buildPath(directory, "dmd2", "linux", "bin64", name);
    case "ldc2":
        return buildPath(directory, "ldc2-" ~ home.versions["ldc"] ~ "-linux-x86_64", "bin", "ldc2");
    default:
        return buildPath(directory, "bin", name);
    }
}

private string pinnedVersion(const ref Home home, string name)
{
    return name == "ldc2" ? home.versions["ldc"] : home.versions[name];
}

/// Inspect the named components (all when empty). With `hash`, also hash the executables.
Toolchain inspect(const ref Home home, scope const(string)[] names, bool hash, string overrideDirectory = null)
{
    import std.file : exists;
    import std.path : buildPath;
    import flint_tool.support.files : sha256File;

    Toolchain toolchain;
    toolchain.directory = toolchainDirectory(home, overrideDirectory);
    const all = names.length == 0;
    foreach (name; ["dmd", "dub", "ldc2", "dfmt", "dscanner"])
    {
        bool wanted = all;
        foreach (requested; names)
            wanted = wanted || requested == name;
        Component component;
        component.name = name;
        component.path = componentPath(home, toolchain.directory, name);
        component.expected = pinnedVersion(home, name);
        component.present = exists(component.path);
        if (wanted && component.present)
        {
            component.reported = versionLine(component.path);
            component.versionMatches = reportsVersion(component.reported, component.expected);
            if (hash)
                component.sha256 = sha256File(component.path);
        }
        assign(toolchain, component);
    }
    const bin = buildPath(toolchain.directory, "dmd2", "linux", "bin64");
    toolchain.fork.installed = exists(buildPath(bin, "dmd.upstream")) && exists(buildPath(bin, "dub.upstream"));
    toolchain.fork.dmdPatch = sha256File(buildPath(home.root, "toolchain", "dmd-2.114.0-flint.patch"));
    toolchain.fork.dubPatch = sha256File(buildPath(home.root, "toolchain", "dub-1.43.0-flint.patch"));
    toolchain.fork.receiptPath = buildPath(toolchain.directory, receiptName);
    ToolchainReceipt receipt;
    if (readReceipt(toolchain.fork.receiptPath, receipt))
    {
        toolchain.fork.receiptPresent = true;
        toolchain.fork.recordedDmdPatch = receipt.dmd.dmd_patch_sha256;
        toolchain.fork.recordedDubPatch = receipt.dmd.dub_patch_sha256;
        bool binaries = true;
        foreach (pair; [
                [toolchain.dmd.sha256, receipt.dmd.binary_sha256],
                [toolchain.dub.sha256, receipt.dmd.dub_sha256],
                [toolchain.ldc2.sha256, receipt.ldc.binary_sha256]
            ])
            binaries = binaries && (pair[0].length == 0 || pair[0] == pair[1]);
        toolchain.fork.verified = toolchain.fork.installed && binaries
            && receipt.dmd.dmd_patch_sha256 == toolchain.fork.dmdPatch
            && receipt.dmd.dub_patch_sha256 == toolchain.fork.dubPatch;
    }
    return toolchain;
}

private void assign(ref Toolchain toolchain, Component component)
{
    switch (component.name)
    {
    case "dmd":
        toolchain.dmd = component;
        break;
    case "dub":
        toolchain.dub = component;
        break;
    case "ldc2":
        toolchain.ldc2 = component;
        break;
    case "dfmt":
        toolchain.dfmt = component;
        break;
    default:
        toolchain.dscanner = component;
    }
}

/// Read and parse the toolchain receipt.
bool readReceipt(string path, out ToolchainReceipt receipt)
{
    import flint.serde.owned : deserialize;
    import flint_tool.support.files : readIfPresent;

    const text = readIfPresent(path);
    if (text is null)
        return false;
    const decoded = deserialize!ToolchainReceipt(text);
    if (!decoded.ok || decoded.value.schema != "flint.toolchain/1")
        return false;
    receipt = copyReceipt(decoded.value);
    return true;
}

private ToolchainReceipt copyReceipt(const ToolchainReceipt receipt)
{
    ToolchainReceipt copy;
    copy.schema = receipt.schema;
    copy.installer_sha256 = receipt.installer_sha256;
    copy.dmd = receipt.dmd;
    copy.ldc = receipt.ldc;
    return copy;
}

/// First line of `<executable> --version`.
string versionLine(string executable)
{
    import std.string : lineSplitter, strip;
    import flint_tool.support.process : capture;

    const outcome = capture([executable, "--version"]);
    foreach (line; outcome.combined().lineSplitter)
    {
        if (line.strip.length)
            return line.strip.idup;
    }
    return null;
}

/// Whether a --version line names `expected` as a whole version.
bool reportsVersion(string line, string expected)
{
    import std.algorithm.searching : find;

    auto rest = line;
    while (true)
    {
        rest = rest.find(expected);
        if (rest.length == 0)
            return false;
        const start = line.length - rest.length;
        const before = start == 0 ? ' ' : line[start - 1];
        const after = rest.length == expected.length ? ' ' : rest[expected.length];
        if (!(before >= '0' && before <= '9') && before != '.' && !(after >= '0' && after <= '9') && after != '.')
            return true;
        rest = rest[1 .. $];
    }
}

/// Report toolchain problems for the named components. Severity is error with --verify, else warning.
void verifyToolchain(const ref Toolchain toolchain, scope const(string)[] names, Severity severity, ref Report report)
{
    foreach (name; names)
    {
        const component = toolchain.component(name);
        if (!component.present)
        {
            report.add(diagnostic("FLINT-E0802", severity,
                    name ~ " is not installed at " ~ component.path, name == "dfmt"
                    || name == "dscanner" ? "python3 tools/install_quality_tools.py" : "flint toolchain install"));
            continue;
        }
        if (!component.versionMatches)
            report.add(diagnostic("FLINT-E0803", severity,
                    name ~ " reports `" ~ component.reported ~ "`; policy pins " ~ component.expected,
                    "flint toolchain install"));
    }
    bool forkNeeded;
    foreach (name; names)
        forkNeeded = forkNeeded || name == "dmd" || name == "dub";
    if (!forkNeeded)
        return;
    if (!toolchain.fork.installed)
        report.add(diagnostic("FLINT-E0802", severity,
                "the Flint DMD/DUB fork is not installed in " ~ toolchain.directory, "flint toolchain install"));
    else if (!toolchain.fork.receiptPresent)
        report.add(diagnostic("FLINT-E0804", severity, "no toolchain receipt at " ~ toolchain.fork.receiptPath
                ~ ", so the installed fork cannot be traced to toolchain/*.patch", "flint toolchain install"));
    else if (toolchain.fork.recordedDmdPatch != toolchain.fork.dmdPatch
            || toolchain.fork.recordedDubPatch != toolchain.fork.dubPatch)
        report.add(diagnostic("FLINT-E0805", severity,
                "the installed fork was built from different patches than " ~ "toolchain/ holds",
                "flint toolchain install"));
    else if (!toolchain.fork.verified)
        report.add(diagnostic("FLINT-E0806", severity,
                "an installed toolchain binary differs from the hash its receipt " ~ "records",
                "flint toolchain install"));
}

/// Whether every named component is present with the pinned version, and the fork is verified when needed.
bool canonicalToolchain(const ref Toolchain toolchain, scope const(string)[] names)
{
    Report probe;
    verifyToolchain(toolchain, names, Severity.error, probe);
    return probe.ok;
}

/// The commands `flint toolchain install` runs.
string[][] installCommands(const ref Home home, string directory, bool pgo, string linker,
        bool sanitizers = false, bool musl = false)
{
    import std.path : buildPath;

    const installer = buildPath(home.root, "tools", "install_toolchains.py");
    string[] dmd = ["python3", installer, "--compiler", "dmd", "--flint-fork"];
    if (!pgo)
        dmd ~= "--no-pgo";
    if (linker.length)
        dmd ~= ["--dmd-linker", linker];
    dmd ~= ["--destination", directory];
    string[][] commands = [
        dmd, ["python3", installer, "--compiler", "ldc", "--destination", directory],
        // The pinned clang compiles embedded C and runs clang-tidy; Conan is the hidden native-package engine.
        ["python3", installer, "--compiler", "clang", "--destination", directory],
        ["python3", installer, "--compiler", "conan", "--destination", directory]
    ];
    if (sanitizers)
        commands ~= [
        "python3", installer, "--compiler", "ldc-sanitizer-runtime", "--destination", directory
    ];
    // linux-x86_64-musl packages: the Alpine LDC runtime and the pinned musl sysroot (ADR-023).
    if (musl)
        commands ~= [
        ["python3", installer, "--compiler", "ldc", "--musl", "--destination", directory],
        ["python3", installer, "--compiler", "musl-sysroot", "--destination", directory]
    ];
    if (directory == buildPath(home.root, ".tools"))
        commands ~= ["python3", buildPath(home.root, "tools", "install_quality_tools.py")];
    return commands;
}

/// Installer output: the JSON receipt line each install_toolchains.py run prints last.
struct InstallerDmd
{
    /// Archive checksum.
    string sha256;
    /// Fork summary.
    InstallerFork flint_fork;
}

/// The fork summary install_toolchains.py prints.
struct InstallerFork
{
    /// DMD patch hash.
    string dmd_patch_sha256;
    /// DUB patch hash.
    string dub_patch_sha256;
    /// Prelude hash.
    string prelude_sha256;
    /// PGO enabled.
    bool pgo;
    /// Installed dmd hash.
    string dmd_sha256;
    /// Installed dub hash.
    string dub_sha256;
}

/// Plain installer output.
struct InstallerTool
{
    /// Archive checksum.
    string sha256;
}

/// The last line of `text` that looks like a JSON object.
string lastJsonLine(string text)
{
    import std.string : lineSplitter, strip;

    string found;
    foreach (line; text.lineSplitter)
    {
        const trimmed = line.strip;
        if (trimmed.length > 1 && trimmed[0] == '{' && trimmed[$ - 1] == '}')
            found = trimmed.idup;
    }
    return found;
}

/// Build the toolchain receipt from the two installer outputs and the installed binaries.
bool composeReceipt(const ref Home home, string directory, string dmdOutput, string ldcOutput,
        out ToolchainReceipt receipt, ref Report report)
{
    import flint.serde : DecodeOptions, UnknownFields;
    import flint.serde.owned : deserialize;
    import std.path : buildPath;
    import flint_tool.support.files : sha256File;

    DecodeOptions lenient;
    lenient.unknownFields = UnknownFields.ignore;
    auto dmd = deserialize!InstallerDmd(lastJsonLine(dmdOutput), lenient);
    auto ldc = deserialize!InstallerTool(lastJsonLine(ldcOutput), lenient);
    if (!dmd.ok || !ldc.ok || dmd.value.flint_fork.dmd_patch_sha256.length == 0)
    {
        report.error("FLINT-E0814", "the installer did not print its receipt", "flint toolchain install --plan");
        return false;
    }
    receipt.installer_sha256 = sha256File(buildPath(home.root, "tools", "install_toolchains.py"));
    receipt.dmd = ReceiptDmd(home.versions["dmd"], dmd.value.sha256,
            dmd.value.flint_fork.dmd_sha256, dmd.value.flint_fork.dub_sha256,
            dmd.value.flint_fork.dmd_patch_sha256, dmd.value.flint_fork.dub_patch_sha256,
            dmd.value.flint_fork.prelude_sha256, dmd.value.flint_fork.pgo);
    receipt.ldc = ReceiptTool(home.versions["ldc"], ldc.value.sha256, sha256File(componentPath(home,
            directory, "ldc2")));
    return true;
}
