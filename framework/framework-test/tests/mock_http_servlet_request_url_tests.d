/++
Ported from spring-projects/spring-framework v7.1.0,
spring-test/src/test/java/org/springframework/mock/web/MockHttpServletRequestTests.java.
Copyright 2002-present the original author or authors.
Licensed under the Apache License, Version 2.0 (https://www.apache.org/licenses/LICENSE-2.0).
Modified by the Flint authors: check the request URL directly as a D string.
+/
module mock_http_servlet_request_url_tests;

import flint.mock.web : MockHttpServletRequest;

@safe:

@("getServerNameWithDefaultName")
unittest
{
    auto request = new MockHttpServletRequest;
    assert(request.getServerName() == "localhost");
}

@("getServerNameWithCustomName")
unittest
{
    auto request = new MockHttpServletRequest;
    request.setServerName("example.com");
    assert(request.getServerName() == "example.com");
}

@("getServerPortWithDefaultPort")
unittest
{
    auto request = new MockHttpServletRequest;
    assert(request.getServerPort() == 80);
}

@("getServerPortWithCustomPort")
unittest
{
    auto request = new MockHttpServletRequest;
    request.setServerPort(8080);
    assert(request.getServerPort() == 8080);
}

@("getRequestURL")
unittest
{
    auto request = new MockHttpServletRequest;
    request.setServerPort(8080);
    request.setRequestURI("/path");
    assert(request.getRequestURL() == "http://localhost:8080/path");

    request.setScheme("https");
    request.setServerName("example.com");
    request.setServerPort(8443);
    assert(request.getRequestURL() == "https://example.com:8443/path");
}

@("getRequestURLWithDefaults")
unittest
{
    auto request = new MockHttpServletRequest;
    assert(request.getRequestURL() == "http://localhost");
}

@("getRequestURLWithIpv6AddressViaServerNameWithoutPort")
unittest
{
    auto request = new MockHttpServletRequest;
    request.setServerName("[::ffff:abcd:abcd]");
    assert(request.getRequestURL() == "http://[::ffff:abcd:abcd]");
}

@("getRequestURLWithIpv6AddressViaServerNameWithPort")
unittest
{
    auto request = new MockHttpServletRequest;
    request.setServerName("[::ffff:abcd:abcd]");
    request.setServerPort(9999);
    assert(request.getRequestURL() == "http://[::ffff:abcd:abcd]:9999");
}

@("getRequestURLWithNullRequestUri")
unittest
{
    auto request = new MockHttpServletRequest;
    request.setRequestURI(null);
    assert(request.getRequestURL() == "http://localhost");
}

@("getRequestURLWithDefaultsAndHttps")
unittest
{
    auto request = new MockHttpServletRequest;
    request.setScheme("https");
    request.setServerPort(443);
    assert(request.getRequestURL() == "https://localhost");
}
