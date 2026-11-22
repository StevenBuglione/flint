/// Where the pinned toolchain lives on this host (ADR-024).
///
/// Linux x86-64 runs the Flint DMD/DUB fork: the forked DMD with its compile server, the parallel
/// DUB pipeline and direct linking. macOS arm64 has no DMD code generator, so the DMD role of the
/// dev and test profiles is filled by LDC's DMD-compatible driver `ldmd2`, which takes the same
/// canonical flags. Its DUB is the Flint-patched DUB 1.43.0 built from source with LDC. The DUB
/// pipeline writes ELF-style archives and stays off there; the compile server is a DMD feature.
module flint_tool.toolchain.host;

@safe:

version (OSX)
{
    /// The forked DMD and its compile server are installed on this host.
    enum bool dmdForkHost = false;
    /// The pinned LDC release directory name.
    enum string ldcPlatform = "osx-arm64";
}
else
{
    /// The forked DMD and its compile server are installed on this host.
    enum bool dmdForkHost = true;
    /// The pinned LDC release directory name.
    enum string ldcPlatform = "linux-x86_64";
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
    else
        return ldcBin(ldcVersion);
}

/// The executable name that fills the DMD role.
enum string dmdExecutable = dmdForkHost ? "dmd" : "ldmd2";

/// The directory holding the pinned DUB, relative to the toolchain directory.
string dubBin(string dubVersion) pure
{
    import std.path : buildPath;

    static if (dmdForkHost)
        return buildPath("dmd2", "linux", "bin64");
    else
        return buildPath("dub-" ~ dubVersion, "bin");
}

/// The pinned version the DMD-role executable reports: DMD's, or LDC's for ldmd2.
string dmdRoleVersion(string dmdVersion, string ldcVersion) pure
{
    return dmdForkHost ? dmdVersion : ldcVersion;
}
