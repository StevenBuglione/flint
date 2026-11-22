module flint_tool.toolchain.environment_test;

import flint.test : expect;

@safe:

@("the loader probe finds the C library (kernel32 on Windows) and refuses a missing library")
unittest
{
    import flint_tool.sys.posix : loadableLibrary;

    version (Windows)
    {
        expect(loadableLibrary(["flint-absent-test.dll", "kernel32.dll"])).toEqual("kernel32.dll");
        expect(loadableLibrary(["flint-absent-test.dll"]).length).toEqual(0);
    }
    else version (OSX)
    {
        expect(loadableLibrary(["libflint-absent-test.9.dylib", "libSystem.B.dylib"])).toEqual("libSystem.B.dylib");
        expect(loadableLibrary(["libflint-absent-test.9.dylib"]).length).toEqual(0);
    }
    else
    {
        expect(loadableLibrary(["libflint-absent-test.so.9", "libc.so.6"])).toEqual("libc.so.6");
        expect(loadableLibrary(["libflint-absent-test.so.9"]).length).toEqual(0);
    }
}

@("an installer failure is summarised by its last line")
unittest
{
    import flint_tool.commands.tooling : lastLine;

    expect(lastLine("Traceback (most recent call last):\n  File \"x\"\nSystemExit: dub cannot download\n\n")).toEqual(
            "SystemExit: dub cannot download");
    expect(lastLine("").length).toEqual(0);
}

@("dmd.conf splits only when the toolchain path has a space and %@P% is unquoted")
unittest
{
    import std.file : mkdirRecurse, rmdirRecurse, tempDir, write;
    import std.path : buildPath;
    import flint_tool.toolchain.toolchain : dmdConfSplits;

    const root = buildPath(tempDir(), "flint test dmd conf");
    mkdirRecurse(root);
    scope (exit)
        rmdirRecurse(root);
    write(buildPath(root, "dmd.conf"), "[Environment64]\nDFLAGS=-I%@P%/../../src/phobos -fPIC\n");
    expect(dmdConfSplits(buildPath(root, "dmd"))).toEqual(true);
    write(buildPath(root, "dmd.conf"), "[Environment64]\nDFLAGS=\"-I%@P%/../../src/phobos\" -fPIC\n");
    expect(dmdConfSplits(buildPath(root, "dmd"))).toEqual(false);
    expect(dmdConfSplits("/opt/flint/.tools/dmd2/linux/bin64/dmd")).toEqual(false);
}

@("the cross target's ldc2.conf leaves a project path with spaces")
unittest
{
    import std.algorithm.searching : any, startsWith;
    import std.ascii : isWhite;
    import flint_tool.commands.packaging : configurationPath;

    import std.path : buildPath;

    expect(configurationPath("/work/shop", "linux-x86_64-musl", "x")).toEqual(buildPath("/work/shop",
            ".flint", "generated", "ldc2-linux-x86_64-musl.conf"));
    const moved = configurationPath("/work/my shop", "linux-x86_64-musl", "x");
    expect(moved.any!isWhite).toEqual(false);
    expect(configurationPath("/work/my shop", "linux-x86_64-musl", "x")).toEqual(moved);
}
