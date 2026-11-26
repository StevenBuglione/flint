/++
Ported from spring-projects/spring-framework v7.1.0,
spring-test/src/test/java/org/springframework/test/web/servlet/samples/standalone/resultmatchers/
HandlerAssertionTests.java.
Copyright 2002-present the original author or authors.
Licensed under the Apache License, Version 2.0 (https://www.apache.org/licenses/LICENSE-2.0).
Modified by the Flint authors: the controller class token is a template parameter (R4).
+/
module handler_assertion_tests;

import flint.engine.aot.name : typeNameOf;
import flint.java.lang : AssertionError;
import flint.test.web.servlet : DefaultMvcResult, MvcResult, ResultActions, ResultMatcher;
import flint.test.web.servlet.request : MockMvcRequestBuilders;
import flint.test.web.servlet.result : MockMvcResultMatchers;
import flint.test.web.servlet.setup : MockMvcBuilders;
import flint.web.bind.annotation : GetMapping, RestController;

@safe:

private alias Matchers = MockMvcResultMatchers;

@RestController
private final class SimpleController
{
    @GetMapping("/")
    string handle()
    {
        return "ok";
    }
}

private ResultActions performGet()
{
    auto mvc = MockMvcBuilders.standaloneSetup(new SimpleController).alwaysExpect(Matchers.status().isOk()).build();
    return mvc.perform(MockMvcRequestBuilders.get("/"));
}

@("handlerType")
unittest
{
    performGet().andExpect(Matchers.handler().handlerType!SimpleController());
}

@("methodName")
unittest
{
    performGet().andExpect(Matchers.handler().methodName("handle"));
}

private final class StubResult : DefaultMvcResult
{
    private Object handler;

    this(Object handler)
    {
        super(null, null);
        this.handler = handler;
    }

    override Object getHandler()
    {
        return handler;
    }
}

private void fails(ResultMatcher matcher, MvcResult result, string message)
{
    try
    {
        matcher.match(result);
        assert(false);
    }
    catch (AssertionError failure)
        assert(failure.getMessage() == message, failure.getMessage());
}

unittest
{
    auto result = performGet().andReturn();
    auto matchers = Matchers.handler();
    fails(matchers.methodName("other"), result, "Handler method expected:<other> but was:<handle>");
    fails(matchers.handlerType!Object(), result,
            "Handler type expected:<" ~ typeNameOf!Object ~ "> but was:<" ~ typeNameOf!SimpleController ~ ">");
    fails(matchers.handlerType!SimpleController(), new StubResult(null), "No handler");
    fails(matchers.methodName("handle"), new StubResult(null), "Not a HandlerMethod: null");
    matchers.handlerType!SimpleController().match(new StubResult(new SimpleController));
}
