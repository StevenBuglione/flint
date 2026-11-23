// Ported from spring-boot v4.2.0: core/spring-boot/src/test/java/org/springframework/boot/context/config/
// ConfigDataEnvironmentTests.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: AssertJ assertions become D asserts; a @ParameterizedTest loops over its values.
// Flint's `ConfigDataEnvironment` takes its environment as options and returns the sources and profiles it decided
// (`ConfigDataResult`) instead of applying them to a mutable Environment: an Environment property is a command-line
// argument, `@WithResource` files are in-memory class path resources, and a contributor the test adds is an
// `application.properties` document.
module boot_tests.config_data_environment_test;

import boot_tests.support : assertThrows;
import boot_tests.upstream_support : MemoryReader;
import flint.boot.context.config : ConfigDataEnvironment, ConfigDataEnvironmentOptions,
    ConfigDataResult, InvalidConfigDataPropertyException;

@safe:

private ConfigDataResult processAndApply(string[string] files, string[] args = null,
        string[] additionalProfiles = null, string[string] defaultProperties = null)
{
    ConfigDataEnvironmentOptions options;
    options.reader = new MemoryReader(files);
    options.args = args;
    options.additionalProfiles = additionalProfiles;
    options.defaultProperties = defaultProperties;
    return new ConfigDataEnvironment(options).processAndApply();
}

version (FlintConfigDataContributors)
{
    // Gap: Flint's ConfigDataEnvironment has no contributor tree, location-resolver binder or
    // `spring.config.import`; it flattens location groups directly into property sources.
    import flint.boot.context.config : ConfigDataEnvironmentContributor, ImportPhase, Kind;
    import flint.core.env : MockPropertySource;

    @("createExposesEnvironmentBinderToConfigDataLocationResolvers") unittest
    {
        ConfigDataEnvironmentOptions options;
        options.args = ["--spring=boot"];
        auto configDataEnvironment = new ConfigDataEnvironment(options);
        auto binder = configDataEnvironment.getConfigDataLocationResolversBinder();
        assert(binder.bind!string("spring").get() == "boot");
    }

    @("createCreatesContributorsBasedOnExistingSources") unittest
    {
        auto propertySource1 = new MockPropertySource("p1");
        auto propertySource2 = new MockPropertySource("p2");
        auto propertySource3 = new MockPropertySource("p3");
        ConfigDataEnvironmentOptions options;
        options.propertySources = [propertySource1, propertySource2, propertySource3];
        auto children = new ConfigDataEnvironment(options).getContributors().getRoot()
            .getChildren(ImportPhase.BEFORE_PROFILE_ACTIVATION);
        Object[] wrapped;
        foreach (child; children)
        {
            if (child.getKind() == Kind.EXISTING)
                wrapped ~= child.getPropertySource();
        }
        assert(wrapped[1] is propertySource1 && wrapped[2] is propertySource2 && wrapped[3] is propertySource3);
    }

    @("createWhenHasDefaultPropertySourceMovesItToLastContributor") unittest
    {
        auto defaultPropertySource = new MockPropertySource("defaultProperties");
        auto propertySource1 = new MockPropertySource("p2");
        auto propertySource2 = new MockPropertySource("p3");
        ConfigDataEnvironmentOptions options;
        options.propertySources = [defaultPropertySource, propertySource1, propertySource2];
        auto children = new ConfigDataEnvironment(options).getContributors().getRoot()
            .getChildren(ImportPhase.BEFORE_PROFILE_ACTIVATION);
        Object[] wrapped;
        foreach (child; children)
        {
            if (child.getKind() == Kind.EXISTING)
                wrapped ~= child.getPropertySource();
        }
        assert(wrapped[1] is propertySource1 && wrapped[2] is propertySource2 && wrapped[3] is defaultPropertySource);
    }

    @("createCreatesInitialImportContributorsInCorrectOrder") unittest
    {
        ConfigDataEnvironmentOptions options;
        options.args = [
            "--spring.config.location=l1,l2", "--spring.config.additional-location=a1,a2",
            "--spring.config.import=i1,i2"
        ];
        auto children = new ConfigDataEnvironment(options).getContributors().getRoot()
            .getChildren(ImportPhase.BEFORE_PROFILE_ACTIVATION);
        string[] imports;
        foreach (child; children)
        {
            if (child.getKind() == Kind.INITIAL_IMPORT)
                imports ~= child.getImports().toString();
        }
        assert(imports == ["[i1, i2]", "[a2]", "[a1]", "[l2]", "[l1]"]);
    }
}

@("processAndApplyAddsImportedSourceToEnvironment") unittest
{
    auto result = processAndApply(["resources/application.properties": "spring=boot"]);
    assert(result.getProperty("spring") == "boot");
}

@("processAndApplyMovesDefaultPropertySourceToLast") unittest
{
    auto result = processAndApply(["config/application.properties": "a=b"],
            ["--spring.config.location=optional:file:./config/"], null, ["x": "y"]);
    auto sources = result.getSources();
    assert(sources[$ - 1].getUnderlyingSourceName() == "defaultProperties");
}

@("processAndApplySetsDefaultProfiles") unittest
{
    auto result = processAndApply([
        "resources/application.properties": "spring.profiles.default=one,two,three"
    ]);
    assert(result.getProfiles().getDefault() == ["one", "two", "three"]);
}

@("processAndApplySetsActiveProfiles") unittest
{
    auto result = processAndApply([
        "resources/application.properties": "spring.profiles.active=one,two,three"
    ]);
    assert(result.getProfiles().getActive() == ["one", "two", "three"]);
}

version (FlintConfigDataOptions)
{
    // Gap: config data has no options (ConfigData.Option.IGNORE_PROFILES): every document's profile properties
    // count.
    import flint.boot.context.config : ConfigDataOption;

    @("processAndApplyDoesNotSetProfilesFromIgnoreProfilesContributors") unittest
    {
        ConfigDataEnvironmentOptions options;
        options.reader = new MemoryReader([
            "resources/application.properties": "spring.profiles.active=test",
            "resources/ignored.properties": "spring.profiles.active=ignore1\nspring.profiles.include=ignore2"
        ]);
        options.args = [
            "--spring.config.additional-location=optional:classpath:/ignored.properties"
        ];
        options.configDataOptions = [
            "optional:classpath:/ignored.properties": [ConfigDataOption.IGNORE_PROFILES]
        ];
        auto result = new ConfigDataEnvironment(options).processAndApply();
        assert(result.getProfiles().getActive() == ["test"]);
    }

    @("processAndApplyDoesNotSetProfilesFromIgnoreProfilesContributorsWhenNoProfilesActive") unittest
    {
        ConfigDataEnvironmentOptions options;
        options.reader = new MemoryReader([
            "resources/application.properties": "spring=boot",
            "resources/ignored.properties": "spring.profiles.active=ignore1\nspring.profiles.include=ignore2"
        ]);
        options.args = [
            "--spring.config.additional-location=optional:classpath:/ignored.properties"
        ];
        options.configDataOptions = [
            "optional:classpath:/ignored.properties": [ConfigDataOption.IGNORE_PROFILES]
        ];
        auto result = new ConfigDataEnvironment(options).processAndApply();
        assert(result.getProfiles().getActive().length == 0);
        assert(result.getProperty("spring") == "boot");
    }
}

version (FlintInactiveConfigDataAccess)
{
    // Gap: a profile include in an inactive on-profile document fails with InvalidConfigDataPropertyException, not
    // Boot's InactiveConfigDataAccessException.
    import flint.boot.context.config : InactiveConfigDataAccessException;

    @("processAndApplyWhenHasProfileIncludeInProfileSpecificDocumentThrowsException") unittest
    {
        foreach (property; ["include", "include[0]"])
        {
            assertThrows!InactiveConfigDataAccessException(() {
                processAndApply([
                    "resources/application.properties": "spring.config.activate.on-profile=activate\n"
                    ~ "spring.profiles." ~ property ~ "=include"
                ]);
            });
        }
    }
}

@("processAndApplyIncludesProfilesFromSpringProfilesInclude") unittest
{
    foreach (property; ["spring.profiles.include", "spring.profiles.include[0]"])
    {
        auto result = processAndApply(["resources/application.properties": property ~ "=included"]);
        assert(result.getProfiles().getActive() == ["included"]);
    }
}

version (FlintInvalidPropertyInEnvironment)
{
    // Gap: an invalid `spring.profiles` property is only rejected in config data files, not in the environment
    // (command line, environment variables) the run starts from.
    @("processAndApplyWhenHasInvalidPropertyThrowsException") unittest
    {
        assertThrows!InvalidConfigDataPropertyException(() {
            processAndApply(null, ["--spring.profiles=a"]);
        });
    }
}

version (FlintConfigDataUpdateListener)
{
    // Gap: there is no ConfigDataEnvironmentUpdateListener (onPropertySourceAdded, onSetProfiles).
    import flint.boot.context.config : ConfigDataEnvironmentUpdateListener, Profiles;

    /// `TestConfigDataEnvironmentUpdateListener`.
    final class TestConfigDataEnvironmentUpdateListener : ConfigDataEnvironmentUpdateListener
    {
        /// Part of the upstream test fixture.
        string[] addedLocations;
        /// Part of the upstream test fixture.
        string[] addedResources;
        /// Part of the upstream test fixture.
        string[] addedValues;
        /// Part of the upstream test fixture.
        Profiles profiles;

        /// Part of the upstream test fixture.
        void onPropertySourceAdded(string propertyValue, string location, string resource)
        {
            addedValues ~= propertyValue;
            addedLocations ~= location;
            addedResources ~= resource;
        }

        /// Part of the upstream test fixture.
        void onSetProfiles(Profiles profiles)
        {
            this.profiles = profiles;
        }
    }

    @("processAndApplyWhenHasListenerCallsOnPropertySourceAdded") unittest
    {
        import std.algorithm.searching : canFind;

        auto listener = new TestConfigDataEnvironmentUpdateListener;
        ConfigDataEnvironmentOptions options;
        options.reader = new MemoryReader(["resources/custom/config.properties": "spring=boot"]);
        options.args = ["--spring.config.location=classpath:custom/config.properties"];
        options.listener = listener;
        new ConfigDataEnvironment(options).processAndApply();
        assert(listener.addedValues == ["boot"]);
        assert(listener.addedLocations == ["classpath:custom/config.properties"]);
        assert(listener.addedResources[0].canFind("class path resource"));
        assert(listener.addedResources[0].canFind("custom/config.properties"));
    }

    @("processAndApplyWhenHasListenerCallsOnSetProfiles") unittest
    {
        auto listener = new TestConfigDataEnvironmentUpdateListener;
        ConfigDataEnvironmentOptions options;
        options.reader = new MemoryReader([
            "resources/application.properties": "spring.profiles.active=one,two,three"
        ]);
        options.listener = listener;
        new ConfigDataEnvironment(options).processAndApply();
        assert(listener.profiles !is null);
        assert(listener.profiles.getActive() == ["one", "two", "three"]);
    }
}

@("processAndApplyWhenExternalFileConfigOverridesProfileSpecificClasspathConfig") unittest
{
    // gh-49724
    auto result = processAndApply([
        "resources/application-local.properties": "test.property=classpath-local",
        "ext/application.properties": "test.property=file-default\n"
    ], ["--spring.config.location=optional:classpath:/,optional:file:ext/"], ["local"]);
    assert(result.getProperty("test.property") == "file-default");
}

import boot_tests.support : RegisterTests;

mixin RegisterTests;
