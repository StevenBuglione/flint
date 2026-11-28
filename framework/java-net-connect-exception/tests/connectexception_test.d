// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module flint.java.net.connectexception_test;

import flint.java.io : IOException;
import flint.java.net.connectexception : ConnectException;
import flint.java.net.socketexception : SocketException;

@safe:

@("ConnectException is a checked socket exception with an optional detail message")
unittest
{
    static assert(is(ConnectException : SocketException));
    static assert(is(ConnectException : IOException));

    const auto absent = new ConnectException();
    assert(absent.getMessage() is null);
    assert(absent.getCause() is null);
    assert((new ConnectException(cast(string) null)).getMessage() is null);

    const auto empty = new ConnectException("");
    assert(empty.getMessage() is null);

    const line = __LINE__ + 1;
    auto explicit = new ConnectException("connection refused");
    assert(explicit.file == __FILE__);
    assert(explicit.line == line);
    assert(explicit.getMessage() == "connection refused");
    assert(explicit.getCause() is null);

    bool caughtAsSocket;
    try
        throw explicit;
    catch (SocketException caught)
    {
        caughtAsSocket = caught is explicit;
        assert(caught.getMessage() == "connection refused");
    }
    assert(caughtAsSocket);

    bool caughtAsIo;
    try
        throw explicit;
    catch (IOException caught)
    {
        caughtAsIo = caught is explicit;
    }
    assert(caughtAsIo);
}
