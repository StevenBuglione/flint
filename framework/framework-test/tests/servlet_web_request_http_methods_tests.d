/++
Ported from spring-projects/spring-framework v7.1.0,
spring-web/src/test/java/org/springframework/web/context/request/ServletWebRequestHttpMethodsTests.java.
Copyright 2002-present the original author or authors.
Licensed under the Apache License, Version 2.0 (https://www.apache.org/licenses/LICENSE-2.0).
Modified by the Flint authors: parameterized methods run for GET and HEAD with a fixed test clock.
+/
module flint.test.web.servlet_web_request_http_methods_tests;

import flint.http : HttpHeaders;
import flint.java.lang : IllegalArgumentException;
import flint.mock.web : MockHttpServletRequest, MockHttpServletResponse;
import flint.web.context.request : ServletWebRequest;
import std.typecons : nullable;

@safe:

private enum nowTime = 1_397_037_462_000L;
private enum earlierTime = nowTime - 60_000;
private enum laterTime = nowTime + 60_000;
private enum nowDate = "Wed, 09 Apr 2014 09:57:42 GMT";
private enum springTag = "\"spring\"";
private enum weakTag = "W/" ~ springTag;
private enum otherTag = "\"framework\"";

private final class DateCheckingRequest : MockHttpServletRequest
{
    this(string method)
    {
        super(method, "https://example.org");
    }

    override long getDateHeader(string name)
    {
        foreach (c; getHeader(name))
            if (c == ';')
                throw new IllegalArgumentException("Invalid HTTP date");
        return super.getDateHeader(name);
    }
}

private struct Exchange
{
    DateCheckingRequest request;
    MockHttpServletResponse response;
    ServletWebRequest web;

    this(string method)
    {
        request = new DateCheckingRequest(method);
        response = new MockHttpServletResponse();
        web = new ServletWebRequest(request, response);
    }

    void expect(bool actual, int status)
    {
        const stopped = status == 304 || status == 412;
        assert(actual == stopped);
        assert(web.isNotModified() == stopped);
        assert(response.getStatus() == status);
    }

    void expectTag(string etag)
    {
        assert(response.getHeader(HttpHeaders.ETAG) == etag);
    }

    void expectLastModified(long millis)
    {
        assert(response.getHeader(HttpHeaders.LAST_MODIFIED) == HttpHeaders.formatDate(millis));
    }
}

@("ServletWebRequestHttpMethodsTests.ifMatchWildcardShouldMatchWhenETagPresent")
unittest
{
    auto f = Exchange("PUT");
    f.request.addHeader(HttpHeaders.IF_MATCH, "*");
    f.expect(f.web.checkNotModified(springTag), 200);
}

@("ServletWebRequestHttpMethodsTests.ifMatchWildcardShouldMatchETagMissing")
unittest
{
    auto f = Exchange("PUT");
    f.request.addHeader(HttpHeaders.IF_MATCH, "*");
    f.expect(f.web.checkNotModified(""), 412);
}

@("ServletWebRequestHttpMethodsTests.ifMatchValueShouldMatchWhenETagMatches")
unittest
{
    auto f = Exchange("PUT");
    f.request.addHeader(HttpHeaders.IF_MATCH, springTag);
    f.request.addHeader(HttpHeaders.IF_MATCH, otherTag);
    f.expect(f.web.checkNotModified(otherTag), 200);
}

@("ServletWebRequestHttpMethodsTests.ifMatchValueShouldRejectWhenETagDoesNotMatch")
unittest
{
    auto f = Exchange("PUT");
    f.request.addHeader(HttpHeaders.IF_MATCH, springTag);
    f.expect(f.web.checkNotModified(otherTag), 412);
}

@("ServletWebRequestHttpMethodsTests.ifMatchValueShouldUseStrongComparison")
unittest
{
    auto f = Exchange("PUT");
    f.request.addHeader(HttpHeaders.IF_MATCH, weakTag);
    f.expect(f.web.checkNotModified(springTag), 412);
}

@("ServletWebRequestHttpMethodsTests.ifMatchShouldOnlyBeConsideredForUnsafeMethods")
unittest
{
    foreach (method; ["GET", "HEAD"])
    {
        auto f = Exchange(method);
        f.request.addHeader(HttpHeaders.IF_MATCH, "*");
        f.expect(f.web.checkNotModified(springTag), 200);
    }
}

@("ServletWebRequestHttpMethodsTests.ifUnModifiedSinceShouldMatchValueWhenLater")
unittest
{
    auto f = Exchange("PUT");
    f.request.addHeader(HttpHeaders.IF_UNMODIFIED_SINCE, nowDate);
    f.expect(f.web.checkNotModified(earlierTime), 200);
    assert(f.response.getHeader(HttpHeaders.LAST_MODIFIED) is null);
}

@("ServletWebRequestHttpMethodsTests.ifUnModifiedSinceShouldNotMatchValueWhenEarlier")
unittest
{
    auto f = Exchange("PUT");
    f.request.addHeader(HttpHeaders.IF_UNMODIFIED_SINCE, HttpHeaders.formatDate(earlierTime));
    f.expect(f.web.checkNotModified(nowTime), 412);
}

@("ServletWebRequestHttpMethodsTests.ifUnModifiedSinceShouldSetHeadersWithSafeMethod")
unittest
{
    foreach (method; ["GET", "HEAD"])
    {
        auto f = Exchange(method);
        f.request.addHeader(HttpHeaders.IF_UNMODIFIED_SINCE, nowDate);
        f.expect(f.web.checkNotModified(earlierTime), 200);
        f.expectLastModified(earlierTime);
    }
}

@("ServletWebRequestHttpMethodsTests.ifNoneMatchShouldMatchIdenticalETagValue")
unittest
{
    foreach (method; ["GET", "HEAD"])
    {
        auto f = Exchange(method);
        f.request.addHeader(HttpHeaders.IF_NONE_MATCH, springTag);
        f.expect(f.web.checkNotModified(springTag), 304);
        f.expectTag(springTag);
    }
}

@("ServletWebRequestHttpMethodsTests.ifNoneMatchShouldMatchETagWithSeparatorChar")
unittest
{
    foreach (method; ["GET", "HEAD"])
    {
        auto f = Exchange(method);
        const value = "\"spring,framework\"";
        f.request.addHeader(HttpHeaders.IF_NONE_MATCH, value);
        f.expect(f.web.checkNotModified(value), 304);
        f.expectTag(value);
    }
}

@("ServletWebRequestHttpMethodsTests.ifNoneMatchShouldNotMatchDifferentETag")
unittest
{
    foreach (method; ["GET", "HEAD"])
    {
        auto f = Exchange(method);
        f.request.addHeader(HttpHeaders.IF_NONE_MATCH, springTag);
        f.expect(f.web.checkNotModified(otherTag), 200);
        f.expectTag(otherTag);
    }
}

@("ServletWebRequestHttpMethodsTests.ifNoneMatchShouldNotFailForUnquotedETag")
unittest
{
    foreach (method; ["GET", "HEAD"])
    {
        auto f = Exchange(method);
        f.request.addHeader(HttpHeaders.IF_NONE_MATCH, "missingquotes");
        f.expect(f.web.checkNotModified(springTag), 200);
        f.expectTag(springTag);
    }
}

@("ServletWebRequestHttpMethodsTests.ifNoneMatchShouldMatchPaddedETag")
unittest
{
    foreach (method; ["GET", "HEAD"])
    {
        auto f = Exchange(method);
        f.request.addHeader(HttpHeaders.IF_NONE_MATCH, springTag);
        f.expect(f.web.checkNotModified("spring"), 304);
        f.expectTag(springTag);
    }
}

@("ServletWebRequestHttpMethodsTests.ifNoneMatchShouldIgnoreWildcard")
unittest
{
    foreach (method; ["GET", "HEAD"])
    {
        auto f = Exchange(method);
        f.request.addHeader(HttpHeaders.IF_NONE_MATCH, "*");
        f.expect(f.web.checkNotModified(springTag), 200);
        f.expectTag(springTag);
    }
}

@("ServletWebRequestHttpMethodsTests.ifNoneMatchShouldRejectWildcardForUnsafeMethods")
unittest
{
    auto f = Exchange("PUT");
    f.request.addHeader(HttpHeaders.IF_NONE_MATCH, "*");
    f.expect(f.web.checkNotModified(springTag), 412);
}

@("ServletWebRequestHttpMethodsTests.ifNoneMatchValueShouldUseWeakComparison")
unittest
{
    foreach (method; ["GET", "HEAD"])
    {
        auto f = Exchange(method);
        f.request.addHeader(HttpHeaders.IF_NONE_MATCH, weakTag);
        f.expect(f.web.checkNotModified(springTag), 304);
        f.expectTag(springTag);
    }
}

@("ServletWebRequestHttpMethodsTests.ifModifiedSinceShouldMatchIfDatesEqual")
unittest
{
    foreach (method; ["GET", "HEAD"])
    {
        auto f = Exchange(method);
        f.request.addHeader(HttpHeaders.IF_MODIFIED_SINCE, nowDate);
        f.expect(f.web.checkNotModified(nowTime + 123), 304);
        f.expectLastModified(nowTime);
    }
}

@("ServletWebRequestHttpMethodsTests.ifModifiedSinceShouldNotMatchIfDateAfter")
unittest
{
    foreach (method; ["GET", "HEAD"])
    {
        auto f = Exchange(method);
        f.request.addHeader(HttpHeaders.IF_MODIFIED_SINCE, nowDate);
        f.expect(f.web.checkNotModified(laterTime), 200);
        f.expectLastModified(laterTime);
    }
}

@("ServletWebRequestHttpMethodsTests.ifModifiedSinceShouldNotOverrideResponseStatus")
unittest
{
    foreach (method; ["GET", "HEAD"])
    {
        auto f = Exchange(method);
        f.request.addHeader(HttpHeaders.IF_MODIFIED_SINCE, nowDate);
        f.response.setStatus(304);
        assert(!f.web.checkNotModified(nowTime));
        assert(!f.web.isNotModified());
        assert(f.response.getStatus() == 304);
    }
}

@("ServletWebRequestHttpMethodsTests.ifModifiedSinceShouldNotFailForInvalidResponseStatus")
unittest
{
    foreach (method; ["GET", "HEAD"])
    {
        auto f = Exchange(method);
        f.request.addHeader(HttpHeaders.IF_MODIFIED_SINCE, nowDate);
        f.response.setStatus(0);
        f.expect(f.web.checkNotModified(nowTime), 0);
    }
}

@("ServletWebRequestHttpMethodsTests.ifModifiedSinceShouldNotFailForTimestampWithLengthPart")
unittest
{
    foreach (method; ["GET", "HEAD"])
    {
        auto f = Exchange(method);
        f.request.addHeader(HttpHeaders.IF_MODIFIED_SINCE, nowDate ~ "; length=13774");
        f.expect(f.web.checkNotModified(nowTime), 304);
        f.expectLastModified(nowTime);
    }
}

@("ServletWebRequestHttpMethodsTests.IfNoneMatchAndIfNotModifiedSinceShouldMatchWhenSameETagAndDate")
unittest
{
    foreach (method; ["GET", "HEAD"])
    {
        auto f = Exchange(method);
        f.request.addHeader(HttpHeaders.IF_NONE_MATCH, springTag);
        f.request.addHeader(HttpHeaders.IF_MODIFIED_SINCE, nowDate);
        f.expect(f.web.checkNotModified(nullable(springTag), nowTime), 304);
        f.expectTag(springTag);
        f.expectLastModified(nowTime);
    }
}

@("ServletWebRequestHttpMethodsTests.IfNoneMatchAndIfNotModifiedSinceShouldMatchWhenSameETagAndLaterDate")
unittest
{
    foreach (method; ["GET", "HEAD"])
    {
        auto f = Exchange(method);
        f.request.addHeader(HttpHeaders.IF_NONE_MATCH, springTag);
        f.request.addHeader(HttpHeaders.IF_MODIFIED_SINCE, HttpHeaders.formatDate(laterTime));
        f.expect(f.web.checkNotModified(nullable(springTag), nowTime), 304);
        f.expectTag(springTag);
        f.expectLastModified(nowTime);
    }
}

@("ServletWebRequestHttpMethodsTests.IfNoneMatchAndIfNotModifiedSinceShouldNotMatchWhenDifferentETag")
unittest
{
    foreach (method; ["GET", "HEAD"])
    {
        auto f = Exchange(method);
        f.request.addHeader(HttpHeaders.IF_NONE_MATCH, springTag);
        f.request.addHeader(HttpHeaders.IF_MODIFIED_SINCE, HttpHeaders.formatDate(laterTime));
        f.expect(f.web.checkNotModified(nullable(otherTag), nowTime), 200);
        f.expectTag(otherTag);
        f.expectLastModified(nowTime);
    }
}

@("Flint.ServletWebRequest.retainsConditionalResult")
unittest
{
    auto request = new MockHttpServletRequest("GET", "/");
    request.addHeader(HttpHeaders.IF_NONE_MATCH, springTag);
    auto web = new ServletWebRequest(request);
    assert(web.checkNotModified(springTag));
    assert(web.isNotModified());
    assert(web.checkNotModified(otherTag));
}

@("Flint.ServletWebRequest.retainsExistingResponseValidators")
unittest
{
    auto f = Exchange("GET");
    f.response.setHeader(HttpHeaders.ETAG, otherTag);
    f.response.setDateHeader(HttpHeaders.LAST_MODIFIED, earlierTime);
    f.expect(f.web.checkNotModified(nullable(springTag), nowTime), 200);
    f.expectTag(otherTag);
    f.expectLastModified(earlierTime);
}
