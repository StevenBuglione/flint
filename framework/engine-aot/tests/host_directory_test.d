module flint.engine.aot.host_directory_test;

import flint.engine.aot.host : describe, DirectoryEntry, DirectoryEntryKind, directoryEntries, FileError;
import std.conv : to;
import std.file : mkdir, rmdirRecurse, tempDir, write;
import std.path : buildPath;
import std.process : thisProcessID;

@safe:

private string fixture()
{
    const path = buildPath(tempDir(), "flint-directory-entries-" ~ thisProcessID.to!string);
    mkdir(path);
    return path;
}

@("directory listing owns its direct names and classifies entries")
unittest
{
    const root = fixture();
    const subdirectory = buildPath(root, "nested");
    FileError error;
    scope (exit)
        rmdirRecurse(root);
    mkdir(subdirectory);
    write(buildPath(root, "test.txt"), "file");
    write(buildPath(subdirectory, "nested.txt"), "nested");

    const entries = directoryEntries(root, error);
    assert(error == FileError.none && entries.length == 2);
    bool fileSeen, directorySeen;
    foreach (entry; entries)
    {
        if (entry.name == "test.txt")
            fileSeen = entry.kind == DirectoryEntryKind.file;
        if (entry.name == "nested")
            directorySeen = entry.kind == DirectoryEntryKind.directory;
    }
    assert(fileSeen && directorySeen);
}

@("directory listing distinguishes an empty directory from an error and enforces its limit")
unittest
{
    const root = fixture();
    scope (exit)
        rmdirRecurse(root);
    FileError error = FileError.other;
    assert(directoryEntries(root, error, 0).length == 0 && error == FileError.none);
    assert(directoryEntries(root, error, size_t.max) is null && error == FileError.resourceExhausted);
    assert(directoryEntries(buildPath(root, "missing"), error) is null && error == FileError.notFound);
    assert(directoryEntries(root ~ "\0ignored", error) is null && error == FileError.notFound);

    const file = buildPath(root, "file");
    write(file, "");
    assert(directoryEntries(file, error) is null && error != FileError.none);
    assert(directoryEntries(root, error, 1).length == 1 && error == FileError.none);
    write(buildPath(root, "second"), "");
    assert(directoryEntries(root, error, 1) is null && error == FileError.resourceExhausted);
    assert(describe(error) == "Directory entry limit exceeded");
    assert(directoryEntries(root, error, 2).length == 2 && error == FileError.none);
}

version (Posix) @("file identity persists on rename and symbolic links have their own identity")
unittest
{
    import std.file : rename, symlink;

    const root = fixture();
    scope (exit)
        rmdirRecurse(root);
    const original = buildPath(root, "original");
    write(original, "file");
    symlink("original", buildPath(root, "symbolic"));

    FileError error;
    const entries = directoryEntries(root, error);
    assert(error == FileError.none && entries.length == 2);
    DirectoryEntry originalEntry, linkEntry;
    foreach (entry; entries)
    {
        if (entry.name == "original")
            originalEntry = entry;
        else if (entry.name == "symbolic")
            linkEntry = entry;
    }
    assert(originalEntry.kind == DirectoryEntryKind.file);
    assert(linkEntry.kind == DirectoryEntryKind.symlink && linkEntry.identity != originalEntry.identity);

    rename(original, buildPath(root, "renamed"));
    const again = directoryEntries(root, error);
    assert(error == FileError.none && again.length == 2);
    bool renamed;
    foreach (entry; again)
        if (entry.name == "renamed")
            renamed = entry.identity == originalEntry.identity;
    assert(renamed);
}
