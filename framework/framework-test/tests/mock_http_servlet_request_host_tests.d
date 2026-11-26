/++
Ported from spring-projects/spring-framework v7.1.0,
spring-test/src/test/java/org/springframework/mock/web/MockHttpServletRequestTests.java.
Copyright 2002-present the original author or authors.
Licensed under the Apache License, Version 2.0 (https://www.apache.org/licenses/LICENSE-2.0).
Modified by the Flint authors: JUnit cases become D unittests.
+/
module mock_http_servlet_request_host_tests;

import std.algorithm.searching : canFind;
import std.exception : collectException;

import flint.java.lang : IllegalStateException, NumberFormatException;
import flint.mock.web : MockHttpServletRequest;

@safe:

private enum hostHeader = "Host";

@("getServerNameViaHostHeaderWithoutPort")
unittest
{
    auto request = new MockHttpServletRequest;
    request.addHeader(hostHeader, "test.server");
    assert(request.getServerName() == "test.server");
}

@("getServerNameViaHostHeaderWithPort")
unittest
{
    auto request = new MockHttpServletRequest;
    request.addHeader(hostHeader, "test.server:8080");
    assert(request.getServerName() == "test.server");
}

@("getServerNameWithInvalidIpv6AddressViaHostHeader")
unittest
{
    auto request = new MockHttpServletRequest;
    enum invalid = "[::ffff:abcd:abcd";
    request.addHeader(hostHeader, invalid);
    const error = collectException!IllegalStateException(request.getServerName());
    assert(error !is null && error.msg == "Invalid Host header: " ~ invalid);
}

@("getServerNameViaHostHeaderAsIpv6AddressWithoutPort")
unittest
{
    auto request = new MockHttpServletRequest;
    request.addHeader(hostHeader, "[2001:db8:0:1]");
    assert(request.getServerName() == "[2001:db8:0:1]");
}

@("getServerNameViaHostHeaderAsIpv6AddressWithPort")
unittest
{
    auto request = new MockHttpServletRequest;
    request.addHeader(hostHeader, "[2001:db8:0:1]:8081");
    assert(request.getServerName() == "[2001:db8:0:1]");
}

@("getServerPortWithInvalidIpv6AddressViaHostHeader")
unittest
{
    auto request = new MockHttpServletRequest;
    enum invalid = "[::ffff:abcd:abcd:8080";
    request.addHeader(hostHeader, invalid);
    const error = collectException!IllegalStateException(request.getServerPort());
    assert(error !is null && error.msg == "Invalid Host header: " ~ invalid);
}

@("getServerPortWithIpv6AddressAndInvalidPortViaHostHeader")
unittest
{
    auto request = new MockHttpServletRequest;
    request.addHeader(hostHeader, "[::ffff:abcd:abcd]:bogus");
    const error = collectException!NumberFormatException(request.getServerPort());
    assert(error !is null && error.msg.canFind("bogus"));
}

@("getServerPortViaHostHeaderAsIpv6AddressWithoutPort")
unittest
{
    auto request = new MockHttpServletRequest;
    request.addHeader(hostHeader, "[2001:db8:0:1]");
    assert(request.getServerPort() == 80);
}

@("getServerPortViaHostHeaderAsIpv6AddressWithPort")
unittest
{
    auto request = new MockHttpServletRequest;
    request.addHeader(hostHeader, "[2001:db8:0:1]:9999");
    assert(request.getServerPort() == 9999);
}

@("getServerPortViaHostHeaderWithoutPort")
unittest
{
    auto request = new MockHttpServletRequest;
    request.addHeader(hostHeader, "test.server");
    assert(request.getServerPort() == 80);
}

@("getServerPortViaHostHeaderWithPort")
unittest
{
    auto request = new MockHttpServletRequest;
    request.addHeader(hostHeader, "test.server:9999");
    assert(request.getServerPort() == 9999);
}

@("The first Host header takes precedence and uses Java trim")
unittest
{
    auto request = new MockHttpServletRequest;
    request.setServerName("configured");
    request.setServerPort(8080);
    request.addHeader("host", "\r\t [2001:db8:0:1]:+9999 \n");
    request.addHeader(hostHeader, "ignored:1000");

    assert(request.getServerName() == "[2001:db8:0:1]");
    assert(request.getServerPort() == 9999);
}

@("An empty Host name is distinct from an absent Host header")
unittest
{
    auto request = new MockHttpServletRequest;
    request.setServerPort(8080);
    request.addHeader(hostHeader, " \t ");

    const name = request.getServerName();
    assert(name !is null && name.length == 0);
    assert(request.getServerPort() == 8080);
}
