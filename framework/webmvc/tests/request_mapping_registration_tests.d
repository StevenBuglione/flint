module flint.web.servlet.request_mapping_registration_tests;

import flint.engine.aot.mapping : HandlerMapping;
import flint.java.lang : IllegalStateException;
import flint.web.method : HandlerMethod;
import flint.web.servlet.mvc.method : RequestMappingInfo;
import flint.web.servlet.mvc.method.annotation : RequestMappingHandlerMapping;
import std.exception : assertThrown;

@safe:

private HandlerMethod handler(string beanName)
{
    HandlerMapping row;
    row.bean = beanName;
    return new HandlerMethod(new Object(), "java.lang.Object", row);
}

@("Flint.RequestMappingRegistration.distinctHeaders")
unittest
{
    // Spring's FrameworkExtensionTests registers these header predicates on the same route.
    auto mapping = new RequestMappingHandlerMapping(null, null);
    auto foo = new RequestMappingInfo(["/"], ["GET"], null, ["Foo=a=b"]);
    auto bar = new RequestMappingInfo(["/"], ["GET"], null, ["Bar=a=b"]);
    mapping.registerMapping(foo, handler("foo"));
    mapping.registerMapping(bar, handler("bar"));
    assert(mapping.registeredMappingInfos() == [foo, bar]);
}

@("Flint.RequestMappingRegistration.distinctConsumes")
unittest
{
    auto mapping = new RequestMappingHandlerMapping(null, null);
    auto json = new RequestMappingInfo(["/"], ["POST"], null, null, ["application/json"]);
    auto text = new RequestMappingInfo(["/"], ["POST"], null, null, ["text/plain"]);
    mapping.registerMapping(json, handler("json"));
    mapping.registerMapping(text, handler("text"));
    assert(mapping.registeredMappingInfos() == [json, text]);
}

@("Flint.RequestMappingRegistration.equivalentConditionsAreAmbiguous")
unittest
{
    auto mapping = new RequestMappingHandlerMapping(null, null);
    auto original = new RequestMappingInfo(["/a", "/b"], ["GET", "POST"], ["id", "!debug"], [
        "X-Custom=yes"
    ]);
    auto reordered = new RequestMappingInfo(["/b", "/a", "/b"], ["POST", "GET"], ["!debug", "id"], [
        "x-custom=yes"
    ]);
    mapping.registerMapping(original, handler("original"));
    assertThrown!IllegalStateException(mapping.registerMapping(reordered, handler("reordered")));
    assert(mapping.registeredMappingInfos() == [original]);
}
