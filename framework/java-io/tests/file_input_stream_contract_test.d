// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
/** Original specification tests for opening files through the Java stream facade. */
module flint.java.io.file_input_stream_contract_test;

import flint.java.io : File, FileInputStream, FileNotFoundException, InputStream;
import std.conv : to;
import std.exception : assertThrown;
import std.file : mkdir, rmdirRecurse, tempDir, write;
import std.path : buildPath;
import std.process : thisProcessID;

@safe:

@("FileInputStream reads unsigned bytes and reaches EOF on regular and empty files")
unittest
{
    const root = buildPath(tempDir(), "flint-file-input-content-" ~ thisProcessID.to!string);
    mkdir(root);
    scope (exit)
        rmdirRecurse(root);
    const path = buildPath(root, "bytes");
    const ubyte[] content = [0, 255];
    write(path, content);

    InputStream input = new FileInputStream(new File(path));
    scope (exit)
        input.close();
    assert(input.read() == 0);
    assert(input.read() == 255);
    assert(input.read() == -1);

    const emptyPath = buildPath(root, "empty");
    write(emptyPath, "");
    auto empty = new FileInputStream(new File(emptyPath));
    scope (exit)
        empty.close();
    assert(empty.read() == -1);
}

@("FileInputStream rejects missing paths and directories as FileNotFoundException")
unittest
{
    const root = buildPath(tempDir(), "flint-file-input-errors-" ~ thisProcessID.to!string);
    mkdir(root);
    scope (exit)
        rmdirRecurse(root);
    assertThrown!FileNotFoundException(new FileInputStream(new File(buildPath(root, "missing"))));
    assertThrown!FileNotFoundException(new FileInputStream(new File(root)));
}
