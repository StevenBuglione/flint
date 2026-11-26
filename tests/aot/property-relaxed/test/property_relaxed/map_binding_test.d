// Ported from Spring Boot v4.2.0 ConfigurationPropertiesTests.java.
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: start the generated registry through FlintApplication.
module property_relaxed.map_binding_test;

import flint.boot : FlintApplication, WebApplicationType;
import flint.boot.context.properties : ClassRef;
import property_relaxed.map_binding : WithMapProperties;

@safe:

@("ConfigurationPropertiesTests.loadShouldBindToMap")
unittest
{
    auto application = new FlintApplication(ClassRef("property_relaxed.app.PropertyRelaxedApplication"));
    application.setWebApplicationType(WebApplicationType.NONE);
    application.setOutput((string) {});
    application.setEnvironmentVariables(null);
    auto context = application.run([
        "--flint.boot.enableautoconfiguration=false", "--proof.properties.map=true",
        "--test.map.foo=bar"
    ]);
    scope (exit)
        context.close();

    auto bean = cast(WithMapProperties) context.getBeanFactory()
        .getBean("test-property_relaxed.map_binding.WithMapProperties");
    assert(bean !is null, "the properties bean for the map must be registered");
    auto map = bean.getMap();
    const matches = map !is null && map.size() == 1 && map.get("foo") == "bar";
    assert(matches, "the map must bind exactly the configured entry");
}
