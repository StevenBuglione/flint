// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module flint.java.net.bindexception_test;

import flint.java.io : IOException;
import flint.java.net.bindexception : BindException;
import flint.java.net.socketexception : SocketException;

@safe:

@("BindException is a checked socket exception with an optional detail message")
unittest
{
    static assert(is(BindException : SocketException));
    static assert(is(BindException : IOException));

    const auto absent = new BindException();
    assert(absent.getMessage() is null);
    assert(absent.getCause() is null);
    assert((new BindException(cast(string) null)).getMessage() is null);

    const auto empty = new BindException("");
    assert(empty.getMessage() is null);

    const line = __LINE__ + 1;
    auto explicit = new BindException("address already in use");
    assert(explicit.file == __FILE__);
    assert(explicit.line == line);
    assert(explicit.getMessage() == "address already in use");
    assert(explicit.getCause() is null);

    bool caughtAsSocket;
    try
        throw explicit;
    catch (SocketException caught)
    {
        caughtAsSocket = caught is explicit;
        assert(caught.getMessage() == "address already in use");
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
