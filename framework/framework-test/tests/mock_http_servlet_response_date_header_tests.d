/++
Ported from spring-projects/spring-framework v7.1.0,
spring-test/src/test/java/org/springframework/mock/web/MockHttpServletResponseTests.java.
Copyright 2002-present the original author or authors.
Licensed under the Apache License, Version 2.0 (https://www.apache.org/licenses/LICENSE-2.0).
Modified by the Flint authors: use D strings and unittests.
+/
module mock_http_servlet_response_date_header_tests;

import flint.mock.web : MockHttpServletResponse;

@safe:

private enum string lastModified = "Last-Modified";
private enum long date = 1_437_472_800_000;
private enum string dateText = "Tue, 21 Jul 2015 10:00:00 GMT";

@("setDateHeader")
unittest
{
    auto response = new MockHttpServletResponse;
    response.setDateHeader(lastModified, date);
    assert(response.getHeader(lastModified) == dateText);
}

@("addDateHeader")
unittest
{
    auto response = new MockHttpServletResponse;
    response.addDateHeader(lastModified, date);
    response.addDateHeader(lastModified, date + 1_000);
    assert(response.getHeaders(lastModified) == [dateText, "Tue, 21 Jul 2015 10:00:01 GMT"]);
}
