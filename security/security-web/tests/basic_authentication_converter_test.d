// Ported from spring-security 7.2.0: web/src/test/java/org/springframework/security/web/authentication/www/BasicAuthenticationConverterTests.java
/*
 * Copyright 2004-present the original author or authors.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      https://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
// Modified by the Flint authors.

module flint.security.web.basic_authentication_converter_test;

import flint.mock.web : MockHttpServletRequest;
import flint.security.authentication : BadCredentialsException, UsernamePasswordAuthenticationToken;
import flint.security.web.authentication : AuthenticationConverter;
import flint.security.web.authentication.www : BasicAuthenticationConverter;
import std.exception : collectException;

@safe:

private MockHttpServletRequest requestWith(string authorization)
{
    auto request = new MockHttpServletRequest("GET", "/");
    request.addHeader("Authorization", authorization);
    return request;
}

@("BasicAuthenticationConverter implements AuthenticationConverter with a covariant token")
unittest
{
    auto basic = new BasicAuthenticationConverter;
    AuthenticationConverter converter = basic;
    foreach (scheme; [BasicAuthenticationConverter.AUTHENTICATION_SCHEME_BASIC, "BaSiC"])
    {
        auto authentication = converter.convert(requestWith(scheme ~ " cm9kOmtvYWxh"));
        auto token = cast(UsernamePasswordAuthenticationToken) authentication;
        assert(token !is null && !token.isAuthenticated());
        assert(token.getName() == "rod" && token.getCredentials().get!string == "koala");
    }

    auto token = basic.convert(requestWith("Basic cm9kOg=="));
    assert(token !is null && token.getName() == "rod");
    assert(token.getCredentials().get!string == "");
    assert(converter.convert(new MockHttpServletRequest("GET", "/")) is null);
    assert(converter.convert(requestWith("Bearer someOtherToken")) is null);
}

@("BasicAuthenticationConverterTests.testWhenInvalidBasicAuthorizationTokenThenError")
unittest
{
    auto converter = new BasicAuthenticationConverter;
    auto request = requestWith("Basic Tk9UX0FfVkFMSURfVE9LRU5fQVNfTUlTU0lOR19DT0xPTg==");
    assert(collectException!BadCredentialsException(converter.convert(request)) !is null);
}

@("BasicAuthenticationConverterTests.testWhenInvalidBase64ThenError")
unittest
{
    auto converter = new BasicAuthenticationConverter;
    auto request = requestWith("Basic NOT_VALID_BASE64");
    assert(collectException!BadCredentialsException(converter.convert(request)) !is null);
}

@("BasicAuthenticationConverterTests.requestWhenEmptyBasicAuthorizationHeaderTokenThenError")
unittest
{
    auto converter = new BasicAuthenticationConverter;
    auto request = requestWith("Basic ");
    assert(collectException!BadCredentialsException(converter.convert(request)) !is null);
}
