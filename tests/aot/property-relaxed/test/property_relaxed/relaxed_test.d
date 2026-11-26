// Ported from spring-boot v4.2.0: core/spring-boot-autoconfigure/src/test/java/org/springframework/boot/autoconfigure/condition/ConditionalOnPropertyTests.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: supply config data to Boot's ApplicationEnvironment before refreshing the context.
module property_relaxed.relaxed_test;

import flint.boot : ApplicationEnvironment;
import flint.boot.context.config : ConfigDataResult, Profiles;
import flint.boot.context.properties.source : MapConfigurationPropertySource;
import flint.context.support : GenericApplicationContext;

@safe:

private void expectBean(string name, bool present, const string[2][] entries)
{
    auto context = new GenericApplicationContext();
    scope (exit)
        context.close();
    auto source = new MapConfigurationPropertySource("test", entries);
    // The fixture evaluates the explicit configurations without Boot's binder or unrelated auto-configurations.
    auto settings = new MapConfigurationPropertySource("test-settings",
            [["flint.boot.enableautoconfiguration", "false"]]);
    context.setEnvironment(new ApplicationEnvironment(new ConfigDataResult([source, settings],
            new Profiles(null, ["default"]))));
    context.deferAotRegistry();
    context.refresh();
    assert(context.containsBean(name) == present, name);
}

@("ConditionalOnPropertyTests.relaxedName")
unittest
{
    expectBean("withRelaxedName", true, [["spring.theRelaxedProperty", "value1"]]);
}

@("ConditionalOnPropertyTests.enabledIfNotConfiguredOtherwiseWithConfig")
unittest
{
    expectBean("enabledByDefault", false, [["simple.myProperty", "false"]]);
}

@("ConditionalOnPropertyTests.disableIfNotConfiguredOtherwiseWithConfig")
unittest
{
    expectBean("disabledByDefault", true, [["simple.myProperty", "true"]]);
}

@("ConditionalOnPropertyTests.disableIfNotConfiguredOtherwiseWithConfigDifferentCase")
unittest
{
    expectBean("disabledByDefault", true, [["simple.myproperty", "TrUe"]]);
}

@("ConditionalOnPropertyTests.simpleValueIsSet")
unittest
{
    expectBean("withRequiredString", true, [["simple.myProperty", "bar"]]);
}

@("ConditionalOnPropertyTests.caseInsensitive")
unittest
{
    expectBean("withRequiredString", true, [["simple.myProperty", "BaR"]]);
}

@("ConditionalOnPropertyTests.prefix")
unittest
{
    expectBean("withRequiredString", true, [["simple.myProperty", "bar"]]);
}

@("ConditionalOnPropertyTests.relaxedEnabledByDefault")
unittest
{
    expectBean("withRequiredString", true, [["simple.my-property", "bar"]]);
}

@("ConditionalOnPropertyTests.metaAnnotationConditionMatchesWhenPropertyIsSet")
unittest
{
    expectBean("withMeta", true, [["my.feature.enabled", "true"]]);
}

@("ConditionalOnPropertyTests.metaAnnotationConditionDoesNotMatchWhenPropertyIsNotSet")
unittest
{
    expectBean("withMeta", false, []);
}

@("ConditionalOnPropertyTests.metaAnnotationWithAliasConditionMatchesWhenPropertyIsSet")
unittest
{
    expectBean("withAliasedMeta", true, [["my.feature.enabled", "true"]]);
}

@("A composed property condition with a prefix alias requires the prefixed key")
unittest
{
    expectBean("withAliasedMeta", false, [["enabled", "true"]]);
}
