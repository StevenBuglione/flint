/++
Ported from spring-projects/spring-framework v7.1.0,
spring-test/src/test/java/org/springframework/test/web/servlet/result/ContentResultMatchersTests.java.
Copyright 2002-present the original author or authors.
Licensed under the Apache License, Version 2.0 (https://www.apache.org/licenses/LICENSE-2.0).
Modified by the Flint authors.
+/
module content_result_matchers_tests;

import flint.http : MediaType;
import flint.java.lang : AssertionError;
import flint.java.nio.charset : StandardCharsets;
import flint.mock.web : MockHttpServletResponse;
import flint.test.json : JsonCompareMode, JsonComparison;
import flint.test.web.servlet : DefaultMvcResult, MvcResult, ResultMatcher;
import flint.test.web.servlet.result : MockMvcResultMatchers;
import std.typecons : Nullable;

@safe:

private enum content = `{"foo":"bar","foo array":["foo","bar"]}`;

private MvcResult stubResult(string body = content, string mediaType = MediaType.APPLICATION_JSON_VALUE)
{
    auto response = new MockHttpServletResponse;
    if (mediaType !is null)
        response.addHeader("Content-Type", mediaType);
    response.getOutputStream().write(cast(const(ubyte)[])
            body);
    return new DefaultMvcResult(null, response);
}

private void expectFailure(ResultMatcher matcher, MvcResult result, string expectedMessage = null)
{
    try
    {
        matcher.match(result);
        assert(false);
    }
    catch (AssertionError failure)
    {
        if (expectedMessage !is null)
            assert(failure.getMessage() == expectedMessage, failure.getMessage());
    }
}

@("typeMatches")
unittest
{
    MockMvcResultMatchers.content().contentType(MediaType.APPLICATION_JSON_VALUE).match(stubResult());
}

@("typeNoMatch")
unittest
{
    expectFailure(MockMvcResultMatchers.content().contentType("text/plain"), stubResult());
}

@("string")
unittest
{
    MockMvcResultMatchers.content().string(content).match(stubResult());
}

@("stringNoMatch")
unittest
{
    expectFailure(MockMvcResultMatchers.content().encoding("bogus"), stubResult());
}

@("bytes")
unittest
{
    MockMvcResultMatchers.content().bytes(cast(const(ubyte)[]) content).match(stubResult());
}

@("bytesNoMatch")
unittest
{
    expectFailure(MockMvcResultMatchers.content().bytes(cast(const(ubyte)[]) "bogus"), stubResult());
}

@("jsonLenientMatch")
unittest
{
    auto matchers = MockMvcResultMatchers.content();
    matchers.json("{\n \"foo\" : \"bar\"\n}").match(stubResult());
    matchers.json(`{"foo":"bar"}`, JsonCompareMode.LENIENT).match(stubResult());
}

@("jsonLenientMatchWithDeprecatedBooleanFlag")
unittest
{
    MockMvcResultMatchers.content().json(`{"foo":"bar"}`, false).match(stubResult());
}

@("jsonStrictMatch")
unittest
{
    auto matchers = MockMvcResultMatchers.content();
    matchers.json(`{"foo":"bar", "foo array":["foo","bar"]}`, JsonCompareMode.STRICT).match(stubResult());
    matchers.json(`{"foo array":["foo","bar"], "foo":"bar"}`, JsonCompareMode.STRICT).match(stubResult());
}

@("jsonStrictMatchWithDeprecatedBooleanFlag")
unittest
{
    auto matchers = MockMvcResultMatchers.content();
    matchers.json(`{"foo":"bar", "foo array":["foo","bar"]}`, true).match(stubResult());
    matchers.json(`{"foo array":["foo","bar"], "foo":"bar"}`, true).match(stubResult());
}

@("jsonLenientNoMatch")
unittest
{
    expectFailure(MockMvcResultMatchers.content().json(`{"fooo":"bar"}`), stubResult());
}

@("jsonStrictNoMatch")
unittest
{
    expectFailure(MockMvcResultMatchers.content().json(`{"foo":"bar", "foo array":["bar","foo"]}`,
            JsonCompareMode.STRICT), stubResult());
}

@("jsonStrictNoMatchWithDeprecatedBooleanFlag")
unittest
{
    expectFailure(MockMvcResultMatchers.content().json(`{"foo":"bar", "foo array":["bar","foo"]}`, true), stubResult());
}

@("jsonUtf8Match")
unittest
{
    MockMvcResultMatchers.content().json(`{"name":"Jürgen"}`).match(stubResult(`{"name":"Jürgen"}`));
}

@("MockMvc JSON passes both bodies and preserves a custom comparator diagnostic")
unittest
{
    auto matcher = MockMvcResultMatchers.content().json(`{"example":42}`,
            (Nullable!string expected, Nullable!string actual) {
        assert(expected.get() == `{"example":42}`);
        assert(actual.get() == content);
        return JsonComparison.mismatch("custom error");
    });
    expectFailure(matcher, stubResult(), "custom error");
}

@("MockMvc content recognizes Java charsets and distinguishes a missing content type")
unittest
{
    auto matchers = MockMvcResultMatchers.content();
    matchers.encoding(StandardCharsets.UTF_8).match(stubResult("Jürgen", "text/plain;charset=UTF-8"));
    auto missing = stubResult("", null);
    expectFailure(matchers.contentType("text/plain"), missing, "Content type not set");
    expectFailure(matchers.contentTypeCompatibleWith("text/plain"), missing, "Content type not set");
}
