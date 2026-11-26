/++
Ported from spring-projects/spring-framework v7.1.0,
spring-test/src/test/java/org/springframework/mock/web/MockHttpServletResponseTests.java.
Copyright 2002-present the original author or authors.
Licensed under the Apache License, Version 2.0 (https://www.apache.org/licenses/LICENSE-2.0).
Modified by the Flint authors: use D strings and unittests.
+/
module mock_http_servlet_response_header_tests;

import flint.java.util : Locale;
import flint.mock.web : MockHttpServletResponse;
import std.typecons : Nullable;

@safe:

private immutable string[5] headerNames = [
    "Content-Type", "Content-Length", "Content-Language", "Set-Cookie", "X-Test"
];

@("addHeaderWithNullValueShouldHaveNoEffect")
unittest
{
    foreach (name; headerNames)
    {
        auto response = new MockHttpServletResponse;
        response.addHeader(name, null);
        assert(!response.containsHeader(name), name);
    }
}

@("addHeaderWithNullNameShouldHaveNoEffect")
unittest
{
    auto response = new MockHttpServletResponse;
    response.addHeader(null, "test");
    assert(response.getHeaderNames().length == 0);
}

@("setHeaderWithNullValueShouldHaveNoEffect")
unittest
{
    foreach (name; headerNames)
    {
        auto response = new MockHttpServletResponse;
        response.setHeader(name, null);
        assert(!response.containsHeader(name), name);
    }
}

@("setHeaderWithNullValueShouldRemoveHeader")
unittest
{
    foreach (name; ["Content-Language", "X-Test-Header"])
    {
        auto response = new MockHttpServletResponse;
        response.addHeader("First", "1");
        response.addHeader(name, "en");
        response.addHeader("Last", "2");
        response.setHeader(name, null);
        assert(!response.containsHeader(name), name);
        assert(response.getHeaderNames() == ["First", "Last"]);
    }
}

@("contentLanguageHeaderWithSingleValue")
unittest
{
    auto response = new MockHttpServletResponse;
    response.setHeader("Content-Language", "it");
    assert(response.getHeader("Content-Language") == "it");
    assert(response.getLocale() == Locale.ITALIAN);
}

@("contentLanguageHeaderWithMultipleValues")
unittest
{
    auto response = new MockHttpServletResponse;
    response.setHeader("Content-Language", "it, en");
    assert(response.getHeader("Content-Language") == "it, en");
    assert(response.getLocale() == Locale.ITALIAN);

    response.setHeader("Content-Language", `"de-DE", en`);
    assert(response.getLocale() == Locale.GERMANY);
}

@("shouldAddMultipleContentLanguage")
unittest
{
    auto response = new MockHttpServletResponse;
    response.addHeader("Content-Language", "en");
    response.addHeader("content-language", "fr");
    assert(response.getHeaders("Content-Language") == ["en", "fr"]);
    assert(response.getLocale() == Locale.ENGLISH);

    response.setHeader("content-language", "fr, it");
    assert(response.getLocale() == Locale.FRENCH);
    assert(response.getHeaders("Content-Language") == ["fr, it"]);
}

@("contentLengthSetsHeader")
unittest
{
    auto response = new MockHttpServletResponse;
    response.setContentLength(66);
    assert(response.getContentLength() == 66);
    assert(response.getHeader("Content-Length") == "66");
}

@("contentLengthHeaderSetsLength")
unittest
{
    auto response = new MockHttpServletResponse;
    response.addHeader("Content-Length", "66");
    assert(response.getContentLength() == 66);
    assert(response.getHeader("Content-Length") == "66");
}

@("contentLengthIntHeader")
unittest
{
    auto response = new MockHttpServletResponse;
    response.addIntHeader("Content-Length", 66);
    assert(response.getContentLength() == 66);
    assert(response.getHeader("Content-Length") == "66");
    response.setIntHeader("content-length", 67);
    assert(response.getContentLengthLong() == 67);
    assert(response.getHeaders("Content-Length") == ["67"]);
}

@("httpHeaderNameCasingIsPreserved")
unittest
{
    auto response = new MockHttpServletResponse;
    response.addHeader("Header1", "value1");
    assert(response.getHeaderNames() == ["Header1"]);
}

@("setLocaleWithNullValue")
unittest
{
    auto response = new MockHttpServletResponse;
    assert(response.getLocale() == Locale.getDefault());
    response.setLocale(Nullable!Locale.init);
    assert(response.getLocale() == Locale.getDefault());
    response.setLocale(Locale.ROOT);
    response.setLocale(Nullable!Locale.init);
    assert(response.getLocale() == Locale.ROOT);
    assert(response.getHeader("Content-Language") == "und");
}

@("A committed response retains its Content-Length")
unittest
{
    auto response = new MockHttpServletResponse;
    response.setContentLengthLong(3_000_000_000);
    response.flushBuffer();
    response.setContentLength(100);
    response.setIntHeader("Content-Length", 101);
    assert(response.getContentLengthLong() == 3_000_000_000);
    assert(response.getHeader("Content-Length") == "3000000000");
}
