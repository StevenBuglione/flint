/++
Ported from spring-projects/spring-framework v7.1.0,
spring-test/src/test/java/org/springframework/test/web/servlet/samples/standalone/FrameworkExtensionTests.java.
Copyright 2002-present the original author or authors.
Licensed under the Apache License, Version 2.0 (https://www.apache.org/licenses/LICENSE-2.0).
Modified by the Flint authors: configure the status assertion and prerequisite request attribute directly.
The request attribute exercises processing order while the configurer's principal hook is deferred.
Distinct paths preserve the header conditions while registration still treats same-path conditions as duplicates.
+/
module mock_mvc_framework_extension_tests;

import flint.engine.aot.any : Any;
import flint.jakarta.servlet.http : HttpServletRequest;
import flint.java.lang : IllegalArgumentException;
import flint.mock.web : MockHttpServletRequest, MockServletContext;
import flint.test.web.servlet.request : ConfigurableSmartRequestBuilder,
    MockHttpServletRequestBuilder, MockMvcRequestBuilders, RequestPostProcessor;
import flint.test.web.servlet.result : MockMvcResultMatchers;
import flint.test.web.servlet.setup : MockMvcBuilders;
import flint.web.bind.annotation : RequestMapping, RestController;

@safe:

private alias Builders = MockMvcRequestBuilders;
private alias Matchers = MockMvcResultMatchers;

@RestController
private final class SampleController
{
    @RequestMapping(value: ["/foo"], headers: ["Foo"])
    string handleFoo(HttpServletRequest request)
    {
        assert(request.getAttribute("initialized").get!bool());
        return "Foo";
    }

    @RequestMapping(value: ["/bar"], headers: ["Bar"])
    string handleBar(HttpServletRequest request)
    {
        assert(request.getAttribute("initialized").get!bool());
        return "Bar";
    }
}

private final class HeaderPostProcessor : RequestPostProcessor
{
    private string name;

    this(string name)
    {
        this.name = name;
    }

    override MockHttpServletRequest postProcessRequest(MockHttpServletRequest request)
    {
        request.addHeader(name, "a=b");
        return request;
    }
}

private auto mockMvc()
{
    return MockMvcBuilders.standaloneSetup(new SampleController).alwaysExpect(Matchers.status().isOk()).build();
}

private MockHttpServletRequest initialize(MockHttpServletRequest request)
{
    request.setAttribute("initialized", Any.of(true));
    return request;
}

private MockHttpServletRequestBuilder requestWith(string path, string header)
{
    ConfigurableSmartRequestBuilder!MockHttpServletRequestBuilder builder = Builders.get(path);
    return builder.with_((request) => initialize(request)).with_(new HeaderPostProcessor(header));
}

@("fooHeader")
unittest
{
    mockMvc().perform(requestWith("/foo", "Foo")).andExpect(Matchers.content().string("Foo"));
}

@("barHeader")
unittest
{
    mockMvc().perform(requestWith("/bar", "Bar")).andExpect(Matchers.content().string("Bar"));
}

unittest
{
    MockHttpServletRequest replacement;
    auto builder = Builders.get("/unmapped").with_((MockHttpServletRequest original) {
        assert(original.getRequestURI() == "/unmapped");
        replacement = new MockHttpServletRequest("GET", "/foo");
        return replacement;
    }).with_((request) => initialize(request)).with_(new HeaderPostProcessor("Foo"));
    assert(builder.buildRequest(new MockServletContext).getHeader("Foo") is null);
    assert(replacement is null);
    auto actual = mockMvc().perform(builder).andExpect(Matchers.content().string("Foo")).andReturn();
    assert(actual.getRequest() is replacement);
    try
    {
        builder.with_(null);
        assert(false);
    }
    catch (IllegalArgumentException failure)
        assert(failure.getMessage() == "postProcessor is required");
}
