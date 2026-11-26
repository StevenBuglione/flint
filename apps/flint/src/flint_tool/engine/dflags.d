/// Compiler flags in the spelling of the compiler that receives them.
///
/// policy/profiles.toml, flint.toml additions and the platform modules' version identifiers use DMD's spelling.
/// ldc2 spells the conditional-compilation switches differently: `-d-debug` and `-d-version=`. It rejects
/// `-debug` as an unknown argument, and reads `-version=X` as its `--version` option with a value. DMD rejects
/// LDC's spelling. Every flag a build hands a compiler passes through `spelledFor` first.
module flint_tool.engine.dflags;

@safe:

/// Whether `compiler`, a name or a path, is ldc2, which takes LDC's own spelling. ldmd2 takes DMD's.
bool takesLdcSpelling(string compiler) pure nothrow
{
    import std.algorithm.searching : startsWith;
    import std.path : baseName;

    return baseName(compiler).startsWith("ldc");
}

/// `flags` with the debug and version switches spelled for `compiler`, in order; every other flag unchanged.
string[] spelledFor(scope const(string)[] flags, string compiler) pure nothrow
{
    const ldc = takesLdcSpelling(compiler);
    string[] spelled;
    spelled.reserve(flags.length);
    foreach (flag; flags)
        spelled ~= ldc ? ldcSpelling(flag) : dmdSpelling(flag);
    return spelled;
}

private string ldcSpelling(string flag) pure nothrow
{
    import std.algorithm.searching : startsWith;

    if (flag == "-debug" || flag.startsWith("-debug="))
        return "-d" ~ flag;
    if (flag.startsWith("-version="))
        return "-d" ~ flag;
    return flag;
}

private string dmdSpelling(string flag) pure nothrow
{
    import std.algorithm.searching : startsWith;

    foreach (prefix; ["--d-", "-d-"])
    {
        const rest = flag.startsWith(prefix) ? flag[prefix.length .. $] : null;
        if (rest == "debug" || rest.startsWith("debug=") || rest.startsWith("version="))
            return "-" ~ rest;
    }
    return flag;
}

@("ldc2 gets -d-debug and -d-version=; DMD gets -debug and -version=; other flags pass unchanged")
unittest
{
    const dev = [
        "-preview=dip1000", "-debug", "-g", "-boundscheck=on", "-version=A", "-debug=Trace", "-L-s"
    ];
    assert(spelledFor(dev, "ldc2") == [
        "-preview=dip1000", "-d-debug", "-g", "-boundscheck=on", "-d-version=A", "-d-debug=Trace",
        "-L-s"
    ]);
    assert(spelledFor(dev, "/opt/ldc2-1.43.0/bin/ldc2") == spelledFor(dev, "ldc2"));
    assert(spelledFor(dev, "dmd") == dev);
    assert(spelledFor(dev, "ldmd2") == dev);
    assert(spelledFor(spelledFor(dev, "ldc2"), "/x/dmd") == dev);
    assert(spelledFor(["--d-version=B", "--d-debug", "-version", "-debuglib=x", "-d-debug-info"],
            "dmd") == ["-version=B", "-debug", "-version", "-debuglib=x", "-d-debug-info"]);
    assert(spelledFor(["-debuglib=x", "-version", "-versionX"], "ldc2") == [
        "-debuglib=x", "-version", "-versionX"
    ]);
}
