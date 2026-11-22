module flint_tool.support.archive_test;

import flint_tool.support.archive : Entry, octal755, tarArchive;
import flint.test : expect;

@safe:

@("tar archives are block aligned, end with two zero blocks and checksum their headers")
unittest
{
    const archive = tarArchive([
        Entry("bin/", null, octal755), Entry("bin/app", cast(const(ubyte)[]) "hello", octal755)
    ], 1_700_000_000);
    expect(archive.length).toEqual(512 + 512 + 512 + 1024);
    expect(cast(const(char)[]) archive[512 .. 519]).toEqual("bin/app");
    expect(archive[512 + 156]).toEqual(cast(ubyte) '0');
    expect(archive[156]).toEqual(cast(ubyte) '5');
    uint sum;
    foreach (i, b; archive[512 .. 1024])
        sum += i >= 148 && i < 156 ? ' ' : b;
    import std.conv : to;
    import std.string : rightJustify;

    const expected = rightJustify(sum.to!string(8), 6, '0');
    expect((cast(const(char)[]) archive[512 + 148 .. 512 + 154]).idup).toEqual(expected.idup);
    expect(cast(const(char)[]) archive[1024 .. 1029]).toEqual("hello");
}

@("long paths split into the ustar prefix")
unittest
{
    string path = "config/";
    foreach (_; 0 .. 12)
        path ~= "directory/";
    path ~= "file.toml";
    const archive = tarArchive([Entry(path, cast(const(ubyte)[]) "x")]);
    expect(archive[345] != 0).toEqual(true);
}
