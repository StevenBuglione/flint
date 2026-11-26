// Ported from spring-boot v4.2.0: core/spring-boot-autoconfigure/src/test/java/org/springframework/boot/autoconfigure/SpringBootApplicationTests.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: read the merged Configuration metadata from Flint's descriptor.
module property_relaxed.boot_application_test;

import flint.context.annotation : Configuration;
import flint.engine.aot.descriptor : descriptorOf;
import property_relaxed.app : PropertyRelaxedApplication;

@safe:

@("SpringBootApplicationTests.proxyBeanMethodsIsEnabledByDefault")
unittest
{
    const merged = descriptorOf!PropertyRelaxedApplication().annotation("flint.context.annotation.Configuration");
    assert(merged !is null);
    assert(merged.value.get!Configuration.proxyBeanMethods);
}
