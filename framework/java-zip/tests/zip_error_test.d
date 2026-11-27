// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module zip_error_test;

import flint.java.util.zip : ZipError;

@safe:

@("ZipError keeps Java's detail message and is catchable inside the zip package")
unittest
{
    static assert(is(ZipError : Exception));

    const nullMessage = new ZipError(null);
    assert(nullMessage.getMessage() is null);

    const empty = new ZipError("");
    assert(empty.getMessage() !is null && empty.getMessage().length == 0);

    const invalid = new ZipError("invalid zip");
    assert(invalid.getMessage() == "invalid zip");

    bool caught;
    try
        throw invalid;
    catch (ZipError error)
        caught = error.getMessage() == "invalid zip";
    assert(caught);
}
