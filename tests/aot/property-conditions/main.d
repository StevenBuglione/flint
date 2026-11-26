// Ported from spring-boot v4.2.0: core/spring-boot-autoconfigure/src/test/java/org/springframework/boot/autoconfigure/condition/ConditionalOnPropertyTests.java
// with ConditionalOnBooleanPropertyTests.java from the same directory.
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

@("ConditionalOnBooleanPropertyTests.defaultsWhenTrue")
unittest
{
    expectBean("booleanDefaults", true, ["test": "true"]);
}

@("ConditionalOnBooleanPropertyTests.defaultsWhenFalse")
unittest
{
    expectBean("booleanDefaults", false, ["test": "false"]);
}

@("ConditionalOnBooleanPropertyTests.defaultsWhenMissing")
unittest
{
    expectBean("booleanDefaults", false);
}

@("ConditionalOnBooleanPropertyTests.havingValueTrueMatchIfMissingFalseWhenTrue")
unittest
{
    expectBean("booleanTrueRequired", true, ["test": "true"]);
}

@("ConditionalOnBooleanPropertyTests.havingValueTrueMatchIfMissingFalseWhenFalse")
unittest
{
    expectBean("booleanTrueRequired", false, ["test": "false"]);
}

@("ConditionalOnBooleanPropertyTests.havingValueTrueMatchIfMissingFalseWhenMissing")
unittest
{
    expectBean("booleanTrueRequired", false);
}

@("ConditionalOnBooleanPropertyTests.havingValueTrueMatchIfMissingTrueWhenTrue")
unittest
{
    expectBean("booleanTrueOptional", true, ["test": "true"]);
}

@("ConditionalOnBooleanPropertyTests.havingValueTrueMatchIfMissingTrueWhenFalse")
unittest
{
    expectBean("booleanTrueOptional", false, ["test": "false"]);
}

@("ConditionalOnBooleanPropertyTests.havingValueTrueMatchIfMissingTrueWhenMissing")
unittest
{
    expectBean("booleanTrueOptional", true);
}

@("ConditionalOnBooleanPropertyTests.havingValueFalseMatchIfMissingFalseWhenTrue")
unittest
{
    expectBean("booleanFalseRequired", false, ["test": "true"]);
}

@("ConditionalOnBooleanPropertyTests.havingValueFalseMatchIfMissingFalseWhenFalse")
unittest
{
    expectBean("booleanFalseRequired", true, ["test": "false"]);
}

@("ConditionalOnBooleanPropertyTests.havingValueFalseMatchIfMissingFalseWhenMissing")
unittest
{
    expectBean("booleanFalseRequired", false);
}

@("ConditionalOnBooleanPropertyTests.havingValueFalseMatchIfMissingTrueWhenTrue")
unittest
{
    expectBean("booleanFalseOptional", false, ["test": "true"]);
}

@("ConditionalOnBooleanPropertyTests.havingValueFalseMatchIfMissingTrueWhenFalse")
unittest
{
    expectBean("booleanFalseOptional", true, ["test": "false"]);
}

@("ConditionalOnBooleanPropertyTests.havingValueFalseMatchIfMissingTrueWhenMissing")
unittest
{
    expectBean("booleanFalseOptional", true);
}

@("ConditionalOnBooleanPropertyTests.withPrefix")
unittest
{
    // The pinned method supplies foo.test to the false-optional configuration.
    expectBean("booleanFalseOptional", true, ["foo.test": "true"]);
    expectBean("booleanPrefixed", true, ["foo.test": "true"]);
    expectBean("booleanPrefixed", false, ["test": "true"]);
}

@("ConditionalOnMissingBeanTests.impliedOnBeanMethod")
unittest
{
    expectBean("exampleBean", true, ["test.example-bean": "true"]);
    expectBean("exampleBean2", false, ["test.example-bean": "true"]);
}

@("An inferred missing-bean condition supplies the fallback when the user bean is absent")
unittest
{
    expectBean("exampleBean", false);
    expectBean("exampleBean2", true);
}

private void expectHierarchicalFallback(bool hasFoo)
{
    auto parent = new GenericApplicationContext();
    scope (exit)
        parent.close();
    if (hasFoo)
        parent.registerBean!Object("foo", () => new Object());
    parent.refresh();

    auto child = new GenericApplicationContext();
    scope (exit)
        child.close();
    child.setParent(parent);
    child.deferAotRegistry();
    child.refresh();

    assert(child.containsBean("foo") == hasFoo);
    assert(!child.containsLocalBean("foo"));
    assert(child.containsLocalBean("bar") == !hasFoo, "named fallback in child");
}

@("ConditionalOnMissingBeanTests.hierarchyConsidered")
unittest
{
    expectHierarchicalFallback(true);
}

@("A named missing-bean condition matches when the parent has no candidate")
unittest
{
    expectHierarchicalFallback(false);
}
