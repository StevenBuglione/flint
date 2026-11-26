/++
Ported from spring-projects/spring-framework v7.1.0,
spring-test/src/test/java/org/springframework/mock/web/MockHttpServletRequestTests.java.
Copyright 2002-present the original author or authors.
Licensed under the Apache License, Version 2.0 (https://www.apache.org/licenses/LICENSE-2.0).
Modified by the Flint authors: use D arrays and unittests.
+/
module mock_http_servlet_request_locale_tests;

import std.exception : assertThrown;

import flint.java.lang : IllegalArgumentException;
import flint.java.util : Locale;
import flint.mock.web : MockHttpServletRequest;

@safe:

@("setPreferredLocalesWithNullList")
unittest
{
    auto request = new MockHttpServletRequest;
    assertThrown!IllegalArgumentException(request.setPreferredLocales(null));
}

@("setPreferredLocalesWithEmptyList")
unittest
{
    auto request = new MockHttpServletRequest;
    auto storage = new Locale[1];
    assertThrown!IllegalArgumentException(request.setPreferredLocales(storage[0 .. 0]));
}

@("preferredLocalesFromAcceptLanguageHeader")
unittest
{
    enum header = "Accept-Language";
    enum value = "fr-ch, fr;q=0.9, en-*;q=0.8, de;q=0.7, *;q=0.5";
    auto request = new MockHttpServletRequest;
    request.addHeader(header, value);

    assert(request.getLocales() == [
        Locale.forLanguageTag("fr-ch"), Locale.forLanguageTag("fr"), Locale.ENGLISH, Locale.GERMAN,
    ]);
    assert(request.getHeader(header) == value);
}

@("emptyAcceptLanguageHeader")
unittest
{
    enum header = "Accept-Language";
    auto request = new MockHttpServletRequest;
    request.addHeader(header, "");

    assert(request.getLocale() == Locale.ENGLISH);
    assert(request.getHeader(header) !is null);
    assert(request.getHeader(header).length == 0);
}
