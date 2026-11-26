/++
Ported from spring-projects/spring-framework v7.1.0,
spring-web/src/test/java/org/springframework/http/server/ServletServerHttpResponseTests.java.
Copyright 2002-present the original author or authors.
Licensed under the Apache License, Version 2.0 (https://www.apache.org/licenses/LICENSE-2.0).
Modified by the Flint authors. Body writes use the HttpOutputMessage writeBody adaptation.
+/
module flint.http.servlet_server_http_response_tests;

import flint.http : HttpHeaders, HttpStatus, MediaType;
import flint.http.server : ServletServerHttpResponse;
import flint.java.nio.charset : StandardCharsets;
import flint.mock.web : MockHttpServletResponse;

@safe:

@("ServletServerHttpResponseTests.setStatusCode")
unittest
{
    auto mock = new MockHttpServletResponse;
    auto response = new ServletServerHttpResponse(mock);
    response.setStatusCode(HttpStatus.NOT_FOUND);

    assert(mock.getStatus() == 404);
}

@("ServletServerHttpResponseTests.getHeaders")
unittest
{
    auto mock = new MockHttpServletResponse;
    auto response = new ServletServerHttpResponse(mock);
    auto headers = response.getHeaders();
    headers.add("MyHeader", "value1");
    headers.add("MyHeader", "value2");
    headers.setContentType(MediaType("text", "plain", StandardCharsets.UTF_8));

    response.close();

    assert(mock.containsHeader("MyHeader"));
    assert(mock.getHeaders("MyHeader") == ["value1", "value2"]);
    assert(mock.getHeader(HttpHeaders.CONTENT_TYPE) == "text/plain;charset=UTF-8");
    assert(mock.getContentType() == "text/plain;charset=UTF-8");
    assert(mock.getCharacterEncoding() == "UTF-8");
}

@("ServletServerHttpResponseTests.getHeadersWithNoContentType")
unittest
{
    auto response = new ServletServerHttpResponse(new MockHttpServletResponse);
    assert(response.getHeaders().get(HttpHeaders.CONTENT_TYPE) is null);
}

@("ServletServerHttpResponseTests.preExistingContentTypeIsOverriddenImmediately")
unittest
{
    auto mock = new MockHttpServletResponse;
    mock.setContentType("text/csv");
    auto response = new ServletServerHttpResponse(mock);
    response.getHeaders().setContentType(MediaType.APPLICATION_JSON);

    assert(*response.getHeaders().getContentType() == MediaType.APPLICATION_JSON);
}

@("ServletServerHttpResponseTests.getBody")
unittest
{
    auto mock = new MockHttpServletResponse;
    auto response = new ServletServerHttpResponse(mock);
    auto content = cast(const(ubyte)[]) "Hello World";
    response.writeBody(content);

    assert(mock.getContentAsByteArray() == content);
}

@("ServletServerHttpResponse.flush commits after a body write")
unittest
{
    auto mock = new MockHttpServletResponse;
    auto response = new ServletServerHttpResponse(mock);
    response.getHeaders().set("X-Staged", "yes");

    response.flush();
    assert(mock.getHeader("X-Staged") == "yes");
    assert(!mock.isCommitted());

    response.writeBody(cast(const(ubyte)[]) "buffered");
    assert(!mock.isCommitted());

    response.flush();
    assert(mock.isCommitted());
}
