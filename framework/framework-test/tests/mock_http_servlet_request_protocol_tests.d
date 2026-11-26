/++
Ported from spring-projects/spring-framework v7.1.0,
spring-test/src/test/java/org/springframework/mock/web/MockHttpServletRequestTests.java.
Copyright 2002-present the original author or authors.
Licensed under the Apache License, Version 2.0 (https://www.apache.org/licenses/LICENSE-2.0).
Modified by the Flint authors: JUnit cases become D unittests.
+/
module mock_http_servlet_request_protocol_tests;

import flint.mock.web : MockHttpServletRequest;

@safe:

@("protocolAndScheme")
unittest
{
    auto request = new MockHttpServletRequest;
    assert(MockHttpServletRequest.DEFAULT_PROTOCOL == "HTTP/1.1");
    assert(MockHttpServletRequest.DEFAULT_SCHEME == "http");
    assert(request.getProtocol() == MockHttpServletRequest.DEFAULT_PROTOCOL);
    assert(request.getScheme() == MockHttpServletRequest.DEFAULT_SCHEME);

    request.setProtocol("HTTP/2.0");
    request.setScheme("https");
    assert(request.getProtocol() == "HTTP/2.0");
    assert(request.getScheme() == "https");
}

@("isSecureWithHttpSchemeAndSecureFlagIsFalse")
unittest
{
    auto request = new MockHttpServletRequest;
    assert(!request.isSecure());
    request.setScheme("http");
    request.setSecure(false);
    assert(!request.isSecure());
}

@("isSecureWithHttpSchemeAndSecureFlagIsTrue")
unittest
{
    auto request = new MockHttpServletRequest;
    assert(!request.isSecure());
    request.setScheme("http");
    request.setSecure(true);
    assert(request.isSecure());
}

@("isSecureWithHttpsSchemeAndSecureFlagIsFalse")
unittest
{
    auto request = new MockHttpServletRequest;
    assert(!request.isSecure());
    request.setScheme("https");
    request.setSecure(false);
    assert(request.isSecure());
}

@("isSecureWithHttpsSchemeAndSecureFlagIsTrue")
unittest
{
    auto request = new MockHttpServletRequest;
    assert(!request.isSecure());
    request.setScheme("https");
    request.setSecure(true);
    assert(request.isSecure());
}

@("HTTPS uses case-insensitive scheme matching after the secure flag is cleared")
unittest
{
    auto request = new MockHttpServletRequest;
    request.setSecure(true);
    request.setScheme("hTtPs");
    request.setSecure(false);
    assert(request.isSecure());

    request.setScheme("http");
    assert(!request.isSecure());
}
