/++
Ported from spring-projects/spring-framework v7.1.0,
spring-test/src/test/java/org/springframework/mock/web/MockHttpServletRequestTests.java.
Copyright 2002-present the original author or authors.
Licensed under the Apache License, Version 2.0 (https://www.apache.org/licenses/LICENSE-2.0).
Modified by the Flint authors: use D strings and unittests.
+/
module mock_http_servlet_request_header_tests;

import flint.java.lang : IllegalArgumentException;
import flint.mock.web : MockHttpServletRequest;

@safe:

private enum string modifiedSince = "If-Modified-Since";
private enum long july2015 = 1_437_472_800_000;

@("httpHeaderNameCasingIsPreserved")
unittest
{
    auto request = new MockHttpServletRequest;
    request.addHeader("Header1", "value1");
    assert(request.getHeaderNames() == ["Header1"]);
    assert(request.getHeader("header1") == "value1");
}

@("httpHeaderRfcFormattedDate")
unittest
{
    auto request = new MockHttpServletRequest;
    request.addHeader(modifiedSince, "Tue, 21 Jul 2015 10:00:00 GMT");
    assert(request.getDateHeader(modifiedSince) == july2015);
}

@("httpHeaderFirstVariantFormattedDate")
unittest
{
    auto request = new MockHttpServletRequest;
    request.addHeader(modifiedSince, "Tue, 21-Jul-15 10:00:00 GMT");
    assert(request.getDateHeader(modifiedSince) == july2015);
}

@("httpHeaderSecondVariantFormattedDate")
unittest
{
    auto request = new MockHttpServletRequest;
    request.addHeader(modifiedSince, "Tue Jul 21 10:00:00 2015");
    assert(request.getDateHeader(modifiedSince) == july2015);
}

@("httpHeaderFormattedDateError")
unittest
{
    auto request = new MockHttpServletRequest;
    request.addHeader(modifiedSince, "This is not a date");
    try
    {
        request.getDateHeader(modifiedSince);
        assert(false, "expected an invalid date to fail");
    }
    catch (IllegalArgumentException)
    {
    }
}
