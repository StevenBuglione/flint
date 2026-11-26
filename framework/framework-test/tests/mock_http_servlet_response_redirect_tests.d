/++
Ported from spring-projects/spring-framework v7.1.0,
spring-test/src/test/java/org/springframework/mock/web/MockHttpServletResponseTests.java.
Copyright 2002-present the original author or authors.
Licensed under the Apache License, Version 2.0 (https://www.apache.org/licenses/LICENSE-2.0).
Modified by the Flint authors: use D strings and unittests.
+/
module mock_http_servlet_response_redirect_tests;

import flint.jakarta.servlet.http : HttpServletResponse;
import flint.java.lang : IllegalArgumentException, IllegalStateException;
import flint.mock.web : MockHttpServletResponse;

@safe:

@("sendRedirect")
unittest
{
    auto response = new MockHttpServletResponse;
    response.sendRedirect("/redirect");

    assert(response.getStatus() == HttpServletResponse.SC_MOVED_TEMPORARILY);
    assert(response.getHeader("Location") == "/redirect");
    assert(response.getRedirectedUrl() == "/redirect");
    assert(response.isCommitted());
}

@("locationHeaderUpdatesGetRedirectedUrl")
unittest
{
    auto response = new MockHttpServletResponse;
    assert(response.getRedirectedUrl() is null);
    response.setHeader("Location", "/redirect");
    assert(response.getRedirectedUrl() == "/redirect");
    response.addHeader("location", "/second");
    assert(response.getRedirectedUrl() == "/redirect");
    response.setHeader("LOCATION", "/new");
    const readOnlyResponse = response;
    assert(readOnlyResponse.getRedirectedUrl() == "/new");
}

@("modifyStatusAfterSendError")
unittest
{
    auto response = new MockHttpServletResponse;
    response.sendError(HttpServletResponse.SC_NOT_FOUND);
    response.setStatus(HttpServletResponse.SC_OK);

    assert(response.getStatus() == HttpServletResponse.SC_NOT_FOUND);
    assert(response.isCommitted());
}

@("modifyStatusMessageAfterSendError")
unittest
{
    auto response = new MockHttpServletResponse;
    response.sendError(HttpServletResponse.SC_NOT_FOUND);
    response.setStatus(HttpServletResponse.SC_INTERNAL_SERVER_ERROR);

    assert(response.getStatus() == HttpServletResponse.SC_NOT_FOUND);
}

@("A second error after clearing commitment preserves the first error message")
unittest
{
    auto response = new MockHttpServletResponse;
    response.sendError(HttpServletResponse.SC_NOT_FOUND, "missing");
    response.setCommitted(false);
    response.sendError(HttpServletResponse.SC_INTERNAL_SERVER_ERROR);

    assert(response.isCommitted());
    assert(response.getStatus() == HttpServletResponse.SC_INTERNAL_SERVER_ERROR);
    assert(response.getErrorMessage() == "missing");
}

@("A rejected redirect leaves status and headers as they were")
unittest
{
    auto response = new MockHttpServletResponse;
    try
    {
        response.sendRedirect(null);
        assert(false, "expected null redirect rejection");
    }
    catch (IllegalArgumentException failure)
        assert(failure.getMessage() == "Redirect URL must not be null");
    assert(!response.isCommitted());
    assert(response.getStatus() == HttpServletResponse.SC_OK);
    assert(!response.containsHeader("Location"));

    response.sendRedirect("/first");
    try
    {
        response.sendRedirect("/second");
        assert(false, "expected committed response to reject redirect");
    }
    catch (IllegalStateException failure)
        assert(failure.getMessage() == "Cannot send redirect - response is already committed");
    assert(response.getRedirectedUrl() == "/first");
}

@("A mock redirect uses the requested status and preserves the body for either clearBuffer value")
unittest
{
    foreach (clearBuffer; [false, true])
    {
        auto response = new MockHttpServletResponse;
        response.getWriter().write("body");
        response.sendRedirect("/next", 307, clearBuffer);

        assert(response.getStatus() == 307);
        assert(response.getRedirectedUrl() == "/next");
        assert(response.isCommitted());
        assert(response.getContentAsString() == "body");

        response.setCommitted(false);
        response.reset();
        assert(response.getRedirectedUrl() is null);
    }
}

@("An empty Location is distinct from a missing Location")
unittest
{
    auto response = new MockHttpServletResponse;
    response.sendRedirect("");
    assert(response.getRedirectedUrl() !is null);
    assert(response.getRedirectedUrl().length == 0);
}
