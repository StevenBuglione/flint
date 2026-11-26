// Ported from spring-boot v4.2.0: core/spring-boot/src/test/java/org/springframework/boot/context/properties/source/ConfigurationPropertySourcesTests.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (https://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: use Flint's configurable environment and map types.
module boot_tests.configuration_property_sources_attach_tests;

import flint.boot : ApplicationEnvironment;
import flint.boot.context.config : ConfigDataResult, Profiles;
import flint.boot.context.properties.source : ConfigurationPropertySources, MapConfigurationPropertySource;
import flint.core.env : MapPropertySource, StandardEnvironment, SystemEnvironmentPropertySource;
import flint.engine.aot.any : Any;
import flint.java.util : LinkedHashMap;

@safe:

private MapPropertySource properties(string propertySource, string key, string value)
{
    auto entries = new LinkedHashMap!(string, Any);
    entries.put(key, Any.of(value));
    return new MapPropertySource(propertySource, entries);
}

@("attachShouldAddAdapterAtBeginning")
unittest
{
    auto environment = new StandardEnvironment;
    auto entries = new LinkedHashMap!(string, Any);
    entries.put("SERVER_PORT", Any.of("1234"));
    environment.getPropertySources().addFirst(properties("config", "server.port", "4568"));
    environment.getPropertySources().addFirst(new SystemEnvironmentPropertySource("systemEnvironment", entries));
    auto sources = environment.getPropertySources();
    const before = sources.size();

    ConfigurationPropertySources.attach(environment);
    auto attached = sources.toArray()[0];
    assert(sources.size() == before + 1 && attached is sources.get("configurationProperties"));
    assert(ConfigurationPropertySources.isAttachedConfigurationPropertySource(attached));
    assert(!ConfigurationPropertySources.isAttachedConfigurationPropertySource(sources.get("config")));
    assert(environment.getProperty("server.port") == "1234");
}

@("Repeated attach follows the same sources and retains its adapter")
unittest
{
    auto environment = new StandardEnvironment;
    auto sources = environment.getPropertySources();
    ConfigurationPropertySources.attach(environment);
    const first = sources.get("configurationProperties");
    sources.addFirst(properties("later", "sample.someKey", "new"));

    ConfigurationPropertySources.attach(environment);
    assert(first !is null && sources.get("configurationProperties") is first);
    assert(sources.toArray()[0] is first);
    assert(environment.getProperty("sample.some-key") == "new");
    sources.remove("later");
    assert(environment.getProperty("sample.some-key") is null);
}

@("attachShouldReattachInMergedSetup")
unittest
{
    auto parent = new StandardEnvironment;
    parent.getPropertySources().addFirst(properties("parent", "sample.someKey", "parent"));
    ConfigurationPropertySources.attach(parent);

    auto child = new StandardEnvironment;
    child.merge(parent);
    child.getPropertySources().addFirst(properties("child", "sample.someKey", "child"));
    ConfigurationPropertySources.attach(child);

    assert(child.getPropertySources().get("configurationProperties") !is parent.getPropertySources()
            .get("configurationProperties"));
    assert(parent.getProperty("sample.some-key") == "parent");
    assert(child.getProperty("sample.some-key") == "child");
}

@("environmentPropertyExpansionShouldWorkWhenAttached")
unittest
{
    auto environment = new StandardEnvironment;
    auto entries = new LinkedHashMap!(string, Any);
    entries.put("fooBar", Any.of("Spring ${barBaz} ${bar-baz}"));
    entries.put("barBaz", Any.of("Boot"));
    environment.getPropertySources().addFirst(new MapPropertySource("test", entries));

    ConfigurationPropertySources.attach(environment);
    assert(environment.getProperty("foo-bar") == "Spring Boot Boot");
}

@("Attachment prefers native spelling and the current typed value")
unittest
{
    auto environment = new StandardEnvironment;
    auto entries = new LinkedHashMap!(string, Any);
    entries.put("FOO_THE_BAR", Any.of(7));
    entries.put("FOO_THEBAR", Any.of(1));
    environment.getPropertySources().addFirst(new SystemEnvironmentPropertySource("test-systemEnvironment", entries));

    ConfigurationPropertySources.attach(environment);
    assert(environment.getProperty!int("foo.the-bar") == 1);
    entries.remove("FOO_THEBAR");
    assert(environment.getProperty!int("foo.the-bar") == 7);
}

@("Explicit attachment lets Boot's application environment resolve added test values")
unittest
{
    auto configuration = new MapConfigurationPropertySource("config", [["sample.value", "ordinary"]]);
    auto environment = new ApplicationEnvironment(new ConfigDataResult([configuration], new Profiles(null, [
        "default"
    ])));
    assert(!environment.getPropertySources().contains("configurationProperties"));
    environment.getPropertySources().addFirst(properties("test", "sample.value", "test"));
    assert(environment.getProperty("sample.value") == "ordinary");
    ConfigurationPropertySources.attach(environment);
    assert(environment.getProperty("sample.value") == "test");
}
