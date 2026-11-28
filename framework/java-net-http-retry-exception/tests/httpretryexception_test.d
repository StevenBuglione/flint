// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module flint.java.net.httpretryexception_test;

import flint.java.io : IOException;
import flint.java.net.httpretryexception : HttpRetryException;

@safe:

@("HttpRetryException is a checked IOException carrying a response code, reason and location")
unittest
{
    static assert(is(HttpRetryException : IOException));

    const line = __LINE__ + 1;
    auto absentLocation = new HttpRetryException("server busy", 503);
    assert(absentLocation.file == __FILE__);
    assert(absentLocation.line == line);
    assert(absentLocation.responseCode() == 503);
    assert(absentLocation.getReason() == "server busy");
    assert(absentLocation.getMessage() == "server busy");
    assert(absentLocation.getLocation() is null);
    assert(absentLocation.getCause() is null);

    auto located = new HttpRetryException("redirect", 307, "http://example.test/next");
    assert(located.responseCode() == 307);
    assert(located.getReason() == "redirect");
    assert(located.getLocation() == "http://example.test/next");

    auto absentDetail = new HttpRetryException(cast(string) null, 500, null);
    assert(absentDetail.getReason() is null);
    assert(absentDetail.getMessage() is null);
    assert(absentDetail.getLocation() is null);

    auto emptyDetail = new HttpRetryException("", 500);
    assert(emptyDetail.getReason() is null);
    assert(emptyDetail.getMessage() is null);

    bool caughtAsIo;
    try
        throw located;
    catch (IOException caught)
    {
        caughtAsIo = caught is located;
        assert(caught.getMessage() == "redirect");
    }
    assert(caughtAsIo);
}
