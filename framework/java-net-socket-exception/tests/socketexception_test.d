// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module flint.java.net.socketexception_test;

import flint.java.io : IOException;
import flint.java.lang : RuntimeException;
import flint.java.net.socketexception : SocketException;

@safe:

@("SocketException is a checked IOException with an optional detail message and cause")
unittest
{
    static assert(is(SocketException : IOException));

    const auto absent = new SocketException();
    assert(absent.getMessage() is null);
    assert(absent.getCause() is null);
    assert((new SocketException(cast(string) null)).getMessage() is null);

    const auto empty = new SocketException("");
    assert(empty.getMessage() is null);

    const line = __LINE__ + 1;
    auto explicit = new SocketException("connection reset");
    assert(explicit.file == __FILE__);
    assert(explicit.line == line);
    assert(explicit.getMessage() == "connection reset");
    assert(explicit.getCause() is null);

    auto root = new RuntimeException("peer closed");
    auto caused = new SocketException(null, root);
    assert(caused.getCause() is root);
    assert(caused.getMessage() is null);

    auto fromCause = new SocketException(cast(Throwable) root);
    assert(fromCause.getCause() is root);
    assert(fromCause.getMessage() !is null);
    assert(fromCause.getMessage().length > 0);

    bool caughtAsIo;
    try
        throw explicit;
    catch (IOException caught)
    {
        caughtAsIo = caught is explicit;
        assert(caught.getMessage() == "connection reset");
    }
    assert(caughtAsIo);
}
