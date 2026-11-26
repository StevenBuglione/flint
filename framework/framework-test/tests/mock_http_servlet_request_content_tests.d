/++
Ported from spring-projects/spring-framework v7.1.0,
spring-test/src/test/java/org/springframework/mock/web/MockHttpServletRequestTests.java.
Copyright 2002-present the original author or authors.
Licensed under the Apache License, Version 2.0 (https://www.apache.org/licenses/LICENSE-2.0).
Modified by the Flint authors: use D byte slices and unittests.
+/
module mock_http_servlet_request_content_tests;

import flint.mock.web : MockHttpServletRequest;

@safe:

@("setContentAndGetInputStream")
unittest
{
    const bytes = cast(const(ubyte)[]) "body";
    auto request = new MockHttpServletRequest;

    request.setContent(bytes);
    assert(request.getContentLength() == bytes.length);
    assert(request.getInputStream().readAllBytes() == bytes);

    request.setContent(bytes);
    assert(request.getContentLength() == bytes.length);
    assert(request.getInputStream().readAllBytes() == bytes);
}

@("readEmptyInputStreamWorksAcrossRequests")
unittest
{
    auto firstRequest = new MockHttpServletRequest;
    auto firstStream = firstRequest.getInputStream();
    assert(firstStream.readAllBytes().length == 0);
    firstStream.close();

    auto secondRequest = new MockHttpServletRequest;
    auto secondStream = secondRequest.getInputStream();
    assert(secondStream.readAllBytes().length == 0);
    secondStream.close();
}

@("setContentAndGetContentAsByteArray")
unittest
{
    const bytes = cast(const(ubyte)[]) "request body";
    auto request = new MockHttpServletRequest;
    request.setContent(bytes);

    assert(request.getContentLength() == bytes.length);
    assert(request.getContentLengthLong() == bytes.length);
    assert(request.getContentAsByteArray() == bytes);
}

@("noContent")
unittest
{
    auto request = new MockHttpServletRequest;
    assert(request.getContentLength() == -1);
    assert(request.getContentLengthLong() == -1);
    assert(request.getInputStream().read() == -1);
    assert(request.getContentAsByteArray() is null);
}
