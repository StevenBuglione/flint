/++
Ported from spring-projects/spring-framework v7.1.0,
spring-web/src/test/java/org/springframework/http/server/ServletServerHttpRequestTests.java.
Copyright 2002-present the original author or authors.
Licensed under the Apache License, Version 2.0 (https://www.apache.org/licenses/LICENSE-2.0).
Modified by the Flint authors. The mock uses explicit HTTPS port 443 and
suppresses an absent Content-Type field through a servlet request wrapper.
+/
module flint.http.servlet_server_http_request_tests;

import flint.http : HttpHeaders, HttpMethod, MediaType;
import flint.http.server : ServletServerHttpRequest;
import flint.jakarta.servlet.http : HttpServletRequestWrapper;
import flint.java.nio.charset : StandardCharsets;
import flint.mock.web : MockHttpServletRequest;

@safe:

@("ServletServerHttpRequestTests.getMethod")
unittest
{
    auto mock = new MockHttpServletRequest;
    mock.setMethod("POST");

    assert((new ServletServerHttpRequest(mock)).getMethod() == HttpMethod.POST);
}

@("ServletServerHttpRequestTests.getUriForSimplePath")
unittest
{
    assert(requestURI("/path", null) == "https://example.com/path");
}

@("ServletServerHttpRequestTests.getUriWithQueryString")
unittest
{
    assert(requestURI("/path", "query") == "https://example.com/path?query");
}

@("ServletServerHttpRequestTests.getUriWithEncoding")
unittest
{
    enum query = "redirect=https%3A%2F%2Fgithub.com%2Fspring-projects%2Fspring-framework";
    assert(requestURI("/%E4%B8%AD%E6%96%87", query) == "https://example.com/%E4%B8%AD%E6%96%87?" ~ query);
}

private string requestURI(string path, string query)
{
    auto mock = new MockHttpServletRequest;
    mock.setScheme("https");
    mock.setServerName("example.com");
    mock.setServerPort(443);
    mock.setRequestURI(path);
    mock.setQueryString(query);
    return (new ServletServerHttpRequest(mock)).getURI().toString();
}

@("ServletServerHttpRequestTests.getHeaders")
unittest
{
    auto mock = new MockHttpServletRequest;
    mock.addHeader("MyHeader", "value1");
    mock.addHeader("MyHeader", "value2");
    mock.setContentType("text/plain");
    mock.setCharacterEncoding("UTF-8");

    auto headers = (new ServletServerHttpRequest(mock)).getHeaders();
    assert(headers.get("MyHeader") == ["value1", "value2"]);
    assert(*headers.getContentType() == MediaType("text", "plain", StandardCharsets.UTF_8));
}

@("ServletServerHttpRequestTests.getHeadersWithEmptyContentTypeAndEncoding")
unittest
{
    auto mock = new MockHttpServletRequest;
    mock.addHeader("MyHeader", "value1");
    mock.addHeader("MyHeader", "value2");
    mock.setContentType("");
    mock.setCharacterEncoding("");

    auto headers = (new ServletServerHttpRequest(mock)).getHeaders();
    assert(headers.get("MyHeader") == ["value1", "value2"]);
    assert(headers.getContentType() is null);
}

@("ServletServerHttpRequestTests.getHeadersWithWildcardContentType")
unittest
{
    auto mock = new MockHttpServletRequest;
    mock.setContentType("*/*");

    auto request = new ServletServerHttpRequest(new MissingContentTypeHeaderRequest(mock));
    assert(request.getHeaders().isEmpty());
}

private class MissingContentTypeHeaderRequest : HttpServletRequestWrapper
{
    this(MockHttpServletRequest request)
    {
        super(request);
    }

    override string[] getHeaderNames()
    {
        return null;
    }

    override string getHeader(string name)
    {
        assert(name == HttpHeaders.CONTENT_TYPE);
        return null;
    }

    override string[] getHeaders(string name)
    {
        assert(name == HttpHeaders.CONTENT_TYPE);
        return null;
    }
}

@("ServletServerHttpRequestTests.getHeadersWithCharacterEncoding")
unittest
{
    auto mock = new MockHttpServletRequest;
    mock.setContentType("application/x-www-form-urlencoded");

    auto request = new ServletServerHttpRequest(new Latin1Request(mock));
    assert(*request.getHeaders().getContentType() == MediaType(MediaType.APPLICATION_FORM_URLENCODED,
            StandardCharsets.ISO_8859_1));
}

private class Latin1Request : HttpServletRequestWrapper
{
    this(MockHttpServletRequest request)
    {
        super(request);
    }

    override string getCharacterEncoding()
    {
        return "ISO-8859-1";
    }
}

@("ServletServerHttpRequestTests.getBody")
unittest
{
    auto mock = new MockHttpServletRequest;
    auto body = cast(const(ubyte)[]) "Hello World";
    mock.setContent(body);

    auto request = new ServletServerHttpRequest(mock);
    assert(request.getBody() == body);
}

@("ServletServerHttpRequest preserves declared charset and unsupported encodings")
unittest
{
    auto mock = new MockHttpServletRequest;
    mock.setContentType("text/plain;charset=UTF-8");
    mock.setCharacterEncoding("ISO-8859-1");
    assert((new ServletServerHttpRequest(mock)).getHeaders()
            .getFirst(HttpHeaders.CONTENT_TYPE) == "text/plain;charset=UTF-8");

    mock.setContentType("text/plain");
    mock.setCharacterEncoding("UNKNOWN-ENCODING");
    assert((new ServletServerHttpRequest(mock)).getHeaders().getFirst(HttpHeaders.CONTENT_TYPE) == "text/plain");

    mock.setContentType("invalid/type/extra");
    mock.setCharacterEncoding("UTF-8");
    auto headers = (new ServletServerHttpRequest(mock)).getHeaders();
    assert(headers.getFirst(HttpHeaders.CONTENT_TYPE) == "invalid/type/extra");
}

@("ServletServerHttpRequestTests.getFormBody")
unittest
{
    auto mock = formRequest();
    mock.addParameter("name 1", "value 1");
    mock.addParameter("name 2", "value 2+1", "value 2+2");
    mock.addParameter("name 3", cast(string) null);
    mock.addParameter("empty", "");

    auto request = new ServletServerHttpRequest(mock);
    enum expected = "name+1=value+1&name+2=value+2%2B1&name+2=value+2%2B2&name+3&empty=";
    assert(request.getBody() == cast(const(ubyte)[]) expected);
    assert(!request.getHeaders().containsHeader(HttpHeaders.CONTENT_LENGTH));
}

@("ServletServerHttpRequestTests.getEmptyFormBody")
unittest
{
    auto request = new ServletServerHttpRequest(formRequest());

    assert(request.getBody().length == 0);
    assert(!request.getHeaders().containsHeader(HttpHeaders.CONTENT_LENGTH));
}

@("ServletServerHttpRequestTests.getFormBodyWhenQueryParamsAlsoPresent")
unittest
{
    auto mock = formRequest();
    mock.setQueryString("q=1");
    mock.addParameter("q", "1");
    mock.setContent(cast(const(ubyte)[]) "foo=bar");
    mock.addHeader(HttpHeaders.CONTENT_LENGTH, "7");

    auto request = new ServletServerHttpRequest(mock);
    assert(request.getBody() == cast(const(ubyte)[]) "foo=bar");
    assert(request.getHeaders().getContentLength() == 7);

    mock.setQueryString("?"[0 .. 0]);
    assert((new ServletServerHttpRequest(mock)).getBody() == cast(const(ubyte)[]) "foo=bar");
}

@("ServletServerHttpRequestTests.getFormBodyWhenNotEncodedCharactersPresent")
unittest
{
    auto mock = formRequest();
    mock.addParameter("name", "Test");
    mock.addParameter("lastName", "Test@er");
    mock.addHeader(HttpHeaders.CONTENT_LENGTH, "26");

    auto request = new ServletServerHttpRequest(mock);
    auto headers = request.getHeaders();
    auto body = request.getBody();
    assert(body == cast(const(ubyte)[]) "name=Test&lastName=Test%40er");
    assert(headers.getContentLength() == body.length);
}

@("ServletServerHttpRequest encodes default UTF-8 form values")
unittest
{
    auto mock = formRequest("application/x-www-form-urlencoded");
    mock.addParameter("café", "é*~+");

    assert((new ServletServerHttpRequest(mock)).getBody() == cast(const(ubyte)[]) "caf%C3%A9=%C3%A9*%7E%2B");
}

@("ServletServerHttpRequest preserves the raw body for an unsupported form encoding")
unittest
{
    auto mock = formRequest("application/x-www-form-urlencoded; charset=windows-1251");
    mock.addParameter("x", "а");
    mock.setContent(cast(const(ubyte)[]) "x=%e0");

    assert((new ServletServerHttpRequest(mock)).getBody() == cast(const(ubyte)[]) "x=%e0");
}

@("ServletServerHttpRequest uses a staged form charset")
unittest
{
    auto mock = formRequest("application/x-www-form-urlencoded; charset=ISO-8859-1");
    mock.addParameter("x", "é");
    auto request = new ServletServerHttpRequest(mock);
    request.getHeaders().setContentType(MediaType(MediaType.APPLICATION_FORM_URLENCODED, StandardCharsets.UTF_8));

    assert(request.getBody() == cast(const(ubyte)[]) "x=%C3%A9");
}

private MockHttpServletRequest formRequest(string contentType = "application/x-www-form-urlencoded; charset=UTF-8")
{
    auto mock = new MockHttpServletRequest;
    mock.setMethod("POST");
    mock.setContentType(contentType);
    return mock;
}
