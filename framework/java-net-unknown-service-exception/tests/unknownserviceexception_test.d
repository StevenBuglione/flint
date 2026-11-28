// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module flint.java.net.unknownserviceexception_test;

import flint.java.io : IOException;
import flint.java.net.unknownserviceexception : UnknownServiceException;

@safe:

@("UnknownServiceException is a checked IOException with an optional detail message")
unittest
{
    static assert(is(UnknownServiceException : IOException));

    const auto absent = new UnknownServiceException();
    assert(absent.getMessage() is null);
    assert(absent.getCause() is null);
    assert((new UnknownServiceException(cast(string) null)).getMessage() is null);

    const auto empty = new UnknownServiceException("");
    assert(empty.getMessage() !is null);
    assert(empty.getMessage().length == 0);

    const line = __LINE__ + 1;
    auto explicit = new UnknownServiceException("unsupported content type");
    assert(explicit.file == __FILE__);
    assert(explicit.line == line);
    assert(explicit.getCause() is null);

    bool caughtAsIo;
    try
        throw explicit;
    catch (IOException caught)
    {
        caughtAsIo = caught is explicit;
        assert(caught.getMessage() == "unsupported content type");
    }
    assert(caughtAsIo);
}
