/++
Ported from spring-projects/spring-framework v7.1.0,
spring-test/src/test/java/org/springframework/test/web/servlet/result/MockMvcResultMatchersTests.java.
Copyright 2002-present the original author or authors.
Licensed under the Apache License, Version 2.0 (https://www.apache.org/licenses/LICENSE-2.0).
Modified by the Flint authors.
+/
module mock_mvc_result_matchers_tests;

import flint.java.lang : AssertionError;
import flint.mock.web : MockHttpServletResponse;
import flint.test.web.servlet : DefaultMvcResult, ResultMatcher;
import flint.test.web.servlet.result : MockMvcResultMatchers;

@safe:

private alias Matchers = MockMvcResultMatchers;

private DefaultMvcResult stub(string redirectTo = null)
{
    auto response = new MockHttpServletResponse;
    if (redirectTo !is null)
        response.sendRedirect(redirectTo);
    return new DefaultMvcResult(null, response);
}

private void fails(ResultMatcher matcher, DefaultMvcResult result, string message)
{
    try
    {
        matcher.match(result);
        assert(false);
    }
    catch (AssertionError failure)
        assert(failure.getMessage() == message, failure.getMessage());
}

@("redirect")
unittest
{
    Matchers.redirectedUrl("/resource/1").match(stub("/resource/1"));
}

@("redirectWithNullAssertsNoRedirectOccurred")
unittest
{
    Matchers.redirectedUrl(null).match(stub());
}

@("redirectNonMatching")
unittest
{
    fails(Matchers.redirectedUrl("/resource/2"), stub("/resource/1"),
            "Redirected URL expected:</resource/2> but was:</resource/1>");
}

@("redirectWithNullNonMatchingBecauseRedirectOccurred")
unittest
{
    fails(Matchers.redirectedUrl(null), stub("/resource/1"), "Redirected URL expected:<null> but was:</resource/1>");
}

@("redirectWithUrlTemplate")
unittest
{
    Matchers.redirectedUrlTemplate("/orders/{orderId}/items/{itemId}", 1, 2).match(stub("/orders/1/items/2"));
}

@("redirectWithMatchingPattern")
unittest
{
    Matchers.redirectedUrlPattern("/resource/*").match(stub("/resource/1"));
}

@("redirectWithNonMatchingPattern")
unittest
{
    fails(Matchers.redirectedUrlPattern("/resource/"), stub("/resource/1"),
            "'/resource/' is not an Ant-style path pattern");
}

unittest
{
    fails(Matchers.redirectedUrlPattern("/resource/*"), stub(),
            "Redirected URL 'null' does not match the expected URL pattern '/resource/*'");
    fails(Matchers.redirectedUrl(""), stub(), "Redirected URL expected:<> but was:<null>");
    Matchers.redirectedUrlTemplate("/resource/{name}", "deux cafés").match(stub("/resource/deux%20caf%C3%A9s"));
}
