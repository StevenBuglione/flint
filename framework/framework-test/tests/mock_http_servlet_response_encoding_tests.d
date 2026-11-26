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

@("shouldSetUtf8EncodingForJson")
unittest
{
    auto response = new MockHttpServletResponse;
    response.setContentType("application/json");
    assert(!response.isCharset());
    assert(response.getContentType() == "application/json");
    assert(response.getCharacterEncoding() == "UTF-8");
}

@("shouldSetEncodingWithComplexContentTypeSyntax")
unittest
{
    auto response = new MockHttpServletResponse;
    const contentType = `test/plain;charset="utf-8";foo="charset=bar";foocharset=bar;foobar=bar`;
    response.setHeader("Content-Type", contentType);
    assert(response.getContentType() == contentType);
    assert(response.getHeader("Content-Type") == contentType);
    assert(response.getCharacterEncoding() == "UTF-8");
}

@("setContentTypeThenCharacterEncoding")
unittest
{
    auto response = new MockHttpServletResponse;
    response.setContentType("test/plain");
    response.setCharacterEncoding("UTF-8");
    assert(response.getContentType() == "test/plain;charset=UTF-8");
    assert(response.getHeader("Content-Type") == "test/plain;charset=UTF-8");
    assert(response.getCharacterEncoding() == "UTF-8");
}

@("setCharacterEncodingThenContentType")
unittest
{
    auto response = new MockHttpServletResponse;
    response.setCharacterEncoding("UTF-8");
    response.setContentType("test/plain");
    assert(response.getContentType() == "test/plain;charset=UTF-8");
    assert(response.getHeader("Content-Type") == "test/plain;charset=UTF-8");
    assert(response.getCharacterEncoding() == "UTF-8");
}

@("setCharacterEncodingNull")
unittest
{
    auto response = new MockHttpServletResponse;
    response.setContentType("test/plain");
    response.setCharacterEncoding("UTF-8");
    assert(response.getContentType() == "test/plain;charset=UTF-8");
    assert(response.getHeader("Content-Type") == "test/plain;charset=UTF-8");

    response.setCharacterEncoding(null);

    assert(response.getContentType() == "test/plain");
    assert(response.getHeader("Content-Type") == "test/plain");
    assert(response.getCharacterEncoding() == "ISO-8859-1");
    assert(!response.isCharset());
}

@("resetResponseShouldResetCharset")
unittest
{
    auto response = new MockHttpServletResponse;
    assert(response.getContentType() is null);
    assert(response.getCharacterEncoding() == "ISO-8859-1");
    assert(!response.isCharset());

    response.setCharacterEncoding("UTF-8");
    assert(response.isCharset());
    assert(response.getCharacterEncoding() == "UTF-8");
    response.setContentType("text/plain");
    assert(response.getContentType() == "text/plain;charset=UTF-8");
    assert(response.getHeader("Content-Type") == "text/plain;charset=UTF-8");

    response.reset();
    assert(response.getContentType() is null);
    assert(response.getCharacterEncoding() == "ISO-8859-1");
    assert(!response.isCharset());
    response.setContentType("text/plain");
    assert(!response.isCharset());
    assert(response.getContentType() == "text/plain");
    assert(response.getHeader("Content-Type") == "text/plain");
}

@("contentAsStringEncodingWithJson")
unittest
{
    auto response = new MockHttpServletResponse;
    const content = `{"name": "Jürgen"}`;
    response.setContentType("application/json");
    response.getWriter().write(content);
    assert(response.getContentAsString() == content);
}

@("Clearing the charset preserves unrelated Content-Type parameters")
unittest
{
    auto response = new MockHttpServletResponse;
    response.setDefaultCharacterEncoding("US-ASCII");
    response.setContentType(`text/plain;profile="a;charset=b";Charset="UTF-8";v=2`);

    response.setCharacterEncoding(null);

    assert(response.getCharacterEncoding() == "US-ASCII");
    assert(!response.isCharset());
    const remaining = `text/plain;profile="a;charset=b";v=2`;
    assert(response.getContentType() == remaining, response.getContentType());
    assert(response.getHeader("Content-Type") == remaining);
}

@("JSON suffixes use UTF-8 and preserve their explicitly supplied charset")
unittest
{
    auto response = new MockHttpServletResponse;
    const mediaType = "application/problem+json";
    response.setContentType(mediaType);
    assert(response.getCharacterEncoding() == "UTF-8");
    assert(!response.isCharset());
    assert(response.getHeader("Content-Type") == mediaType);

    response.setContentType(mediaType ~ ";charset=ISO-8859-1");
    assert(response.getCharacterEncoding() == "ISO-8859-1");
    assert(response.isCharset());
}

@("The charset fallback applies to an unparseable Content-Type")
unittest
{
    auto response = new MockHttpServletResponse;
    response.setContentType("test/plain; CHARSET=unsupported");
    assert(response.getCharacterEncoding() == "unsupported");
    assert(response.isCharset());
    assert(response.getHeader("Content-Type") == "test/plain; CHARSET=unsupported");

    response.setCharacterEncoding(null);
    assert(!response.isCharset());
    assert(response.getCharacterEncoding() == "ISO-8859-1");
    assert(response.getHeader("Content-Type") == "test/plain");
}

@("setContentTypeWithNullValueShouldRemoveHeader")
unittest
{
    auto response = new MockHttpServletResponse;
    response.addHeader("X-Before", "first");
    response.setContentType("application/json");
    response.addHeader("X-After", "last");

    response.setContentType(null);

    assert(!response.containsHeader("Content-Type"));
    assert(response.getContentType() is null);
    assert(response.getHeader("Content-Type") is null);
    assert(response.getHeaderNames() == ["X-Before", "X-After"]);
    assert(response.getHeader("X-Before") == "first");
    assert(response.getHeader("X-After") == "last");
}

@("setContentTypeHeaderWithNullValueShouldRemoveHeader")
unittest
{
    auto response = new MockHttpServletResponse;
    response.setContentType("application/json");

    response.setHeader("Content-Type", null);
    response.setHeader("Content-Type", null);

    assert(!response.containsHeader("Content-Type"));
    assert(response.getContentType() is null);
    assert(response.getHeader("Content-Type") is null);
}
