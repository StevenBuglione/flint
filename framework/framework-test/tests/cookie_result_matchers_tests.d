/++
Ported from spring-projects/spring-framework v7.1.0,
spring-test/src/test/java/org/springframework/test/web/servlet/samples/standalone/resultmatchers/
CookieAssertionTests.java.
Copyright 2002-present the original author or authors.
Licensed under the Apache License, Version 2.0 (https://www.apache.org/licenses/LICENSE-2.0).
Modified by the Flint authors. The interceptor supplies the same fixture cookies directly.
+/
module cookie_result_matchers_tests;

import flint.jakarta.servlet.http : Cookie, HttpServletRequest, HttpServletResponse;
import flint.java.lang : AssertionError;
import flint.mock.web : MockHttpServletResponse;
import flint.test.web.servlet : DefaultMvcResult, ResultActions, ResultMatcher;
import flint.test.web.servlet.request : MockMvcRequestBuilders;
import flint.test.web.servlet.result : MockMvcResultMatchers;
import flint.test.web.servlet.setup : MockMvcBuilders;
import flint.web.bind.annotation : GetMapping, RestController;
import flint.web.servlet : HandlerInterceptor;
import std.typecons : Nullable;

@safe:

private enum localeCookie = "org.springframework.web.servlet.i18n.CookieLocaleResolver.LOCALE";
private enum secondCookie = "SecondCookie";
private enum cookieAttribute = "COOKIE_ATTRIBUTE";
private alias cookie = MockMvcResultMatchers.cookie;

@RestController
private final class SimpleController
{
    @GetMapping("/")
    string home()
    {
        return "home";
    }
}

private final class CookieInterceptor : HandlerInterceptor
{
    override bool preHandle(HttpServletRequest request, HttpServletResponse response, Object handler)
    {
        auto locale = new Cookie(localeCookie, "en-US");
        locale.setDomain("domain");
        locale.setPath("/");
        locale.setHttpOnly(true);
        locale.setAttribute("SameSite", "foo");
        response.addCookie(locale);

        auto extra = new Cookie(secondCookie, "value");
        extra.setAttribute("sameSite", "Strict");
        extra.setAttribute(cookieAttribute, "there");
        response.addCookie(extra);
        return true;
    }
}

private ResultActions performGet()
{
    auto mvc = MockMvcBuilders.standaloneSetup(new SimpleController).addInterceptors(new CookieInterceptor).build();
    return mvc.perform(MockMvcRequestBuilders.get("/")).andExpect(MockMvcResultMatchers.status().isOk());
}

private void expectFailure(ResultMatcher matcher, string message)
{
    try
    {
        performGet().andExpect(matcher);
        assert(false);
    }
    catch (AssertionError failure)
    {
        assert(failure.getMessage() == message, failure.getMessage());
    }
}

@("exists")
unittest
{
    performGet().andExpect(cookie().exists(localeCookie));
}

@("notExists")
unittest
{
    performGet().andExpect(cookie().doesNotExist("unknownCookie"));
}

@("maxAge")
unittest
{
    performGet().andExpect(cookie().maxAge(localeCookie, -1));
}

@("domain")
unittest
{
    performGet().andExpect(cookie().domain(localeCookie, "domain"));
}

@("sameSite")
unittest
{
    performGet().andExpect(cookie().sameSite(localeCookie, "foo"));
}

@("sameSiteNotEquals")
unittest
{
    expectFailure(cookie().sameSite(secondCookie, "Str"),
            "Response cookie 'SecondCookie' attribute 'SameSite' expected:<Str> but was:<Strict>");
}

@("path")
unittest
{
    performGet().andExpect(cookie().path(localeCookie, "/"));
}

@("secured")
unittest
{
    performGet().andExpect(cookie().secure(localeCookie, false));
}

@("httpOnly")
unittest
{
    performGet().andExpect(cookie().httpOnly(localeCookie, true));
}

@("attribute")
unittest
{
    performGet().andExpect(cookie().attribute(secondCookie, cookieAttribute, "there"));
}

@("attributeNotEquals")
unittest
{
    expectFailure(cookie().attribute(secondCookie, cookieAttribute, "foo"),
            "Response cookie 'SecondCookie' attribute 'COOKIE_ATTRIBUTE' expected:<foo> but was:<there>");
}

@("MockMvc cookie flags, empty attributes, and lookup order")
unittest
{
    auto first = new Cookie("token", "first");
    first.setMaxAge(0);
    first.setSecure(true);
    first.setAttribute("Partitioned", "");
    auto response = new MockHttpServletResponse;
    response.addCookie(first);
    response.addCookie(new Cookie("token", "second"));
    auto result = new DefaultMvcResult(null, response);
    cookie().exists("token").match(result);
    cookie().doesNotExist("TOKEN").match(result);
    cookie().maxAge("token", 0).match(result);
    cookie().secure("token", true).match(result);
    cookie().httpOnly("token", false).match(result);
    cookie().partitioned("token", true).match(result);
    cookie().attribute("token", "partitioned", "").match(result);
    cookie().value("token", "first").match(result);
    cookie().path("token", Nullable!string.init).match(result);
    cookie().sameSite("token", null).match(result);

    expectFailure(cookie().attribute(secondCookie, "absent", ""),
            "Response cookie 'SecondCookie' attribute 'absent' expected:<> but was:<null>");
    expectFailure(cookie().exists("TOKEN"), "No cookie with name 'TOKEN'");
    expectFailure(cookie().doesNotExist(secondCookie), "Unexpected cookie with name 'SecondCookie'");
}

unittest
{
    auto response = new MockHttpServletResponse;
    auto responseCookie = new Cookie("flags", null);
    response.addCookie(responseCookie);
    auto result = new DefaultMvcResult(null, response);
    auto matchers = cookie();
    matchers.value("flags", null).match(result);
    matchers.domain("flags", Nullable!string.init).match(result);
    matchers.partitioned("flags", false).match(result);

    responseCookie.setAttribute("Secure", "non-empty");
    responseCookie.setAttribute("HTTPONLY", "non-empty");
    responseCookie.setAttribute("Partitioned", "non-empty");
    matchers.secure("flags", false).match(result);
    matchers.httpOnly("flags", false).match(result);
    matchers.partitioned("flags", true).match(result);
    expectFailure(matchers.partitioned(secondCookie, true),
            "Response cookie 'SecondCookie' partitioned expected:<true> but was:<false>");
}
