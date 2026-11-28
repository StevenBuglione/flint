// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module flint.java.net.portunreachableexception_test;

import flint.java.io : IOException;
import flint.java.net.portunreachableexception : PortUnreachableException;
import flint.java.net.socketexception : SocketException;

@safe:

@("PortUnreachableException is a checked socket exception with an optional detail message")
unittest
{
    static assert(is(PortUnreachableException : SocketException));
    static assert(is(PortUnreachableException : IOException));

    const auto absent = new PortUnreachableException();
    assert(absent.getMessage() is null);
    assert(absent.getCause() is null);
    assert((new PortUnreachableException(cast(string) null)).getMessage() is null);

    const auto empty = new PortUnreachableException("");
    assert(empty.getMessage() is null);

    const line = __LINE__ + 1;
    auto explicit = new PortUnreachableException("port unreachable");
    assert(explicit.file == __FILE__);
    assert(explicit.line == line);
    assert(explicit.getMessage() == "port unreachable");
    assert(explicit.getCause() is null);

    bool caughtAsSocket;
    try
        throw explicit;
    catch (SocketException caught)
    {
        caughtAsSocket = caught is explicit;
        assert(caught.getMessage() == "port unreachable");
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
