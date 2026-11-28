// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module flint.java.util.zip.zipexception_test;

import flint.java.io : IOException;
import flint.java.util.zip.zipexception : ZipException;

@safe:

@("zip exceptions treat any empty detail as absent")
unittest
{
    string detail = "invalid zip entry";
    auto empty = detail[0 .. 0];
    assert(empty !is null);
    assert((new ZipException(empty)).msg is null);
    assert((new ZipException(null)).msg is null);
    assert((new ZipException()).msg is null);
    assert((new ZipException(detail)).msg == detail);
}

@("zip exceptions are checked IOExceptions")
unittest
{
    auto error = new ZipException("bad");
    assert(cast(IOException) error !is null);
    assert(error.getMessage() == "bad");
}
