// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module flint.java.nio.file.path_construction_test;

import flint.java.lang : IllegalArgumentException;
import flint.java.nio.file : InvalidPathException, Path;
import flint.java.nio.file.path : lexicalPath;
import std.exception : collectException;

@safe:

@("Path.of treats null strings and arrays as empty under R26")
unittest
{
    version (Windows)
        enum separator = "\\";
    else
        enum separator = "/";
    assert(Path.of("base", "", "nested" ~ separator, "leaf").toString() == "base" ~ separator
            ~ "nested" ~ separator ~ "leaf");
    assert(Path.of("base", cast(string[]) null).toString() == "base");
    assert(Path.of("base", null).toString() == "base");
    assert(Path.of("base", []).toString() == "base");
    auto empty = Path.of(cast(string) null).toString();
    assert(empty !is null && empty == "");
    assert(Path.of("base", cast(string) null, "leaf").toString() == "base" ~ separator ~ "leaf");
    assert(Path.of(cast(string) null, "leaf").toString() == "leaf");
}

@("Path empty and root components have the Java name counts")
unittest
{
    auto empty = lexicalPath("", null, false);
    assert(!empty.isAbsolute() && empty.getRoot() is null && empty.getParent() is null);
    assert(empty.getFileName() !is null && empty.getFileName().toString() == "");
    assert(empty.getNameCount() == 1 && empty.getName(0).toString() == "" && empty.subpath(0, 1).toString() == "");

    auto root = lexicalPath("///", null, false);
    assert(root.isAbsolute() && root.getRoot().toString() == "/" && root.getNameCount() == 0);
    assert(root.getFileName() is null && root.getParent() is null);
    assert(collectException!IllegalArgumentException(root.getName(0)) !is null);
}

@("Unix Path preserves spelling and accesses relative names")
unittest
{
    auto path = lexicalPath("//café//..", ["/./", "leaf///"], false);
    assert(path.toString() == "/café/.././leaf" && path.getRoot().toString() == "/");
    assert(path.getParent().toString() == "/café/../." && path.getFileName().toString() == "leaf");
    assert(path.getNameCount() == 4 && path.getName(0).toString() == "café");
    assert(path.getName(3).toString() == "leaf" && path.subpath(1, 3).toString() == "../.");
    assert(lexicalPath("a", ["/b"], false).toString() == "a/b");
    assert(lexicalPath("/only", null, false).getParent().toString() == "/");
    assert(lexicalPath("only\\name", null, false).getParent() is null);
    assert(collectException!IllegalArgumentException(path.getName(-1)) !is null);
    assert(collectException!IllegalArgumentException(path.subpath(1, 1)) !is null);
    assert(collectException!IllegalArgumentException(path.subpath(0, 5)) !is null);

    auto failure = collectException!InvalidPathException(lexicalPath("a\0b", null, false));
    assert(failure !is null && failure.getInput() == "a\0b");
    assert(failure.getReason() == "Nul character not allowed" && failure.getIndex() == -1);
}

@("Windows Path distinguishes drive, directory and UNC roots")
unittest
{
    auto drive = lexicalPath("P:/aa", ["bb//"], true);
    assert(drive.isAbsolute() && drive.toString() == "P:\\aa\\bb");
    assert(drive.getRoot().toString() == "P:\\" && drive.getParent().toString() == "P:\\aa");
    assert(drive.getNameCount() == 2 && drive.getFileName().toString() == "bb");
    assert(drive.subpath(0, 2).toString() == "aa\\bb");

    auto driveRelative = lexicalPath("P:aa\\bb", null, true);
    assert(!driveRelative.isAbsolute() && driveRelative.getRoot().toString() == "P:");
    assert(driveRelative.getParent().toString() == "P:aa");
    assert(lexicalPath("P:aa", null, true).getParent().toString() == "P:");
    assert(lexicalPath("P:", null, true).getNameCount() == 0);

    auto directoryRelative = lexicalPath("/aa\\bb", null, true);
    assert(!directoryRelative.isAbsolute() && directoryRelative.getRoot().toString() == "\\");
    assert(directoryRelative.getParent().toString() == "\\aa");

    auto unc = lexicalPath("//server///share//child/", null, true);
    assert(unc.isAbsolute() && unc.toString() == "\\\\server\\share\\child");
    assert(unc.getRoot().toString() == "\\\\server\\share\\" && unc.getParent().toString() == unc.getRoot().toString());
    assert(unc.getNameCount() == 1 && unc.getName(0).toString() == "child");

    auto extended = lexicalPath("\\\\?\\UNC\\server\\share\\aa", null, true);
    assert(extended.toString() == "\\\\server\\share\\aa");
    assert(lexicalPath("\\\\?\\P:\\aa", null, true).toString() == "P:\\aa");
    assert(lexicalPath("aa//./bb/../", null, true).toString() == "aa\\.\\bb\\..");
}

@("Windows Path errors refer to Java UTF-16 indices and stripped input")
unittest
{
    auto failure = collectException!InvalidPathException(lexicalPath("\\\\?\\P:\\a😀:b", null, true));
    assert(failure !is null && failure.getInput() == "P:\\a😀:b" && failure.getIndex() == 6);
    assert(failure.getReason() == "Illegal char <:>");
    failure = collectException!InvalidPathException(lexicalPath("aa /bb", null, true));
    assert(failure !is null && failure.getIndex() == 2 && failure.getReason() == "Trailing char < >");
    failure = collectException!InvalidPathException(lexicalPath("\\\\server", null, true));
    assert(failure !is null && failure.getIndex() == -1 && failure.getReason() == "UNC path is missing sharename");
    failure = collectException!InvalidPathException(lexicalPath("\\\\?\\aa", null, true));
    assert(failure !is null && failure.getInput() == "aa" && failure.getIndex() == -1);
}
