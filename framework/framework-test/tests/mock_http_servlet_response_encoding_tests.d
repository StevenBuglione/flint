/++
Ported from spring-projects/spring-framework v7.1.0,
spring-test/src/test/java/org/springframework/mock/web/MockHttpServletResponseTests.java.
Copyright 2002-present the original author or authors.
Licensed under the Apache License, Version 2.0 (https://www.apache.org/licenses/LICENSE-2.0).
Modified by the Flint authors: JUnit cases become D unittests.
+/
module mock_http_servlet_response_encoding_tests;

import flint.java.lang : IllegalArgumentException;
import flint.mock.web : MockHttpServletResponse;

@safe:

@("isoShouldBeDefault")
unittest
{
    auto response = new MockHttpServletResponse;
    assert(!response.isCharset());
    assert(response.getContentType() is null);
    assert(response.getCharacterEncoding() == "ISO-8859-1");
}

@("shouldSetDefault")
unittest
{
    auto response = new MockHttpServletResponse;
    response.setDefaultCharacterEncoding("UTF-8");

    assert(!response.isCharset());
    assert(response.getContentType() is null);
    assert(response.getCharacterEncoding() == "UTF-8");
    response.setContentType("text/plain");
    assert(response.getHeader("Content-Type") == "text/plain");
}

@("shouldResetToDefault")
unittest
{
    auto response = new MockHttpServletResponse;
    response.setDefaultCharacterEncoding("UTF-8");
    response.setCharacterEncoding("ISO-8859-1");

    response.reset();

    assert(!response.isCharset());
    assert(response.getContentType() is null);
    assert(response.getCharacterEncoding() == "UTF-8");
}

@("setDefaultShouldNotChangeEncoding")
unittest
{
    auto response = new MockHttpServletResponse;
    response.setCharacterEncoding("UTF-16");
    assert(response.isCharset());
    assert(response.getContentType() is null);
    assert(response.getCharacterEncoding() == "UTF-16");

    response.setDefaultCharacterEncoding("UTF-8");
    assert(response.getCharacterEncoding() == "UTF-16");
}

@("shouldSetEncodingWithContentType")
unittest
{
    auto response = new MockHttpServletResponse;
    response.setDefaultCharacterEncoding("ISO-8859-1");
    response.setContentType("text/plain;charset=UTF-8");

    assert(response.isCharset());
    assert(response.getContentType() == "text/plain;charset=UTF-8");
    assert(response.getCharacterEncoding() == "UTF-8");
}

@("A null default charset is rejected")
unittest
{
    auto response = new MockHttpServletResponse;
    try
    {
        response.setDefaultCharacterEncoding(null);
        assert(false, "expected an IllegalArgumentException");
    }
    catch (IllegalArgumentException failure)
        assert(failure.getMessage() == "'characterEncoding' must not be null");
    assert(response.getCharacterEncoding() == "ISO-8859-1");
}
