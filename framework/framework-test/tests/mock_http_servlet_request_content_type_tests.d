/++
Ported from spring-projects/spring-framework v7.1.0,
spring-test/src/test/java/org/springframework/mock/web/MockHttpServletRequestTests.java.
Copyright 2002-present the original author or authors.
Licensed under the Apache License, Version 2.0 (https://www.apache.org/licenses/LICENSE-2.0).
Modified by the Flint authors: use D strings and unittests.
+/
module mock_http_servlet_request_content_type_tests;

import flint.mock.web : MockHttpServletRequest;

@safe:

@("setContentType")
unittest
{
    auto request = new MockHttpServletRequest;
    request.setContentType("test/plain");
    assert(request.getContentType() == "test/plain");
    assert(request.getHeaders("Content-Type") == ["test/plain"]);
    assert(request.getCharacterEncoding() is null);
}

@("setContentTypeUTF8")
unittest
{
    auto request = new MockHttpServletRequest;
    request.setContentType("test/plain;charset=UTF-8");
    assert(request.getContentType() == "test/plain;charset=UTF-8");
    assert(request.getHeader("Content-Type") == "test/plain;charset=UTF-8");
    assert(request.getCharacterEncoding() == "UTF-8");
}

@("contentTypeHeader")
unittest
{
    auto request = new MockHttpServletRequest;
    request.addHeader("Content-Type", "test/plain");
    assert(request.getContentType() == "test/plain");
    assert(request.getHeaders("content-type") == ["test/plain"]);
    assert(request.getCharacterEncoding() is null);
}

@("contentTypeHeaderUTF8")
unittest
{
    auto request = new MockHttpServletRequest;
    request.addHeader("Content-Type", "test/plain;charset=UTF-8");
    assert(request.getContentType() == "test/plain;charset=UTF-8");
    assert(request.getHeader("Content-Type") == "test/plain;charset=UTF-8");
    assert(request.getCharacterEncoding() == "UTF-8");
}

@("contentTypeMultipleCalls")
unittest
{
    auto request = new MockHttpServletRequest;
    request.addHeader("Content-Type", "text/plain");
    request.addHeader("content-type", "text/html");
    assert(request.getContentType() == "text/html");
    assert(request.getHeaders("Content-Type") == ["text/html"]);
}

@("setContentTypeHeaderWithMoreComplexCharsetSyntax")
unittest
{
    auto request = new MockHttpServletRequest;
    const value = `test/plain;charset="utf-8";foo="charset=bar";foocharset=bar;foobar=bar`;
    request.addHeader("Content-Type", value);
    assert(request.getContentType() == value);
    assert(request.getHeader("Content-Type") == value);
    assert(request.getCharacterEncoding() == "UTF-8");
}
