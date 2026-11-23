/// Where the pinned toolchain lives on this host (ADR-024).
///
/// Linux x86-64 runs the Flint DMD/DUB fork: the forked DMD with its compile server, the parallel
/// DUB pipeline and direct linking.
///
/// macOS arm64 and Linux arm64 run the forked DMD with its AArch64 code generator (ADR-025 section 3),
/// built from source with LDC by `install_toolchains.py --compiler dmd`. Their DUB is the Flint-patched
/// DUB 1.43.0 built from source with LDC (ADR-024); on macOS with the macOS overlay patch, whose pipeline
/// writes Darwin archives. The pipeline stays off on Linux arm64 for now.
///
/// Windows x86-64 runs the upstream DMD of the pinned Windows release and the Flint DUB, built from source with
/// LDC and the Windows overlay patch, whose pipeline spawns with CreateProcess and writes COFF archives (ADR-026).
module flint_tool.toolchain.host;

@safe:

version (OSX)
{
    /// The forked DMD and its compile server are installed on this host.
    enum bool dmdForkHost = false;
    /// The upstream DMD fills its own role on this host.
    enum bool upstreamDmdHost = false;
    /// The forked DMD with its AArch64 code generator fills the DMD role (ADR-025 section 3).
    enum bool dmdArm64Host = true;
    /// The pinned DMD release's directory for this operating system.
    enum string dmdOsDirectory = "osx";
    /// The Flint DUB's parallel pipeline builds on this host.
    enum bool dubPipelineHost = true;
    /// The pinned LDC release directory name.
    enum string ldcPlatform = "osx-arm64";
    /// The suffix of an executable file name.
    enum string executableSuffix = "";
    /// The separator between PATH entries.
    enum string pathListSeparator = ":";
}
else version (Windows)
{
    /// The forked DMD and its compile server are installed on this host.
    enum bool dmdForkHost = false;
    /// The upstream DMD fills its own role on this host.
    enum bool upstreamDmdHost = true;
    /// The forked DMD with its AArch64 code generator fills the DMD role (ADR-025 section 3).
    enum bool dmdArm64Host = false;
    /// The pinned DMD release's directory for this operating system.
    enum string dmdOsDirectory = "windows";
    /// The Flint DUB's parallel pipeline builds on this host.
    enum bool dubPipelineHost = true;
    /// The pinned LDC release directory name.
    enum string ldcPlatform = "windows-x64";
    /// The suffix of an executable file name.
    enum string executableSuffix = ".exe";
    /// The separator between PATH entries.
    enum string pathListSeparator = ";";
}
else version (AArch64)
{
    /// The forked DMD and its compile server are installed on this host.
    enum bool dmdForkHost = false;
    /// The upstream DMD fills its own role on this host.
    enum bool upstreamDmdHost = false;
    /// The forked DMD with its AArch64 code generator fills the DMD role (ADR-025 section 3).
    enum bool dmdArm64Host = true;
    /// The pinned DMD release's directory for this operating system.
    enum string dmdOsDirectory = "linux";
    /// The Flint DUB's parallel pipeline builds on this host.
    enum bool dubPipelineHost = false;
    /// The pinned LDC release directory name.
    enum string ldcPlatform = "linux-aarch64";
    /// The suffix of an executable file name.
    enum string executableSuffix = "";
    /// The separator between PATH entries.
    enum string pathListSeparator = ":";
}
else
{
    /// The forked DMD and its compile server are installed on this host.
    enum bool dmdForkHost = true;
    /// The upstream DMD fills its own role on this host.
    enum bool upstreamDmdHost = false;
    /// The forked DMD with its AArch64 code generator fills the DMD role (ADR-025 section 3).
    enum bool dmdArm64Host = false;
    /// The pinned DMD release's directory for this operating system.
    enum string dmdOsDirectory = "linux";
    /// The Flint DUB's parallel pipeline builds on this host.
    enum bool dubPipelineHost = true;
    /// The pinned LDC release directory name.
    enum string ldcPlatform = "linux-x86_64";
    /// The suffix of an executable file name.
    enum string executableSuffix = "";
    /// The separator between PATH entries.
    enum string pathListSeparator = ":";
}

/// `name` with the host's executable suffix.
string executable(string name) pure nothrow
{
    return name ~ executableSuffix;
}

/// The pinned LDC's bin directory, relative to the toolchain directory.
string ldcBin(string ldcVersion) pure
{
    import std.path : buildPath;

    return buildPath("ldc2-" ~ ldcVersion ~ "-" ~ ldcPlatform, "bin");
}

/// The directory holding the executable that fills the DMD role, relative to the toolchain directory.
string dmdBin(string ldcVersion) pure
{
    import std.path : buildPath;

    static if (dmdForkHost)
        return buildPath("dmd2", "linux", "bin64");
    else static if (upstreamDmdHost)
        return buildPath("dmd2", "windows", "bin64");
    else static if (dmdArm64Host)
        return buildPath("dmd2", dmdOsDirectory, "bin64");
    else
        return ldcBin(ldcVersion);
}

/// The executable name that fills the DMD role.
enum string dmdExecutable = (dmdForkHost || upstreamDmdHost || dmdArm64Host ? "dmd" : "ldmd2") ~ executableSuffix;

/// The directory holding the pinned DUB, relative to the toolchain directory.
string dubBin(string dubVersion) pure
{
    import std.path : buildPath;

    static if (dmdForkHost)
        return buildPath("dmd2", "linux", "bin64");
    else
        return buildPath("dub-" ~ dubVersion, "bin"); // The Flint DUB built from source (ADR-024, ADR-026).
}

/// The pinned version the DMD-role executable reports: DMD's, or LDC's for ldmd2.
string dmdRoleVersion(string dmdVersion, string ldcVersion) pure
{
    return dmdForkHost || upstreamDmdHost || dmdArm64Host ? dmdVersion : ldcVersion;
}
