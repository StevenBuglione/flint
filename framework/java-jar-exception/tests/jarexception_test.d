// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module flint.java.util.jar.jarexception_test;

import flint.java.io : IOException;
import flint.java.lang : IllegalArgumentException, IllegalStateException;
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

@("jar exceptions leave the cause open for one initCause call")
unittest
{
    auto cause = new Exception("root");

    auto noDetail = new JarException();
    assert(noDetail.getCause() is null);
    assert(noDetail.initCause(cause) is noDetail);
    assert(noDetail.getCause() is cause);

    auto withDetail = new JarException("bad");
    assert(withDetail.getCause() is null);
    withDetail.initCause(cause);
    assert(withDetail.getCause() is cause);
}

@("jar exceptions reject a second or a self cause")
unittest
{
    auto error = new JarException("bad");
    auto root = new Exception("root");
    error.initCause(root);

    bool overwrote;
    try
        error.initCause(new Exception("other"));
    catch (IllegalStateException)
        overwrote = true;
    assert(overwrote);
    assert(error.getCause() is root);

    auto self = new JarException("self");
    bool selfCaused;
    try
        self.initCause(self);
    catch (IllegalArgumentException)
        selfCaused = true;
    assert(selfCaused);
    assert(self.getCause() is null);
}
