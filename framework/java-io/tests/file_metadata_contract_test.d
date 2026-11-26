// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
/** Original specification tests for the Java File facade's POSIX metadata behavior. */
module flint.java.io.file_metadata_contract_test;

import flint.java.io : File;

@safe:

version (Posix)
{
    @("File classifies a regular file, directory and symbolic link targets")
    unittest
    {
        import std.conv : to;
        import std.file : mkdir, rmdirRecurse, symlink, tempDir, write;
        import std.path : buildPath;
        import std.process : thisProcessID;

        const root = buildPath(tempDir(), "flint-java-file-metadata-" ~ thisProcessID.to!string);
        mkdir(root);
        scope (exit)
            rmdirRecurse(root);
        const path = buildPath(root, "file");
        write(path, "abc");
        symlink("file", buildPath(root, "linked-file"));
        symlink("missing", buildPath(root, "dangling"));

        const directory = new File(root);
        assert(directory.exists() && directory.isDirectory() && !directory.isFile());
        foreach (name; ["file", "linked-file"])
        {
            const file = new File(buildPath(root, name));
            assert(file.exists() && file.isFile() && !file.isDirectory());
            assert(file.canRead() && file.length() == 3);
        }

        foreach (invalid; [
            "", buildPath(root, "missing"), buildPath(root, "dangling"), path ~ "/child",
            path ~ "\0suffix"
        ])
        {
            const file = new File(invalid);
            assert(!file.exists() && !file.isFile() && !file.isDirectory() && !file.canRead());
            assert(file.length() == 0 && file.lastModified() == 0);
        }
    }

    @("File makes a POSIX relative pathname absolute without canonicalizing it")
    unittest
    {
        import std.file : getcwd;
        import std.path : buildPath;

        const relative = new File("child/../file");
        assert(relative.getAbsolutePath() == buildPath(getcwd(), "child") ~ "/../file");
        const absolute = new File("/parent/file");
        assert(absolute.getAbsolutePath() == "/parent/file");
    }
}
