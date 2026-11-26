// Ported from spring-boot v4.2.0: core/spring-boot-autoconfigure/src/test/java/org/springframework/boot/autoconfigure/condition/ConditionalOnPropertyTests.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: supply each test's properties before refreshing a Flint context with the generated registry.
module property_conditions_test;

import flint.context.support : GenericApplicationContext;
import flint.core.env : MapPropertySource, StandardEnvironment;
import flint.engine.aot.any : Any;
import flint.java.util : HashMap;

@safe:

void main()
{
}

private void expectBean(string name, bool present, string[string] values = null)
{
    auto context = new GenericApplicationContext();
    scope (exit)
        context.close();
    auto sources = context.getConfigurableEnvironment().getPropertySources();
    sources.remove(StandardEnvironment.SYSTEM_PROPERTIES_PROPERTY_SOURCE_NAME);
    sources.remove(StandardEnvironment.SYSTEM_ENVIRONMENT_PROPERTY_SOURCE_NAME);
    auto properties = new HashMap!(string, Any)();
    foreach (key, value; values)
        properties.put(key, Any.of(value));
    sources.addFirst(new MapPropertySource("test", properties));
    context.deferAotRegistry();
    context.refresh();
    assert(context.containsBean(name) == present, name);
}

@("ConditionalOnPropertyTests.allPropertiesAreDefined")
unittest
{
    expectBean("bothRequired", true, ["property1": "value1", "property2": "value2"]);
}

@("ConditionalOnPropertyTests.notAllPropertiesAreDefined")
unittest
{
    expectBean("bothRequired", false, ["property1": "value1"]);
}

@("ConditionalOnPropertyTests.propertyValueEqualsFalse")
unittest
{
    expectBean("bothRequired", false, ["property1": "false", "property2": "value2"]);
}

@("ConditionalOnPropertyTests.propertyValueEqualsFALSE")
unittest
{
    expectBean("bothRequired", false, ["property1": "FALSE", "property2": "value2"]);
}

@("ConditionalOnPropertyTests.prefixWithoutPeriod")
unittest
{
    expectBean("withPrefix", true, ["spring.property": "value1"]);
}

@("ConditionalOnPropertyTests.enabledIfNotConfiguredOtherwise")
unittest
{
    expectBean("enabledByDefault", true);
}

@("ConditionalOnPropertyTests.enabledIfNotConfiguredOtherwiseWithConfigDifferentCase")
unittest
{
    expectBean("enabledByDefault", false, ["simple.my-property": "FALSE"]);
}

@("ConditionalOnPropertyTests.disableIfNotConfiguredOtherwise")
unittest
{
    expectBean("disabledByDefault", false);
}

@("ConditionalOnPropertyTests.defaultValueIsSet")
unittest
{
    expectBean("withDefaultValue", true, ["simple.myProperty": "bar"]);
}

@("ConditionalOnPropertyTests.defaultValueIsNotSet")
unittest
{
    expectBean("withDefaultValue", true);
}

@("ConditionalOnPropertyTests.defaultValueIsSetDifferentValue")
unittest
{
    expectBean("withDefaultValue", false, ["simple.myProperty": "another"]);
}

@("ConditionalOnPropertyTests.multiValuesAllSet")
unittest
{
    expectBean("withMultipleValues", true, [
        "simple.my-property": "bar",
        "simple.my-another-property": "bar"
    ]);
}

@("ConditionalOnPropertyTests.multiValuesOnlyOneSet")
unittest
{
    expectBean("withMultipleValues", false, ["simple.my-property": "bar"]);
}

@("ConditionalOnPropertyTests.usingValueAttribute")
unittest
{
    expectBean("fromValue", true, ["some.property": ""]);
}

@("ConditionalOnProperty compares havingValue without case")
unittest
{
    expectBean("withDefaultValue", true, ["simple.myProperty": "BaR"]);
}
