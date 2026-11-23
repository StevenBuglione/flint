module flint_tool.project.lock_test;

import flint_tool.diagnostics.report : Report;
import flint_tool.fixtures : codes, fixtureHome;
import flint_tool.project.lock : LockState, checkLock, describeChange, quoted, renderLock;
import flint_tool.project.manifest : Manifest;
import flint_tool.project.resolve : ResolvedPackage, Resolution;
import flint.test : expect;

@safe:

private Resolution resolution(bool workspace)
{
    Resolution value;
    value.workspace = workspace;
    value.packages = [
        ResolvedPackage("flint:arena", "core", workspace ? "workspace" : "flint-home", "/flint/packages/arena",
                null, "flint.arena", null, workspace ? null : "aa"),
        ResolvedPackage("flint:log", "core", workspace ? "workspace" : "flint-home",
                "/flint/packages/log", null, "flint.log", ["flint:conc", "flint:arena"], workspace ? null : "bb")
    ];
    value.direct = ["flint:log"];
    return value;
}

@("the lock renders deterministically, with sorted dependencies and workspace pinning")
unittest
{
    const home = fixtureHome();
    Manifest manifest;
    manifest.name = "shop";
    manifest.version_ = "0.1.0";
    const workspace = resolution(true);
    const text = renderLock(home, manifest, workspace);
    expect(text == renderLock(home, manifest, workspace)).toEqual(true);
    import std.algorithm.searching : canFind;

    expect(text.canFind("pinned_by = \"workspace commit\"")).toEqual(true);
    expect(text.canFind("dependencies = [\"flint:arena\", \"flint:conc\"]")).toEqual(true);
    expect(text.canFind("content_sha256")).toEqual(false);
}

@("a changed graph is reported by package name")
unittest
{
    const before = "[[package]]\nname = \"flint:arena\"\nkind = \"core\"\n\n[[package]]\nname = \"old\"\n";
    const after = "[[package]]\nname = \"flint:arena\"\nkind = \"path\"\n\n[[package]]\nname = \"new\"\n";
    expect(describeChange(before, after)).toEqual(
            "the resolved graph differs from flint.lock: added new, changed flint:arena, removed old");
    expect(describeChange("a = 1\n", "a = 2\n")).toEqual(
            "the platform or toolchain identity recorded in flint.lock differs from this installation");
}

@("checkLock distinguishes current, missing and stale locks")
unittest
{
    import std.file : mkdirRecurse, rmdirRecurse, tempDir, write;
    import std.path : buildPath;
    import std.uuid : randomUUID;

    const directory = buildPath(tempDir(), "flint-lock-" ~ randomUUID().toString());
    mkdirRecurse(directory);
    scope (exit)
        rmdirRecurse(directory);
    Report report;
    expect(checkLock(directory, "x = 1\n", false, report) == LockState.missing).toEqual(true);
    expect(report.items.length).toEqual(0);
    expect(checkLock(directory, "x = 1\n", true, report) == LockState.missing).toEqual(true);
    expect(codes(report)).toEqual(["FLINT-E0201"]);
    write(buildPath(directory, "flint.lock"), "x = 1\n");
    Report again;
    expect(checkLock(directory, "x = 1\n", true, again) == LockState.current).toEqual(true);
    expect(checkLock(directory, "x = 2\n", true, again) == LockState.stale).toEqual(true);
    expect(codes(again)).toEqual(["FLINT-E0202"]);
    expect(again.items[0].line).toEqual(1);
    write(buildPath(directory, "flint.lock"), "x = 1\r\ny = 2\r\n");
    Report crlf;
    expect(checkLock(directory, "x = 1\ny = 2\n", true, crlf) == LockState.current).toEqual(true);
    expect(crlf.items.length).toEqual(0);
    expect(quoted("a\"b\\c")).toEqual("\"a\\\"b\\\\c\"");
}
