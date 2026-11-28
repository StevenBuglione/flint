// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module flint.java.net.noroutetohostexception_test;

import flint.java.io : IOException;
import flint.java.net.noroutetohostexception : NoRouteToHostException;
import flint.java.net.socketexception : SocketException;

@safe:

@("NoRouteToHostException is a checked socket exception with an optional detail message")
unittest
{
    static assert(is(NoRouteToHostException : SocketException));
    static assert(is(NoRouteToHostException : IOException));

    const auto absent = new NoRouteToHostException();
    assert(absent.getMessage() is null);
    assert(absent.getCause() is null);
    assert((new NoRouteToHostException(cast(string) null)).getMessage() is null);

    const auto empty = new NoRouteToHostException("");
    assert(empty.getMessage() is null);

    const line = __LINE__ + 1;
    auto explicit = new NoRouteToHostException("no route to host");
    assert(explicit.file == __FILE__);
    assert(explicit.line == line);
    assert(explicit.getMessage() == "no route to host");
    assert(explicit.getCause() is null);

    bool caughtAsSocket;
    try
        throw explicit;
    catch (SocketException caught)
    {
        caughtAsSocket = caught is explicit;
        assert(caught.getMessage() == "no route to host");
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
