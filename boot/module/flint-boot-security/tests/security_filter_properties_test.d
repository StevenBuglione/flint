// Ported from spring-boot v4.2.0: module/spring-boot-security/src/test/java/org/springframework/boot/security/autoconfigure/web/servlet/SecurityFilterPropertiesTests.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: the per-test fields are locals.
module security_filter_properties_test;

import flint.boot.context.properties.bind : Bindable, Binder;
import flint.boot.context.properties.source : ConfigurationPropertySource, MapConfigurationPropertySource;
import flint.boot.security.autoconfigure.web.servlet : SecurityFilterProperties;
import flint.engine.aot.descriptor : descriptorOf;
import flint.jakarta.servlet : DispatcherType;

@safe:

@("SecurityFilterPropertiesTests.validateDefaultFilterOrderMatchesMetadata")
unittest
{
    assert(new SecurityFilterProperties().getOrder() == -100);
}

@("SecurityFilterPropertiesTests.filterOrderShouldBind")
unittest
{
    auto properties = new SecurityFilterProperties;
    auto source = new MapConfigurationPropertySource("test", [
        ["spring.security.filter.order", "55"]
    ]);
    auto binder = new Binder([cast(ConfigurationPropertySource) source]);
    binder.getDescriptors().add(descriptorOf!DispatcherType());
    binder.getDescriptors().add(descriptorOf!(DispatcherType[])());
    binder.bind!SecurityFilterProperties("spring.security.filter",
            Bindable!SecurityFilterProperties.ofInstance(properties));
    assert(properties.getOrder() == 55);
}
