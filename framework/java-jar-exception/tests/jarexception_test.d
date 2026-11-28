// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module flint.java.util.jar.jarexception_test;

import flint.java.io : IOException;
import flint.java.util.zip.zipexception : ZipException;
import flint.java.util.jar.jarexception : JarException;

@safe:

@("jar exceptions treat any empty detail as absent")
unittest
{
    string detail = "invalid jar entry";
    auto empty = detail[0 .. 0];
    assert(empty !is null);
    assert((new JarException(empty)).msg is null);
    assert((new JarException(null)).msg is null);
    assert((new JarException()).msg is null);
    assert((new JarException(detail)).msg == detail);
}

@("jar exceptions are checked zip exceptions")
unittest
{
    auto error = new JarException("bad");
    assert(cast(ZipException) error !is null);
    assert(cast(IOException) error !is null);
    assert(error.getMessage() == "bad");
}
