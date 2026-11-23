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
    import flint_tool.toolchain.host : dmdBin, dmdExecutable, dubBin, executable, ldcBin;

    switch (name)
    {
    case "dmd":
        return buildPath(directory, dmdBin(home.versions["ldc"]), dmdExecutable);
    case "dub":
        return buildPath(directory, dubBin(home.versions["dub"]), executable(name));
    case "ldc2":
        return buildPath(directory, ldcBin(home.versions["ldc"]), executable("ldc2"));
    default:
        return buildPath(directory, "bin", executable(name));
    }
}

private string pinnedVersion(const ref Home home, string name)
{
    import flint_tool.toolchain.host : dmdRoleVersion;

    if (name == "dmd")
        return dmdRoleVersion(home.versions["dmd"], home.versions["ldc"]);
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
    import flint_tool.toolchain.host : dmdArm64Host, dmdForkHost, upstreamDmdHost;

    const bin = buildPath(toolchain.directory, "dmd2", "linux", "bin64");
    // Without the DMD fork (ADR-024) the Flint-patched DUB is the whole fork. With the upstream DMD and DUB
    // (ADR-026) there is no fork: the receipt then only ties the installed binaries to the pinned archives.
    // On Windows the fork is the Flint DUB with its Windows overlay, beside the upstream DMD (ADR-026).
    static if (upstreamDmdHost || dmdArm64Host)
        toolchain.fork.installed = toolchain.dmd.present && toolchain.dub.present;
    else
        toolchain.fork.installed = dmdForkHost ? exists(buildPath(bin, "dmd.upstream"))
            && exists(buildPath(bin, "dub.upstream")) : toolchain.dub.present;
    const dmdPatch = buildPath(home.root, "toolchain", "dmd-2.114.0-flint.patch");
    static if (dmdArm64Host)
        toolchain.fork.dmdPatch = arm64DmdPatchDigest(home);
    else
        toolchain.fork.dmdPatch = dmdForkHost ? sha256File(dmdPatch) : "";
    version (OSX)
        toolchain.fork.dubPatch = dubPatchDigest(home, "dub-1.43.0-flint-darwin.patch");
    else
        toolchain.fork.dubPatch = upstreamDmdHost ? dubPatchDigest(home,
                "dub-1.43.0-flint-windows.patch") : sha256File(buildPath(home.root, "toolchain",
                "dub-1.43.0-flint.patch"));
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

/// Whether the DMD configuration next to `dmd` would split its own paths: the toolchain lies under a path with
/// whitespace and a DFLAGS argument uses %@P% unquoted (FLINT-E0821).
bool dmdConfSplits(string dmd)
{
    import std.algorithm.searching : any, canFind, startsWith;
    import std.array : split;
    import std.ascii : isWhite;
    import std.path : buildPath, dirName;
    import std.string : lineSplitter;
    import flint_tool.support.files : readIfPresent;

    if (!dmd.any!isWhite)
        return false;
    foreach (line; readIfPresent(buildPath(dirName(dmd), "dmd.conf")).lineSplitter)
    {
        if (!line.startsWith("DFLAGS="))
            continue;
        foreach (token; line["DFLAGS=".length .. $].split)
        {
            if (token.canFind("%@P%") && !token.startsWith("\""))
                return true;
        }
    }
    return false;
}

version (Windows)
{
    /// The libraries Phobos' std.net.curl tries, at run time, when DUB downloads from code.dlang.org.
    immutable string[] dubCurlLibraries = ["libcurl.dll", "curl.dll"];

    /// How to make libcurl loadable for DUB.
    enum dubCurlFix = "DMD's Windows release ships libcurl.dll beside dub.exe: reinstall it with `flint toolchain "
        ~ "install`, or put a libcurl.dll on PATH";
}
else version (OSX)
{
    /// The libraries Phobos' std.net.curl tries, at run time, when DUB downloads from code.dlang.org.
    immutable string[] dubCurlLibraries = ["libcurl.4.dylib"];

    /// How to make libcurl loadable for DUB.
    enum dubCurlFix = "macOS ships /usr/lib/libcurl.4.dylib; restore it, or point DYLD_LIBRARY_PATH at a "
        ~ "directory holding libcurl.4.dylib";
}
else
{
    /// The libraries Phobos' std.net.curl tries, at run time, when DUB downloads from code.dlang.org.
    immutable string[] dubCurlLibraries = [
        "libcurl.so", "libcurl.so.4", "libcurl-gnutls.so.4", "libcurl-nss.so.4", "libcurl.so.3"
    ];

    /// How to make libcurl loadable for DUB.
    private enum curlPackage = "install libcurl (Debian/Ubuntu: sudo apt-get install libcurl4), or point ";
    private enum curlPath = "LD_LIBRARY_PATH at the directory holding libcurl.so.4 (NixOS: export LD_LIBRARY_PATH=";
    private enum curlNix = "\"$(nix-build '<nixpkgs>' -A curl.out --no-out-link)/lib\")";
    /// How to make libcurl loadable for DUB.
    enum dubCurlFix = curlPackage ~ curlPath ~ curlNix;
}

/// The libcurl DUB would load, or null when the loader finds none (FLINT-E0820 is then the caller's to raise).
/// On Windows DUB loads it from its own directory first, which `dubDirectory` names.
string dubCurl(string dubDirectory = null)
{
    import flint_tool.sys.posix : loadableLibrary;

    version (Windows)
    {
        import std.file : exists;
        import std.path : buildPath;

        foreach (name; dubCurlLibraries)
            if (dubDirectory.length && exists(buildPath(dubDirectory, name)))
                return buildPath(dubDirectory, name);
    }
    return loadableLibrary(dubCurlLibraries);
}

/// The commands `flint toolchain install` runs.
string[][] installCommands(const ref Home home, string directory, bool pgo, string linker,
        bool sanitizers = false, bool musl = false)
{
    import std.path : buildPath;

    import flint_tool.toolchain.host : dmdArm64Host, dmdForkHost, upstreamDmdHost;

    const installer = buildPath(home.root, "tools", "install_toolchains.py");
    static if (upstreamDmdHost)
    {
        // ADR-026: the upstream DMD, LDC, then the Flint DUB built with LDC. The receipt follows all three. Embedded C
        // uses MSVC, so no clang is installed; the sanitizer and musl lanes are Linux-only. Python is `python` there.
        string[][] upstreamCommands = [
            ["python", installer, "--compiler", "dmd", "--destination", directory],
            ["python", installer, "--compiler", "ldc", "--destination", directory],
            ["python", installer, "--compiler", "dub", "--destination", directory]
        ];
        if (directory == buildPath(home.root, ".tools"))
            upstreamCommands ~= [
            "python", buildPath(home.root, "tools", "install_quality_tools.py")
        ];
        return upstreamCommands;
    }
    else static if (!dmdForkHost)
    {
        // ADR-024: LDC, then the Flint-patched DUB built with it. The receipt follows the second. Embedded C
        // uses the host's C compiler; the sanitizer and musl lanes are Linux x86-64 only.
        string[][] hostCommands = [
            ["python3", installer, "--compiler", "ldc", "--destination", directory],
            ["python3", installer, "--compiler", "dub", "--destination", directory]
        ];
        // ADR-025 section 3: arm64 hosts first build the forked DMD with its AArch64 code generator, so the
        // receipt follows the third command there.
        static if (dmdArm64Host)
            hostCommands = [["python3", installer, "--compiler", "dmd", "--destination", directory]] ~ hostCommands;
        if (directory == buildPath(home.root, ".tools"))
        {
            const quality = buildPath(home.root, "tools", "install_quality_tools.py");
            hostCommands ~= ["python3", quality, "--compiler", "ldc2"];
        }
        return hostCommands;
    }
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
        out ToolchainReceipt receipt, ref Report report, string dubOutput = null)
{
    import flint.serde : DecodeOptions, UnknownFields;
    import flint.serde.owned : deserialize;
    import std.path : buildPath;
    import flint_tool.support.files : sha256File;

    import flint_tool.toolchain.host : dmdArm64Host, dmdForkHost, upstreamDmdHost;

    DecodeOptions lenient;
    lenient.unknownFields = UnknownFields.ignore;
    static if (upstreamDmdHost)
        return composeUpstreamReceipt(home, directory, dmdOutput, ldcOutput, dubOutput, receipt, report);
    else static if (dmdArm64Host)
        return composeArm64Receipt(home, directory, dmdOutput, ldcOutput, dubOutput, receipt, report);
    else static if (!dmdForkHost)
        return composeHostReceipt(home, directory, dmdOutput, ldcOutput, receipt, report);
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

/// What `install_toolchains.py --compiler dub` prints (ADR-024).
struct InstallerDub
{
    /// Source archive checksum.
    string sha256;
    /// DUB fork patch hash.
    string dub_patch_sha256;
    /// Installed dub hash.
    string dub_sha256;
}

/// The receipt on a host without the DMD fork, from the LDC and DUB installer outputs. The DMD role is
/// LDC's ldmd2, so its fields record the LDC archive and the ldmd2 binary, and no DMD patch.
private bool composeHostReceipt(const ref Home home, string directory, string firstOutput,
        string secondOutput, out ToolchainReceipt receipt, ref Report report)
{
    import flint.serde : DecodeOptions, UnknownFields;
    import flint.serde.owned : deserialize;
    import std.path : buildPath;
    import flint_tool.support.files : sha256File;

    DecodeOptions lenient;
    lenient.unknownFields = UnknownFields.ignore;
    // The installer runs LDC first, then DUB (installCommands).
    auto ldc = deserialize!InstallerTool(lastJsonLine(firstOutput), lenient);
    auto dub = deserialize!InstallerDub(lastJsonLine(secondOutput), lenient);
    if (!ldc.ok || !dub.ok || dub.value.dub_patch_sha256.length == 0)
    {
        report.error("FLINT-E0814", "the installer did not print its receipt", "flint toolchain install --plan");
        return false;
    }
    receipt.installer_sha256 = sha256File(buildPath(home.root, "tools", "install_toolchains.py"));
    receipt.dmd = ReceiptDmd(home.versions["ldc"], ldc.value.sha256, sha256File(componentPath(home,
            directory, "dmd")), dub.value.dub_sha256, "", dub.value.dub_patch_sha256, "", false);
    receipt.ldc = ReceiptTool(home.versions["ldc"], ldc.value.sha256, sha256File(componentPath(home,
            directory, "ldc2")));
    return true;
}

/// The receipt on Windows (ADR-026), from the DMD, LDC and DUB installer outputs: the DMD archive and the installed
/// dmd binary, the Flint DUB's binary and the digest of its two patches, and no DMD patch.
private bool composeUpstreamReceipt(const ref Home home, string directory, string dmdOutput,
        string ldcOutput, string dubOutput, out ToolchainReceipt receipt, ref Report report)
{
    import flint.serde : DecodeOptions, UnknownFields;
    import flint.serde.owned : deserialize;
    import std.path : buildPath;
    import flint_tool.support.files : sha256File;

    DecodeOptions lenient;
    lenient.unknownFields = UnknownFields.ignore;
    auto dmd = deserialize!InstallerTool(lastJsonLine(dmdOutput), lenient);
    auto ldc = deserialize!InstallerTool(lastJsonLine(ldcOutput), lenient);
    auto dub = deserialize!InstallerDub(lastJsonLine(dubOutput), lenient);
    if (!dmd.ok || !ldc.ok || !dub.ok || dmd.value.sha256.length == 0 || dub.value.dub_patch_sha256.length == 0)
    {
        report.error("FLINT-E0814", "the installer did not print its receipt", "flint toolchain install --plan");
        return false;
    }
    receipt.installer_sha256 = sha256File(buildPath(home.root, "tools", "install_toolchains.py"));
    receipt.dmd = ReceiptDmd(home.versions["dmd"], dmd.value.sha256, sha256File(componentPath(home,
            directory, "dmd")), dub.value.dub_sha256, "", dub.value.dub_patch_sha256, "", false);
    receipt.ldc = ReceiptTool(home.versions["ldc"], ldc.value.sha256, sha256File(componentPath(home,
            directory, "ldc2")));
    return true;
}

/// The receipt on an arm64 host (ADR-025 section 3), from the DMD, LDC and DUB installer outputs: the forked DMD
/// built from the pinned release's sources with its patches, and the Flint DUB.
private bool composeArm64Receipt(const ref Home home, string directory, string dmdOutput,
        string ldcOutput, string dubOutput, out ToolchainReceipt receipt, ref Report report)
{
    import flint.serde : DecodeOptions, UnknownFields;
    import flint.serde.owned : deserialize;
    import std.path : buildPath;
    import flint_tool.support.files : sha256File;

    DecodeOptions lenient;
    lenient.unknownFields = UnknownFields.ignore;
    auto dmd = deserialize!InstallerDmd(lastJsonLine(dmdOutput), lenient);
    auto ldc = deserialize!InstallerTool(lastJsonLine(ldcOutput), lenient);
    auto dub = deserialize!InstallerDub(lastJsonLine(dubOutput), lenient);
    if (!dmd.ok || !ldc.ok || !dub.ok || dmd.value.flint_fork.dmd_patch_sha256.length == 0
            || dub.value.dub_patch_sha256.length == 0)
    {
        report.error("FLINT-E0814", "the installer did not print its receipt", "flint toolchain install --plan");
        return false;
    }
    receipt.installer_sha256 = sha256File(buildPath(home.root, "tools", "install_toolchains.py"));
    receipt.dmd = ReceiptDmd(home.versions["dmd"], dmd.value.sha256,
            dmd.value.flint_fork.dmd_sha256, dub.value.dub_sha256,
            dmd.value.flint_fork.dmd_patch_sha256, dub.value.dub_patch_sha256,
            dmd.value.flint_fork.prelude_sha256, false);
    receipt.ldc = ReceiptTool(home.versions["ldc"], ldc.value.sha256, sha256File(componentPath(home,
            directory, "ldc2")));
    return true;
}

/// SHA-256 of the DMD patches an arm64 host applies, concatenated in order, as install_toolchains.py computes it:
/// the shared patch, then on macOS the Darwin overlay.
string arm64DmdPatchDigest(const ref Home home)
{
    import std.digest.sha : SHA256, toHexString;
    import std.file : exists, read;
    import std.path : buildPath;
    import std.string : toLower;

    version (OSX)
        immutable names = ["dmd-2.114.0-flint.patch", "dmd-2.114.0-flint-darwin.patch"];
    else
        immutable names = ["dmd-2.114.0-flint.patch"];
    SHA256 digest;
    foreach (name; names)
    {
        const path = buildPath(home.root, "toolchain", name);
        if (!exists(path))
            return null;
        digest.put(cast(const(ubyte)[]) read(path));
    }
    return toHexString(digest.finish()).toLower.idup;
}

/// SHA-256 of the shared DUB patch and a host's overlay (Windows, macOS) concatenated in order, as
/// install_toolchains.py computes it.
string dubPatchDigest(const ref Home home, string overlay)
{
    import std.digest.sha : SHA256, toHexString;
    import std.file : exists, read;
    import std.path : buildPath;
    import std.string : toLower;

    SHA256 digest;
    foreach (name; ["dub-1.43.0-flint.patch", overlay])
    {
        const path = buildPath(home.root, "toolchain", name);
        if (!exists(path))
            return null;
        digest.put(cast(const(ubyte)[]) read(path));
    }
    return toHexString(digest.finish()).toLower.idup;
}
