// Ported from Spring Boot v4.2.0 ConfigurationPropertiesTests.java.
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: put repeated properties into Boot config data.
module property_relaxed.relaxed_binding_test;

import flint.boot : FlintApplication, WebApplicationType;
import flint.boot.context.config : ConfigDataResourceReader;
import flint.boot.context.properties : ClassRef;
import property_relaxed.relaxed_binding : WithRelaxedNamesProperties;

@safe:

private final class RelaxedPropertiesResource : ConfigDataResourceReader
{
    const(ubyte)[] read(string path)
    {
        enum content = "test.FOO_BAR=test1\ntest.FOO_BAR=test2\n" ~ "test.BAR-B-A-Z=testa\ntest.BAR-B-A-Z=testb\n";
        if (path == "resources/relaxed-binding.properties")
            return cast(const(ubyte)[]) content;
        return null;
    }

    string[] subdirectories(string)
    {
        return null;
    }

    bool directoryExists(string)
    {
        return false;
    }
}

@("ConfigurationPropertiesTests.loadWhenUsingRelaxedFormsAndOverrideShouldBind")
unittest
{
    auto application = new FlintApplication(ClassRef("property_relaxed.app.PropertyRelaxedApplication"));
    application.setWebApplicationType(WebApplicationType.NONE);
    application.setOutput((string) {});
    application.setEnvironmentVariables(null);
    application.setResourceReader(new RelaxedPropertiesResource());
    auto context = application.run([
        "--flint.boot.enableautoconfiguration=false", "--proof.properties.relaxed=true",
        "--flint.config.location=classpath:/relaxed-binding.properties"
    ]);
    scope (exit)
        context.close();

    auto bean = cast(WithRelaxedNamesProperties) context.getBeanFactory()
        .getBean("test-property_relaxed.relaxed_binding.WithRelaxedNamesProperties");
    assert(bean !is null, "the relaxed-name properties bean must be registered");
    assert(bean.getFooBar() == "test2", "the later underscored property value must bind");
    assert(bean.getBarBAZ() == "testb", "the later hyphenated property value must bind");
}
