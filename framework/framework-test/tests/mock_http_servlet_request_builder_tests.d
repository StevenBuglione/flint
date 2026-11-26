/++
Ported from spring-projects/spring-framework v7.1.0,
spring-test/src/test/java/org/springframework/test/web/servlet/request/MockHttpServletRequestBuilderTests.java
and AbstractMockHttpServletRequestBuilderTests.java.
Copyright 2002-present the original author or authors.
Licensed under the Apache License, Version 2.0 (https://www.apache.org/licenses/LICENSE-2.0).
Modified by the Flint authors.
+/
module mock_http_servlet_request_builder_tests;

import flint.engine.aot.any : Any;
import flint.http : HttpHeaders, HttpMethod, MediaType;
import flint.jakarta.servlet.http : Cookie;
import flint.java.lang : IllegalArgumentException;
import flint.java.net : URI;
import flint.java.nio.charset : StandardCharsets;
import flint.java.util : ArrayList, Collection;
import flint.java.util.date : Date;
import flint.mock.web : MockHttpServletRequest, MockServletContext;
import flint.test.web.servlet.request : MockHttpServletRequestBuilder, MockMvcRequestBuilders;
import flint.util : LinkedMultiValueMap;

@safe:

private alias Builders = MockMvcRequestBuilders;

@("MockHttpServletRequestBuilderTests.acceptHeader")
unittest
{
    auto request = build(Builders.get("/").accept(MediaType.TEXT_HTML, MediaType.APPLICATION_XML));
    auto values = request.getHeaders(HttpHeaders.ACCEPT);
    assert(values.length == 1);
    auto types = MediaType.parseMediaTypes(values[0]);
    assert(types.length == 2);
    assert(types[0].toString() == "text/html");
    assert(types[1].toString() == "application/xml");
}

@("MockHttpServletRequestBuilderTests.acceptHeaderWithInvalidValues")
unittest
{
    assert(build(Builders.get("/").accept("any", "any2")).getHeader(HttpHeaders.ACCEPT) == "any, any2");
}

@("MockHttpServletRequestBuilderTests.contentType")
unittest
{
    auto request = build(Builders.get("/").contentType(MediaType.TEXT_HTML));
    assert(request.getContentType() == "text/html");
    assert(request.getHeaders(HttpHeaders.CONTENT_TYPE) == ["text/html"]);
}

@("MockHttpServletRequestBuilderTests.contentTypeViaString")
unittest
{
    auto request = build(Builders.get("/").contentType("text/html"));
    assert(request.getContentType() == "text/html");
    assert(request.getHeaders(HttpHeaders.CONTENT_TYPE) == ["text/html"]);
}

@("MockHttpServletRequestBuilderTests.contentTypeWithInvalidValue")
unittest
{
    assert(build(Builders.get("/").contentType("any")).getContentType() == "any");
}

@("MockHttpServletRequestBuilderTests.contentTypeViaHeader")
unittest
{
    assert(build(Builders.get("/").header(HttpHeaders.CONTENT_TYPE, "text/html")).getContentType() == "text/html");
}

@("MockHttpServletRequestBuilderTests.contentTypeViaHeaderWithInvalidValue")
unittest
{
    assert(build(Builders.get("/").header(HttpHeaders.CONTENT_TYPE, "yaml")).getContentType() == "yaml");
}

@("MockHttpServletRequestBuilderTests.contentTypeViaMultipleHeaderValues")
unittest
{
    auto request = build(Builders.get("/").header("content-type", "text/html", "text/plain"));
    assert(request.getContentType() == "text/plain");
    assert(request.getHeaders(HttpHeaders.CONTENT_TYPE) == ["text/plain"]);
}

@("MockHttpServletRequestBuilderTests.body")
unittest
{
    auto body = cast(const(ubyte)[]) "Hello World";
    auto request = build(Builders.get("/").content(body));
    assert(request.getInputStream().readAllBytes() == body);
    assert(request.getContentLength() == body.length);
}

@("MockHttpServletRequestBuilderTests.header")
unittest
{
    assert(build(Builders.get("/").header("foo", "bar", "baz")).getHeaders("foo") == ["bar", "baz"]);
}

@("MockHttpServletRequestBuilderTests.headers")
unittest
{
    auto headers = HttpHeaders.create();
    headers.setContentType(MediaType.APPLICATION_JSON);
    headers.put("foo", ["bar", "baz"]);
    auto request = build(Builders.get("/").headers(headers));
    assert(request.getHeaders("foo") == ["bar", "baz"]);
    assert(request.getHeader(HttpHeaders.CONTENT_TYPE) == MediaType.APPLICATION_JSON.toString());
}

@("MockHttpServletRequestBuilderTests.cookie")
unittest
{
    auto request = build(Builders.get("/").cookie(new Cookie("foo", "bar"), new Cookie("baz", "qux")));
    auto cookies = request.getCookies();
    assert(cookies.length == 2);
    assert(cookies[0].getName() == "foo");
    assert(cookies[0].getValue() == "bar");
    assert(cookies[1].getName() == "baz");
    assert(cookies[1].getValue() == "qux");
}

@("MockHttpServletRequestBuilderTests.noCookies")
unittest
{
    assert(build(Builders.get("/")).getCookies() is null);
}

@("MockHttpServletRequestBuilderTests.characterEncoding")
unittest
{
    auto builder = Builders.get("/").characterEncoding("UTF-8");
    assert(build(builder).getCharacterEncoding() == "UTF-8");
    builder.characterEncoding(StandardCharsets.ISO_8859_1);
    assert(build(builder).getCharacterEncoding() == StandardCharsets.ISO_8859_1.name());
}

@("MockHttpServletRequestBuilderTests.requestAttribute")
unittest
{
    assert(build(Builders.get("/").requestAttr("foo", Any.of("bar"))).getAttribute("foo").get!string() == "bar");
}

unittest
{
    auto builder = Builders.get("/").accept("text/plain").accept(MediaType.TEXT_HTML)
        .header("x-remove", "old").headers((HttpHeaders headers) {
        assert(headers.get(HttpHeaders.ACCEPT) == ["text/html"]);
        headers.remove("X-Remove");
        headers.set("X-Set", "new");
    });
    auto request = build(builder);
    assert(request.getHeader("x-remove") is null);
    assert(request.getHeader("X-Set") == "new");
    rejects(() { builder.accept(cast(string[]) null); }, "'mediaTypes' must not be empty");
    rejects(() { builder.contentType(cast(string) null); }, "'contentType' must not be null");
    rejects(() { builder.cookie(); }, "'cookies' must not be empty");
}

unittest
{
    auto request = build(Builders.post("/").characterEncoding("UTF-8").contentType("text/plain")
            .header("content-TYPE", "text/html;charset=ISO-8859-1").content("café"));
    assert(request.getContentType() == "text/html;charset=ISO-8859-1");
    assert(request.getCharacterEncoding() == "ISO-8859-1");
    assert(request.getInputStream().readAllBytes() == [0x63, 0x61, 0x66, 0xC3, 0xA9]);
    assert(request.getHeader(HttpHeaders.CONTENT_LENGTH) == "5");
    request = build(Builders.post("/").content("").header(HttpHeaders.TRANSFER_ENCODING, "chunked"));
    assert(request.getContentLength() == 0);
    assert(request.getHeader(HttpHeaders.CONTENT_LENGTH) is null);
    request = build(Builders.post("/").content("x").header(HttpHeaders.TRANSFER_ENCODING, "chunked"));
    assert(request.getHeader(HttpHeaders.CONTENT_LENGTH) is null);
    request = build(Builders.post("/").content("x").header("content-length", "2"));
    assert(request.getHeader(HttpHeaders.CONTENT_LENGTH) == "2");
}

unittest
{
    Collection!string tags = new ArrayList!string;
    tags.add("one");
    tags.add("two");
    auto request = build(Builders.get("/").header("X-Number", 42, true).header("X-Tags", tags)
            .header("X-Date", new Date(0)).acceptCharset(StandardCharsets.UTF_8, StandardCharsets.ISO_8859_1)
            .ifNoneMatch("\"one\"", "\"two\"").header("Cookie", "stale=value")
            .cookie(new Cookie("new", "cookie"), new Cookie("other", "")));
    assert(request.getHeaders("X-Number") == ["42", "true"]);
    assert(request.getHeaders("X-Tags") == ["one", "two"]);
    assert(request.getHeader("X-Date") == "Thu, 01 Jan 1970 00:00:00 GMT");
    assert(request.getHeader(HttpHeaders.ACCEPT_CHARSET) == "utf-8, iso-8859-1");
    assert(request.getHeader(HttpHeaders.IF_NONE_MATCH) == "\"one\",\"two\"");
    assert(request.getHeaders(HttpHeaders.COOKIE) == ["new=cookie; other="]);
}

private MockHttpServletRequest build(MockHttpServletRequestBuilder builder)
{
    return builder.buildRequest(new MockServletContext);
}

private void rejects(scope void delegate() @safe run, string message)
{
    try
    {
        run();
        assert(false);
    }
    catch (IllegalArgumentException failure)
        assert(failure.getMessage() == message, failure.getMessage());
}

@("MockHttpServletRequestBuilderTests.method")
unittest
{
    assert(build(Builders.get("/foo/bar")).getMethod() == "GET");
}

@("MockHttpServletRequestBuilderTests.uri")
unittest
{
    enum url = "https://java.sun.com:8080/javase/6/docs/api/java/util/BitSet.html?foo=bar#and(java.util.BitSet)";
    auto request = build(Builders.get(url));
    assert(request.getScheme() == "https");
    assert(request.getQueryString() == "foo=bar");
    assert(request.getServerName() == "java.sun.com");
    assert(request.getServerPort() == 8080);
    assert(request.getRequestURI() == "/javase/6/docs/api/java/util/BitSet.html");
    assert(request.getRequestURL() == "https://java.sun.com:8080/javase/6/docs/api/java/util/BitSet.html");
}

@("MockHttpServletRequestBuilderTests.requestUriWithEncoding")
unittest
{
    assert(build(Builders.get("/foo bar")).getRequestURI() == "/foo%20bar");
}

@("MockHttpServletRequestBuilderTests.requestUriWithDoubleSlashes")
unittest
{
    assert(build(Builders.get(URI.create("/test//currentlyValid/0"))).getRequestURI() == "/test//currentlyValid/0");
}

@("MockHttpServletRequestBuilderTests.requestUriWithoutScheme")
unittest
{
    rejects(() { Builders.get("localhost:8080/path"); },
            "'uri' should start with a path or be a complete HTTP URI: localhost:8080/path");
}

@("MockHttpServletRequestBuilderTests.contextPathEmpty")
unittest
{
    auto request = build(Builders.get("/foo"));
    assert(request.getContextPath() == "" && request.getServletPath() == "");
    assert(request.getPathInfo() == "/foo");
}

@("MockHttpServletRequestBuilderTests.contextPathServletPathEmpty")
unittest
{
    auto request = build(Builders.get("/travel/hotels/42").contextPath("/travel"));
    assert(request.getContextPath() == "/travel" && request.getServletPath() == "");
    assert(request.getPathInfo() == "/hotels/42");
}

@("MockHttpServletRequestBuilderTests.contextPathServletPath")
unittest
{
    auto request = build(Builders.get("/travel/main/hotels/42").contextPath("/travel").servletPath("/main"));
    assert(request.getContextPath() == "/travel" && request.getServletPath() == "/main");
    assert(request.getPathInfo() == "/hotels/42");
}

@("MockHttpServletRequestBuilderTests.contextPathServletPathInfoEmpty")
unittest
{
    auto request = build(Builders.get("/travel/hotels/42").contextPath("/travel").servletPath("/hotels/42"));
    assert(request.getContextPath() == "/travel" && request.getServletPath() == "/hotels/42");
    assert(request.getPathInfo() is null);
}

@("MockHttpServletRequestBuilderTests.contextPathServletPathInfo")
unittest
{
    auto request = build(Builders.get("/").servletPath("/index.html").pathInfo(null));
    assert(request.getContextPath() == "" && request.getServletPath() == "/index.html");
    assert(request.getPathInfo() is null);
}

@("MockHttpServletRequestBuilderTests.emptyPath")
unittest
{
    auto request = build(Builders.get(""));
    assert(request.getRequestURI() == "/" && request.getPathInfo() == "/");
    assert(request.getContextPath() == "" && request.getServletPath() == "");
}

@("MockHttpServletRequestBuilderTests.pathInfoIsDecoded")
unittest
{
    assert(build(Builders.get("/travel/hotels 42")).getPathInfo() == "/travel/hotels 42");
}

@("MockHttpServletRequestBuilderTests.contextPathServletPathInvalid")
unittest
{
    auto builder = Builders.get("/foo/bar");
    rejects(() { build(builder.contextPath("/Foo")); },
            "Request URI [/foo/bar] does not start with context path [/Foo]");
    rejects(() { builder.contextPath("foo"); }, "Context path must start with a '/'");
    rejects(() { builder.contextPath("/foo/"); }, "Context path must not end with a '/'");
    builder.contextPath("/foo");
    rejects(() { build(builder.servletPath("/Bar")); }, "Invalid servlet path [/Bar] for request URI [/foo/bar]");
    rejects(() { builder.servletPath("bar"); }, "Servlet path must start with a '/'");
    rejects(() { builder.servletPath("/bar/"); }, "Servlet path must not end with a '/'");
}

@("MockHttpServletRequestBuilderTests.requestUriAndFragment")
unittest
{
    assert(build(Builders.get("/foo#bar")).getRequestURI() == "/foo");
}

@("MockHttpServletRequestBuilderTests.requestParameter")
unittest
{
    assert(build(Builders.get("/foo/bar").param("foo", "bar", "baz")).getParameterValues("foo") == [
        "bar", "baz"
    ]);
}

@("MockHttpServletRequestBuilderTests.requestParameterFromQueryString")
unittest
{
    auto request = build(Builders.get("/?foo=bar&foo=baz"));
    assert(request.getParameterValues("foo") == ["bar", "baz"]);
    assert(request.getQueryString() == "foo=bar&foo=baz");
}

@("MockHttpServletRequestBuilderTests.requestParameterFromQueryStringWithListValues")
unittest
{
    auto request = build(Builders.get("/?foo[0]=bar&foo[1]=baz"));
    assert(request.getQueryString() == "foo%5B0%5D=bar&foo%5B1%5D=baz");
    assert(request.getParameter("foo[0]") == "bar" && request.getParameter("foo[1]") == "baz");
}

@("MockHttpServletRequestBuilderTests.queryParameter")
unittest
{
    auto request = build(Builders.get("/").queryParam("foo", "bar").queryParam("foo", "baz"));
    assert(request.getParameterValues("foo") == ["bar", "baz"]);
    assert(request.getQueryString() == "foo=bar&foo=baz");
}

@("MockHttpServletRequestBuilderTests.queryParameterMap")
unittest
{
    auto parameters = new LinkedMultiValueMap!(string, string);
    parameters.add("foo", "bar");
    parameters.add("foo", "baz");
    auto request = build(Builders.get("/").queryParams(parameters));
    assert(request.getParameterValues("foo") == ["bar", "baz"]);
    assert(request.getQueryString() == "foo=bar&foo=baz");
}

@("MockHttpServletRequestBuilderTests.requestParameterFromMultiValueMap")
unittest
{
    auto parameters = new LinkedMultiValueMap!(string, string);
    parameters.add("foo", "bar");
    parameters.add("foo", "baz");
    auto request = build(Builders.post("/foo").params(parameters));
    assert(request.getParameterValues("foo") == ["bar", "baz"]);
    assert(request.getQueryString() is null);
}

@("MockHttpServletRequestBuilderTests.queryParameterWithListValues")
unittest
{
    auto request = build(Builders.get("/").queryParam("foo[0]", "bar").queryParam("foo[1]", "baz"));
    assert(request.getQueryString() == "foo%5B0%5D=bar&foo%5B1%5D=baz");
    assert(request.getParameter("foo[0]") == "bar" && request.getParameter("foo[1]") == "baz");
}

@("MockHttpServletRequestBuilderTests.queryParameterAndQueryString")
unittest
{
    auto request = build(Builders.get("/path?param1=value1").queryParam("param1", "value2"));
    assert(request.getParameterValues("param1") == ["value1", "value2"]);
}

@("MockHttpServletRequestBuilderTests.queryParameterWithoutValues")
unittest
{
    auto request = build(Builders.get("/").queryParam("foo"));
    assert(request.getQueryString() == "foo");
    assert(request.getParameterNames() == ["foo"] && request.getParameterValues("foo").length == 0);
}

@("MockHttpServletRequestBuilderTests.queryStringWithoutValues")
unittest
{
    auto request = build(Builders.get("/path?foo"));
    assert(request.getQueryString() == "foo");
    auto values = request.getParameterValues("foo");
    assert(values.length == 1 && values[0] is null);
}

@("MockHttpServletRequestBuilderTests.requestParameterFromQueryWithEncoding")
unittest
{
    auto request = build(Builders.get("/?foo={value}", "bar=baz"));
    assert(request.getQueryString() == "foo=bar%3Dbaz" && request.getParameter("foo") == "bar=baz");
}

@("MockHttpServletRequestBuilderTests.requestParameterFromQueryNull")
unittest
{
    auto request = build(Builders.get("/?foo"));
    auto values = request.getParameterValues("foo");
    assert(values.length == 1 && values[0] is null);
    assert(request.getQueryString() == "foo");
}

@("MockHttpServletRequestBuilderTests.arbitraryMethod")
unittest
{
    auto request = build(Builders.request(HttpMethod.valueOf("REPort"), URI.create("/foo/42")));
    assert(request.getMethod() == "REPort");
    assert(request.getPathInfo() == "/foo/42");
}

@("MockMvc request factories preserve the method and encoded components")
unittest
{
    const uri = URI.create("/a%2Fb?name=Jane+Q%20Public&name=other#ignored");
    auto builders = [
        Builders.get(uri), Builders.post(uri), Builders.put(uri), Builders.patch(uri),
        Builders.delete_(uri), Builders.options(uri), Builders.head(uri),
        Builders.request(HttpMethod.GET, uri), Builders.request("TRACE", uri)
    ];
    auto methods = ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS", "HEAD", "GET", "TRACE"];
    foreach (index, builder; builders)
    {
        auto request = build(builder);
        assert(request.getMethod() == methods[index]);
        assert(request.getRequestURI() == "/a%2Fb" && request.getPathInfo() == "/a/b");
        assert(request.getParameterValues("name") == ["Jane+Q Public", "other"]);
    }

    enum templateValue = "/hotels/{id}";
    auto fromTemplates = [
        Builders.get(templateValue, 42), Builders.post(templateValue, 42),
        Builders.put(templateValue, 42), Builders.patch(templateValue, 42),
        Builders.delete_(templateValue, 42), Builders.options(templateValue, 42),
        Builders.head(templateValue, 42), Builders.request(HttpMethod.GET, templateValue, 42)
    ];
    foreach (index, builder; fromTemplates)
    {
        auto request = build(builder);
        assert(request.getMethod() == methods[index]);
        assert(request.getRequestURI() == "/hotels/42" && request.getUriTemplate().get() == templateValue);
    }
}

@("AbstractMockHttpServletRequestBuilderTests.pathInfoIsNotMutatedByBuildMethod")
unittest
{
    auto builder = Builders.get("/b");
    assert(build(builder).getPathInfo() == "/b");
    builder.uri("/a");
    assert(build(builder).getPathInfo() == "/a");
}

@("AbstractMockHttpServletRequestBuilderTests.uriTemplateSetsRequestsUrlAndTemplateConsistently")
unittest
{
    auto request = build(Builders.get("/hotels/{id}", 42));
    assert(request.getRequestURL() == "http://localhost/hotels/42");
    assert(request.getUriTemplate().get() == "/hotels/{id}");
}

@("AbstractMockHttpServletRequestBuilderTests.uriSetsRequestsUrlAndTemplateConsistently")
unittest
{
    auto builder = Builders.get("/hotels/{id}", 42).uri(URI.create("/hotels/25"));
    auto request = build(builder);
    assert(request.getRequestURL() == "http://localhost/hotels/25");
    assert(request.getUriTemplate().isNull);
}

@("MockMvc preserves existing URI escapes and encodes query template separators")
unittest
{
    auto request = build(Builders.get("/a%2Fb?name=Jane+Q%20Public&filter={value}#ignored", "a=b&x=1"));
    assert(request.getRequestURI() == "/a%2Fb");
    assert(request.getPathInfo() == "/a/b");
    assert(request.getQueryString() == "name=Jane+Q%20Public&filter=a%3Db%26x%3D1");
    assert(request.getParameter("name") == "Jane+Q Public");
    assert(request.getParameter("filter") == "a=b&x=1");
}
