module flint.os.glob_test;

import core.sys.posix.stdlib : mkdtemp;
import flint.arena : Status;
import flint.os : GlobOptions, glob;
import std.file : mkdirRecurse, rmdirRecurse, symlink, tempDir, write;
import std.path : buildPath;

private string temporaryRoot()
{
    auto path = buildPath(tempDir(), "flint-os-glob-XXXXXX").dup ~ '\0';
    assert(mkdtemp(path.ptr) !is null);
    return path[0 .. $ - 1].idup;
}

@("recursive glob confines symlinks, cuts cycles and sorts root-relative paths")
unittest
{
    const parent = temporaryRoot();
    scope (exit)
        rmdirRecurse(parent);
    const root = buildPath(parent, "root");
    const outside = buildPath(parent, "outside");
    mkdirRecurse(buildPath(root, "a", "nested"));
    mkdirRecurse(outside);
    write(buildPath(outside, "secret.txt"), "");
    write(buildPath(root, "top.txt"), "");
    write(buildPath(root, "a", "good2.txt"), "");
    write(buildPath(root, "a", "nested", "good7.txt"), "");
    write(buildPath(root, "a", "nested", "bad.txt"), "");
    symlink("a", buildPath(root, "alias"));
    symlink("..", buildPath(root, "a", "up"));
    symlink("../outside", buildPath(root, "escape"));

    const direct = glob(root, "**/good[1-9].tx?");
    assert(direct.ok, direct.error.message);
    assert(direct.value == ["a/good2.txt", "a/nested/good7.txt"]);
    const followed = glob(root, "**/*.txt", GlobOptions(true));
    assert(followed.ok, followed.error.message);
    assert(followed.value == [
        "a/good2.txt", "a/nested/bad.txt", "a/nested/good7.txt", "alias/good2.txt",
        "alias/nested/bad.txt", "alias/nested/good7.txt", "top.txt"
    ]);

    assert(glob(root, "**/*.txt", GlobOptions(false, 2)).error.code == Status.resourceExhausted);
    assert(glob(root, "**/*.txt", GlobOptions(false, 64, 2)).error.code == Status.resourceExhausted);
    assert(glob(root, "../outside/*").error.code == Status.invalidArgument);
    assert(glob(root, "/top.txt").error.code == Status.invalidArgument);
    assert(glob(root, "**/[z-a]").error.code == Status.invalidArgument);
    assert(glob(root, "**/[unterminated").error.code == Status.invalidArgument);
}

@("bounded glob syntax survives deterministic length and character-class cases")
unittest
{
    const root = temporaryRoot();
    scope (exit)
        rmdirRecurse(root);
    write(buildPath(root, "name.txt"), "");
    enum alphabet = "abc*?[]!\\";
    uint seed = 8573;
    foreach (length; 0 .. 257)
    {
        char[256] pattern;
        foreach (ref byteValue; pattern[0 .. length])
        {
            seed = seed * 1_664_525 + 1_013_904_223;
            byteValue = alphabet[(seed >> 16) % alphabet.length];
        }
        const result = glob(root, pattern[0 .. length]);
        assert(result.error.code == Status.invalidArgument || result.ok);
        if (result.ok)
            assert(result.value.length <= 1);
    }

    char[1024] longPattern;
    longPattern[] = 'a';
    assert(glob(root, longPattern[]).ok);
    auto excessive = new char[1_048_576];
    excessive[] = '?';
    assert(glob(root, excessive).error.code == Status.invalidArgument);
}
