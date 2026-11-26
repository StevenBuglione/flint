// Ported from spring-boot v4.2.0: core/spring-boot-autoconfigure/src/test/java/org/springframework/boot/autoconfigure/condition/ConditionalOnClassTests.java
// with ConditionalOnMissingClassTests.java from the same directory.
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: start the context with the generated registry for each condition.
module class_conditions_test;

import aot_context : AotContext;
import class_conditions.app : BeanValue;
import flint.engine.aot.registry : installedRegistry;

@safe:

void main()
{
}

private AotContext startContext()
{
    auto context = new AotContext(null, null);
    installedRegistry()(context);
    context.refresh();
    return context;
}

private void expectBean(AotContext context, string name, string text)
{
    assert(context.hasBeanNamed(name), name);
    auto value = cast(BeanValue) context.getBean(name);
    assert(value !is null && value.text == text, name);
}

@("ConditionalOnClassTests.testVanillaOnClassCondition")
unittest
{
    auto context = startContext();
    scope (exit)
        context.close();
    expectBean(context, "requirePresentBar", "bar");
}

@("ConditionalOnClassTests.testMissingOnClassCondition")
unittest
{
    auto context = startContext();
    scope (exit)
        context.close();
    assert(!context.hasBeanNamed("requireAbsentBar"));
    expectBean(context, "foo", "foo");
}

@("ConditionalOnMissingClassTests.testVanillaOnClassCondition")
unittest
{
    auto context = startContext();
    scope (exit)
        context.close();
    assert(!context.hasBeanNamed("excludePresentBar"));
    expectBean(context, "foo", "foo");
}

@("ConditionalOnMissingClassTests.testMissingOnClassCondition")
unittest
{
    auto context = startContext();
    scope (exit)
        context.close();
    expectBean(context, "excludeAbsentBar", "bar");
    expectBean(context, "foo", "foo");
}
