// Ported from spring-boot v4.2.0: core/spring-boot-autoconfigure/src/test/java/org/springframework/boot/autoconfigure/condition/ConditionalOnWebApplicationTests.java
// with ConditionalOnNotWebApplicationTests.java from the same directory.
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: refresh a Flint context with the generated registry and selected web type.
module web_conditions_test;

import std.algorithm.searching : canFind;
import flint.context.support : GenericApplicationContext;
import web_conditions.app : BeanValue;

@safe:

void main()
{
}

private GenericApplicationContext startContext(string webType)
{
    auto context = new GenericApplicationContext();
    context.setWebApplicationType(webType);
    context.deferAotRegistry();
    context.refresh();
    return context;
}

private void expectBean(GenericApplicationContext context, string name, bool expected)
{
    assert(context.containsBean(name) == expected, name);
    if (expected)
    {
        const value = cast(BeanValue) context.getBeanErased(name, null, null);
        assert(value !is null && value.text == name, name);
    }
}

private void expectWebBeans(string webType, string[] names)
{
    auto context = startContext(webType);
    scope (exit)
        context.close();
    foreach (name; ["any", "servlet", "reactive"])
        expectBean(context, name, names.canFind(name));
}

private void expectNonWebBean(string webType, bool present)
{
    auto context = startContext(webType);
    scope (exit)
        context.close();
    expectBean(context, "none", present);
}

@("ConditionalOnWebApplicationTests.testWebApplicationWithServletContext")
unittest
{
    expectWebBeans("SERVLET", ["any", "servlet"]);
}

@("ConditionalOnWebApplicationTests.testWebApplicationWithReactiveContext")
unittest
{
    expectWebBeans("REACTIVE", ["any", "reactive"]);
}

@("ConditionalOnWebApplicationTests.testNonWebApplication")
unittest
{
    expectWebBeans("NONE", []);
}

@("ConditionalOnNotWebApplicationTests.testNotWebApplicationWithServletContext")
unittest
{
    expectNonWebBean("SERVLET", false);
}

@("ConditionalOnNotWebApplicationTests.testNotWebApplicationWithReactiveContext")
unittest
{
    expectNonWebBean("REACTIVE", false);
}

@("ConditionalOnNotWebApplicationTests.testNotWebApplication")
unittest
{
    expectNonWebBean("NONE", true);
}
