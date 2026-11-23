// Ported from spring-boot v4.2.0: core/spring-boot/src/test/java/org/springframework/boot/context/config/
// ConfigDataPropertiesTests.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: Flint keeps a document's `spring.config.activate.*` properties inside
// ConfigDataEnvironment, so `ConfigDataProperties.isActive(context)` is checked by loading the document: a second
// `#---` document sets a marker that is visible only when the document is active. The activation context's
// profiles are `a,b,c` (createTestProfiles) or none; Flint detects no cloud platform, so a context with one is
// gated.
module boot_tests.config_data_properties_test;

import boot_tests.upstream_support : MemoryReader;
import flint.boot.context.config : ConfigDataEnvironment, ConfigDataEnvironmentOptions;

@safe:

/// Whether a document with `activate` (`spring.config.activate.*` lines) is active, with profiles a,b,c active when
/// `testProfiles` (createTestProfiles) and none otherwise.
private bool isActive(string activate, bool testProfiles)
{
    ConfigDataEnvironmentOptions options;
    options.reader = new MemoryReader(
            ["resources/application.properties": "marker=base\n#---\nmarker=document\n" ~ activate]);
    if (testProfiles)
        options.additionalProfiles = ["a", "b", "c"];
    return new ConfigDataEnvironment(options).processAndApply().getProperty("marker") == "document";
}

private enum onCloudPlatform = "spring.config.activate.on-cloud-platform=";
private enum onProfile = "spring.config.activate.on-profile=";

version (FlintConfigDataImport)
{
    // Gap: `spring.config.import` and ConfigDataProperties' imports are not ported.
    import flint.boot.context.config : ConfigDataLocation, ConfigDataProperties;
    import flint.boot.context.properties.bind : Binder;
    import flint.boot.context.properties.source : ConfigurationPropertySource, MapConfigurationPropertySource;

    @("getImportsReturnsImports") unittest
    {
        auto l1 = ConfigDataLocation.of("one");
        auto l2 = ConfigDataLocation.of("two");
        auto l3 = ConfigDataLocation.of("three");
        auto properties = new ConfigDataProperties([l1, l2, l3], null);
        assert(properties.getImports() == [l1, l2, l3]);
    }

    @("getImportsWhenImportsAreNullReturnsEmptyList") unittest
    {
        auto properties = new ConfigDataProperties(null, null);
        assert(properties.getImports().length == 0);
    }

    @("getImportOriginWhenCommaListReturnsOrigin") unittest
    {
        auto source = new MapConfigurationPropertySource("source", [
            ["spring.config.import", "one,two,three"]
        ]);
        auto properties = ConfigDataProperties.get(new Binder([
            cast(ConfigurationPropertySource) source
        ]));
        assert(properties !is null);
        assert(properties.getImports()[1].getOrigin()
                .toString() == `"spring.config.import" from property source "source"`);
    }

    @("getImportOriginWhenBracketListReturnsOrigin") unittest
    {
        auto source = new MapConfigurationPropertySource("source", [
            ["spring.config.import[0]", "one"], ["spring.config.import[1]", "two"],
            ["spring.config.import[2]", "three"]
        ]);
        auto properties = ConfigDataProperties.get(new Binder([
            cast(ConfigurationPropertySource) source
        ]));
        assert(properties !is null);
        assert(properties.getImports()[1].getOrigin()
                .toString() == `"spring.config.import[1]" from property source "source"`);
    }
}

@("isActiveWhenNullCloudPlatformAgainstNullCloudPlatform") unittest
{
    assert(isActive("", false));
}

version (FlintCloudPlatform)
{
    // Gap: Flint detects no cloud platform, so the activation context never has one and a document with
    // `on-cloud-platform` (even `none`) is never active.
    import flint.boot.cloud : CloudPlatform;

    /// isActive with the activation context's cloud platform set to `platform`.
    private bool isActiveOn(CloudPlatform platform, string activate, bool testProfiles)
    {
        ConfigDataEnvironmentOptions options;
        options.reader = new MemoryReader(
                [
            "resources/application.properties": "marker=base\n#---\nmarker=document\n" ~ activate
        ]);
        if (testProfiles)
            options.additionalProfiles = ["a", "b", "c"];
        options.cloudPlatform = platform;
        return new ConfigDataEnvironment(options).processAndApply().getProperty("marker") == "document";
    }

    @("isActiveWhenNullCloudPlatformAgainstSpecificCloudPlatform") unittest
    {
        assert(isActiveOn(CloudPlatform.KUBERNETES, "", false));
    }

    @("isActiveWhenSpecificCloudPlatformAgainstMatchingSpecificCloudPlatform") unittest
    {
        assert(isActiveOn(CloudPlatform.KUBERNETES, onCloudPlatform ~ "kubernetes", false));
    }

    @("isActiveWhenSpecificCloudPlatformAgainstDifferentSpecificCloudPlatform") unittest
    {
        assert(!isActiveOn(CloudPlatform.HEROKU, onCloudPlatform ~ "kubernetes", false));
    }

    @("isActiveWhenNoneCloudPlatformAgainstNullCloudPlatform") unittest
    {
        assert(isActive(onCloudPlatform ~ "none", false));
    }

    @("isActiveAgainstBoundData") unittest
    {
        assert(isActiveOn(CloudPlatform.KUBERNETES, onCloudPlatform ~ "kubernetes\n" ~ onProfile ~ "a | b", true));
    }

    @("isActiveAgainstBoundDataWhenProfilesDontMatch") unittest
    {
        assert(!isActiveOn(CloudPlatform.KUBERNETES, onCloudPlatform ~ "kubernetes\n" ~ onProfile ~ "x | z", true));
    }

    @("isActiveAgainstBoundDataWhenCloudPlatformDoesntMatch") unittest
    {
        assert(!isActiveOn(CloudPlatform.KUBERNETES, onCloudPlatform ~ "cloud-foundry\n" ~ onProfile ~ "a | b", true));
    }
}

@("isActiveWhenSpecificCloudPlatformAgainstNullCloudPlatform") unittest
{
    assert(!isActive(onCloudPlatform ~ "kubernetes", false));
}

@("isActiveWhenNullProfilesAgainstNullProfiles") unittest
{
    assert(isActive("", false));
}

@("isActiveWhenNullProfilesAgainstSpecificProfiles") unittest
{
    assert(isActive("", true));
}

@("isActiveWhenSpecificProfilesAgainstNullProfiles") unittest
{
    assert(!isActive(onProfile ~ "a", false));
}

@("isActiveWhenSpecificProfilesAgainstMatchingSpecificProfiles") unittest
{
    assert(isActive(onProfile ~ "a", true));
}

@("isActiveWhenSpecificProfilesAgainstMissingSpecificProfiles") unittest
{
    assert(!isActive(onProfile ~ "x", true));
}

@("isActiveWhenProfileExpressionAgainstSpecificProfiles") unittest
{
    assert(isActive(onProfile ~ "a | b", true));
}

@("isActiveWhenActivateIsNull") unittest
{
    assert(isActive("", true));
}

@("isActiveAgainstBoundDataWhenProfilesMatchCommaSeparatedList") unittest
{
    assert(isActive(onProfile ~ "a&b,nonexistent", true));
}

import boot_tests.support : RegisterTests;

mixin RegisterTests;
