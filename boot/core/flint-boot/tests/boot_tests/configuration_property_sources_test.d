// Ported from spring-boot v4.2.0: core/spring-boot/src/test/java/org/springframework/boot/
// context/properties/source/ConfigurationPropertySourcesTests.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: AssertJ assertions become D asserts; one unittest per upstream @Test. Boot's
// `ConfigurationPropertySources.attach(environment)` is Flint's `ApplicationEnvironment`, which is built attached
// from config data: the attach tests run against it, with the upstream property sources as configuration property
// sources (the merged parent environment of attachShouldReattachInMergedSetup has no counterpart and is dropped).
// Not ported: environmentPropertyAccessWhenMutableShouldBeTolerable (@Disabled upstream, for manual testing).
module boot_tests.configuration_property_sources_test;

import flint.boot : ApplicationEnvironment;
import flint.boot.context.config : ConfigDataResult, Profiles;
import flint.boot.context.properties.source : ConfigurationPropertySource,
    MapConfigurationPropertySource, SystemEnvironmentPropertySource;

@safe:

private ApplicationEnvironment attached(ConfigurationPropertySource[] sources...)
{
    return new ApplicationEnvironment(new ConfigDataResult(sources.dup, new Profiles(null, [
        "default"
    ])));
}

@("attachShouldAddAdapterAtBeginning") unittest
{
    auto environment = attached(new SystemEnvironmentPropertySource(["SERVER_PORT": "1234"],
            "system"), new MapConfigurationPropertySource("config", [["server.port", "4568"]]));
    assert(environment.getProperty!string("server.port") == "1234");
}

@("attachShouldReattachInMergedSetup") unittest
{
    auto child = attached(new MapConfigurationPropertySource("config", [
            ["my.example_property", "1234"]
    ]));
    assert(child.getProperty!string("my.example-property") == "1234");
}

@("attachWhenAlreadyAttachedWithSameSourcesShouldReturnExistingInstance") unittest
{
    auto environment = attached(new SystemEnvironmentPropertySource(["SERVER_PORT": "1234"],
            "system"), new MapConfigurationPropertySource("config", [["server.port", "4568"]]));
    const first = environment.getConfigurationPropertySources();
    const second = environment.getConfigurationPropertySources();
    assert(first is second);
}

@("getWhenAttachedShouldReturnAttached") unittest
{
    auto environment = attached(new MapConfigurationPropertySource("test", [["a", "b"]]));
    const expectedSize = environment.getPropertySources().size();
    assert(environment.getConfigurationPropertySources().length == expectedSize);
}

@("environmentPropertyExpansionShouldWorkWhenAttached") unittest
{
    auto environment = attached(new MapConfigurationPropertySource("test", [
            ["fooBar", "Spring ${barBaz} ${bar-baz}"], ["barBaz", "Boot"]
    ]));
    assert(environment.getProperty!string("foo-bar") == "Spring Boot Boot");
}

version (FlintConfigurationPropertySourcesFrom)
{
    // Gap: ConfigurationPropertySources.get(Environment) and from(PropertySource...) over spring-core property
    // sources are not ported (Flint builds its configuration property sources from config data).
    import flint.boot.context.properties.source : ConfigurationPropertySources, SpringConfigurationPropertySource;
    import flint.core.env : Environment, MapPropertySource, MutablePropertySources,
        PropertySource, StandardEnvironment;
    import flint.engine.aot.any : Any;
    import flint.java.util : Collections;

    @("getWhenNotAttachedShouldReturnAdapted") unittest
    {
        auto environment = new StandardEnvironment();
        assert(ConfigurationPropertySources.get(environment).length > 0);
    }

    @("fromPropertySourceShouldReturnSpringConfigurationPropertySource") unittest
    {
        auto source = new MapPropertySource("foo", Collections.singletonMap("foo", Any.of("bar")));
        const configurationPropertySource = ConfigurationPropertySources.from(source)[0];
        assert(cast(SpringConfigurationPropertySource) configurationPropertySource !is null);
    }

    /// A property source over a whole Environment (the anonymous PropertySource of the upstream test).
    final class EnvironmentPropertySource : PropertySource
    {
        private StandardEnvironment environment;

        /// Part of the upstream test fixture.
        this(StandardEnvironment environment)
        {
            super("env", environment);
            this.environment = environment;
        }

        override Any getProperty(string key)
        {
            return Any.of(environment.getProperty!string(key));
        }
    }

    @("fromPropertySourceShouldFlattenPropertySources") unittest
    {
        auto environment = new StandardEnvironment();
        environment.getPropertySources().addFirst(new MapPropertySource("foo",
                Collections.singletonMap("foo", Any.of("bar"))));
        environment.getPropertySources().addFirst(new MapPropertySource("far",
                Collections.singletonMap("far", Any.of("far"))));
        auto sources = new MutablePropertySources();
        sources.addFirst(new EnvironmentPropertySource(environment));
        sources.addLast(new MapPropertySource("baz", Collections.singletonMap("baz", Any.of("barf"))));
        const configurationSources = ConfigurationPropertySources.from(sources);
        assert(configurationSources.length == 5);
    }
}

version (FlintConfigurationPropertyCaching)
{
    // Gap: Boot's configuration property caching (ConfigurationPropertyCaching, immutable property sources) is not
    // ported; Flint's sources are not cached.
    import core.time : MonoTime;
    import flint.boot.context.properties.source : ConfigurationPropertyCaching,
        ConfigurationPropertyName, ConfigurationPropertySources, ConfigurationPropertyState;
    import flint.core.env : MapPropertySource, PropertySourceInfo, StandardEnvironment;

    /// `TestPropertySource`: a map source that may declare itself immutable (`PropertySourceInfo`).
    final class TestPropertySource : MapPropertySource, PropertySourceInfo
    {
        private bool immutableSource;

        /// Part of the upstream test fixture.
        this(string name, string[string] map, bool immutableSource)
        {
            super(name, map);
            this.immutableSource = immutableSource;
        }

        /// Part of the upstream test fixture.
        bool isImmutable()
        {
            return immutableSource;
        }
    }

    private StandardEnvironment createPerformanceTestEnvironment(bool immutableSources)
    {
        import std.conv : to;

        auto environment = new StandardEnvironment();
        foreach (index; 0 .. 100)
        {
            string[string] map;
            foreach (i; 0 .. 1000)
            {
                const name = "test-" ~ index.to!string ~ "-property-" ~ i.to!string;
                map[name] = name ~ "-value";
            }
            environment.getPropertySources()
                .addLast(new TestPropertySource("test-" ~ index.to!string, map, immutableSources));
        }
        ConfigurationPropertySources.attach(environment);
        return environment;
    }

    private long testPropertySourcePerformance(StandardEnvironment environment)
    {
        import std.conv : to;

        const start = MonoTime.currTime;
        foreach (i; 0 .. 1000)
            environment.getProperty!string("missing" ~ i.to!string);
        const total = (MonoTime.currTime - start).total!"msecs";
        assert(environment.getProperty!string("test-10-property-80") == "test-10-property-80-value");
        return total;
    }

    @("environmentPropertyAccessWhenImmutableShouldBePerformant") unittest
    {
        const baseline = testPropertySourcePerformance(createPerformanceTestEnvironment(false));
        const immutable_ = testPropertySourcePerformance(createPerformanceTestEnvironment(true));
        assert(immutable_ < baseline / 2);
    }

    @("environmentPropertyAccessWhenMutableWithCacheShouldBePerformant") unittest
    {
        auto environment = createPerformanceTestEnvironment(false);
        const uncached = testPropertySourcePerformance(environment);
        ConfigurationPropertyCaching.get(environment).enable();
        const cached = testPropertySourcePerformance(environment);
        assert(cached < uncached / 2);
    }

    @("descendantOfPropertyAccessWhenMutableWithCacheShouldBePerformant") unittest
    {
        long descendantOfPerformance(StandardEnvironment environment)
        {
            auto sources = ConfigurationPropertySources.get(environment);
            auto missing = ConfigurationPropertyName.of("missing");
            const start = MonoTime.currTime;
            foreach (i; 0 .. 1000)
            {
                foreach (source; sources)
                    assert(source.containsDescendantOf(missing) == ConfigurationPropertyState.ABSENT);
            }
            return (MonoTime.currTime - start).total!"msecs";
        }

        auto environment = createPerformanceTestEnvironment(false);
        const baseline = descendantOfPerformance(environment);
        ConfigurationPropertyCaching.get(environment).enable();
        const cached = descendantOfPerformance(environment);
        assert(cached < baseline / 2);
    }
}

import boot_tests.support : RegisterTests;

mixin RegisterTests;
