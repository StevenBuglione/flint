// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module flint.java.net.unknownhostexception_test;

import flint.java.io : IOException;
import flint.java.net.unknownhostexception : UnknownHostException;

@safe:

unittest
{
    auto noMessage = new UnknownHostException();
    assert(cast(IOException) noMessage !is null);
    assert(noMessage.getMessage() is null);
    assert(noMessage.getCause() is null);

    auto withMessage = new UnknownHostException("missing.invalid");
    assert(withMessage.getMessage() == "missing.invalid");
    assert(withMessage.getCause() is null);

    auto emptyMessage = new UnknownHostException("");
    assert(emptyMessage.getMessage().length == 0);
    assert(emptyMessage.getCause() is null);

    auto nullMessage = new UnknownHostException(null);
    assert(nullMessage.getMessage() is null);

    auto rootCause = new Exception("bad literal");
    auto withCause = new UnknownHostException("0177.0.0.1", rootCause);
    assert(withCause.getMessage() == "0177.0.0.1");
    assert(withCause.getCause() is rootCause);

    bool caughtAsIo;
    try
    {
        throw new UnknownHostException("host.example");
    }
    catch (IOException e)
    {
        caughtAsIo = cast(UnknownHostException) e !is null && e.getMessage() == "host.example";
    }
    assert(caughtAsIo);
}

@("Java's cause lifecycle: the no-argument and message constructors keep the cause open")
unittest
{
    auto root = new IOException("root cause");
    auto unnamed = new UnknownHostException();
    unnamed.initCause(root);
    assert(unnamed.getCause() is root);

    auto named = new UnknownHostException("detail");
    named.initCause(root);
    assert(named.getCause() is root);
}
