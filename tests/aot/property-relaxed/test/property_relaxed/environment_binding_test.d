// Ported from Spring Boot v4.2.0 ConfigurationPropertiesTests.java.
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: supply a controlled environment to FlintApplication.
module property_relaxed.environment_binding_test;

import flint.boot : FlintApplication, WebApplicationType;
import flint.boot.context.properties : ClassRef;
import property_relaxed.environment_binding : SimplePrefixedProperties;

@safe:

@("ConfigurationPropertiesTests.loadWhenDotsInSystemEnvironmentPropertiesShouldBind")
unittest
{
    auto application = new FlintApplication(ClassRef("property_relaxed.app.PropertyRelaxedApplication"));
    application.setWebApplicationType(WebApplicationType.NONE);
    application.setOutput((string) {});
    application.setEnvironmentVariables(["com.example.bar": "baz"]);
    auto context = application.run([
        "--flint.boot.enableautoconfiguration=false", "--proof.properties.environment=true"
    ]);
    scope (exit)
        context.close();

    auto bean = cast(SimplePrefixedProperties) context.getBeanFactory()
        .getBean("com.example-property_relaxed.environment_binding.SimplePrefixedProperties");
    assert(bean !is null && bean.getBar() == "baz", "the dotted environment key must bind the property");
}
