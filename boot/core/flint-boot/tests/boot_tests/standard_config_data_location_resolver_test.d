// Ported from spring-boot v4.2.0: core/spring-boot/src/test/java/org/springframework/boot/context/config/
// StandardConfigDataLocationResolverTests.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: AssertJ assertions become D asserts. Flint resolves locations inside
// ConfigDataEnvironment, so `resolver.resolve(context, location)` is a run with `spring.config.location` set to the
// location, and the resolved resources are the descriptions of the property sources it loaded; `@WithResource`
// files are in-memory class path resources and `@ResourcesRoot` files are in-memory files under `root/`.
module boot_tests.standard_config_data_location_resolver_test;

import boot_tests.support : assertThrows;
import boot_tests.upstream_support : MemoryReader;
import flint.boot.context.config : ConfigDataEnvironment, ConfigDataEnvironmentOptions, ConfigDataResult;
import flint.java.lang : IllegalStateException;

@safe:

/// Load `location` from `files`, with `args` more command-line arguments.
private ConfigDataResult resolve(string location, string[string] files, string[] args = null)
{
    ConfigDataEnvironmentOptions options;
    options.reader = new MemoryReader(files);
    options.args = ["--spring.config.location=" ~ location] ~ args;
    return new ConfigDataEnvironment(options).processAndApply();
}

/// The resources the run loaded: the `[...]` description inside each config data source's name.
private string[] resources(ConfigDataResult result)
{
    import std.algorithm.searching : findSplitAfter, findSplitBefore, startsWith;

    string[] found;
    foreach (source; result.getSources())
    {
        const name = source.getUnderlyingSourceName();
        if (!name.startsWith("Config resource '"))
            continue;
        found ~= name["Config resource '".length .. $].findSplitBefore("' via location")[0];
    }
    return found;
}

version (FlintConfigDataLocationResolver)
{
    // Gap: there is no StandardConfigDataLocationResolver with Boot's location checks and messages (wildcard
    // rules, "Unable to load config data from ...", unknown prefixes).
    import flint.boot.context.config : ConfigDataLocation, StandardConfigDataLocationResolver;

    @("isResolvableAlwaysReturnsTrue") unittest
    {
        assert(new StandardConfigDataLocationResolver().isResolvable(null, ConfigDataLocation.of("test")));
    }

    @("resolveWhenLocationIsFileAndNoMatchingLoaderThrowsException") unittest
    {
        try
        {
            resolve("file:src/test/resources/configdata/properties/application.unknown",
                    ["src/test/resources/configdata/properties/application.unknown": "a=b"]);
            assert(false, "expected an IllegalStateException");
        }
        catch (IllegalStateException ex)
        {
            import std.algorithm.searching : startsWith;

            assert(ex.msg.startsWith("Unable to load config data from"));
            assert(ex.next !is null && ex.next.msg.startsWith("File extension is not known"));
        }
    }

    @("resolveWhenLocationHasUnknownPrefixAndNoMatchingLoaderThrowsException") unittest
    {
        try
        {
            resolve("typo:src/test/resources/configdata/properties/application.unknown", null);
            assert(false, "expected an IllegalStateException");
        }
        catch (IllegalStateException ex)
        {
            import std.algorithm.searching : startsWith;

            assert(ex.msg.startsWith("Unable to load config data from"));
            assert(ex.next !is null && ex.next.msg.startsWith("Incorrect ConfigDataLocationResolver chosen or file "
                    ~ "extension is not known to any PropertySourceLoader"));
        }
    }

    @("resolveWhenLocationWildcardIsSpecifiedForClasspathLocationThrowsException") unittest
    {
        assertThrows!IllegalStateException(() { resolve("classpath*:application.properties", null); },
                "Location 'classpath*:application.properties' cannot use classpath wildcards");
    }

    @("resolveWhenLocationWildcardIsNotBeforeLastSlashThrowsException") unittest
    {
        assertThrows!IllegalStateException(() { resolve("file:src/test/resources/*/config/", null); },
                "' must end with '*/'");
    }

    @("createWhenConfigNameHasWildcardThrowsException") unittest
    {
        assertThrows!IllegalStateException(() {
            resolve("optional:classpath:/", null, ["--spring.config.name=*/application"]);
        }, "' cannot contain '*'");
    }

    @("resolveWhenLocationHasMultipleWildcardsThrowsException") unittest
    {
        assertThrows!IllegalStateException(() { resolve("file:src/test/resources/config/**/", null); },
                "' cannot contain multiple wildcards");
    }
}

@("resolveWhenLocationIsDirectoryResolvesAllMatchingFilesInDirectory") unittest
{
    const loaded = resources(resolve("classpath:/configdata/", [
        "resources/configdata/application.properties": "a=b"
    ]));
    assert(loaded == ["class path resource [configdata/application.properties]"]);
}

@("resolveWhenLocationIsFileResolvesFile") unittest
{
    const loaded = resources(resolve("file:configdata/application.properties",
            ["configdata/application.properties": "a=b"]));
    assert(loaded == ["file [configdata/application.properties]"]);
}

private string[string] wildcardFiles()
{
    return [
        "root/config/0-empty/testproperties.properties": "",
        "root/config/1-first/testproperties.properties": "first.property=apple",
        "root/config/2-second/testproperties.properties": "second.property=ball",
        "root/config/nested/3-third/testproperties.properties": "third.property=shouldnotbefound"
    ];
}

@("resolveWhenLocationIsWildcardDirectoriesRestrictsToOneLevelDeep") unittest
{
    auto result = resolve("file:root/config/*/", wildcardFiles(), [
        "--spring.config.name=testproperties"
    ]);
    assert(result.getProperty("first.property") == "apple");
    assert(result.getProperty("second.property") == "ball");
    assert(result.getProperty("third.property") is null);
}

version (FlintEmptyConfigDataResources)
{
    // Gap: an empty config file yields no property source, so `0-empty` is missing from the resolved resources.
    @("resolveWhenLocationIsWildcardDirectoriesSortsAlphabeticallyBasedOnFixedPath") unittest
    {
        import std.algorithm.mutation : reverse;

        // Sources are highest precedence first; the resolution order is the reverse.
        const loaded = resources(resolve("file:root/config/*/", wildcardFiles(),
                ["--spring.config.name=testproperties"])).reverse;
        assert(loaded == [
            "file [root/config/0-empty/testproperties.properties]",
            "file [root/config/1-first/testproperties.properties]",
            "file [root/config/2-second/testproperties.properties]"
        ]);
    }
}

version (FlintWildcardFileLocations)
{
    // Gap: a wildcard file location (`config/*/testproperties.properties`) is read as a literal path.
    @("resolveWhenLocationIsWildcardFilesLoadsAllFilesThatMatch") unittest
    {
        auto result = resolve("file:root/config/*/testproperties.properties", wildcardFiles());
        assert(result.getProperty("first.property") == "apple");
        assert(result.getProperty("second.property") == "ball");
        assert(result.getProperty("third.property") is null);
    }
}

version (FlintConfigDataImport)
{
    // Gap: `spring.config.import` is not ported, so there are no locations relative to an importing resource.
    private string[string] parent()
    {
        return [
            "resources/configdata/properties/application.properties": "spring.config.import=other.properties",
            "resources/configdata/properties/other.properties": "other=true",
            "resources/config/specific.properties": "spring.config.import=nested/3-third/",
            "resources/config/nested/3-third/testproperties.properties": "nested=true",
            "resources/configdata/properties/application.other": "x=y"
        ];
    }

    @("resolveWhenLocationIsRelativeAndFileResolves") unittest
    {
        auto loaded = resources(resolve("classpath:configdata/properties/application.properties",
                parent(), ["--spring.config.name=other"]));
        assert(loaded[0] == "class path resource [configdata/properties/other.properties]");
    }

    @("resolveWhenLocationIsRelativeAndDirectoryResolves") unittest
    {
        auto loaded = resources(resolve("classpath:config/specific.properties", parent(),
                ["--spring.config.name=testproperties"]));
        assert(loaded[0] == "class path resource [config/nested/3-third/testproperties.properties]");
    }

    @("resolveWhenLocationIsRelativeAndNoMatchingLoaderThrowsException") unittest
    {
        auto files = parent();
        files["resources/configdata/properties/application.properties"] = "spring.config.import=application.other";
        assertThrows!IllegalStateException(() {
            resolve("classpath:configdata/properties/application.properties", files);
        }, "Unable to load config data from 'application.other'");
    }
}

version (FlintConfigDataLocationHints)
{
    // Gap: location hints (`[.properties]`, `[extension=.properties]`, `[encoding=utf-8]`) are not parsed.
    @("resolveWhenLocationUsesOptionalExtensionSyntaxResolves") unittest
    {
        auto result = resolve("classpath:/application-props-no-extension[.properties]",
                ["resources/application-props-no-extension": "withnoextension=test"]);
        assert(result.getProperty("withnoextension") == "test");
    }

    @("resolveWhenLocationUsesOptionalExplicitExtensionSyntaxResolves") unittest
    {
        auto result = resolve("classpath:/application-props-no-extension[extension=.properties]",
                ["resources/application-props-no-extension": "withnoextension=test"]);
        assert(result.getProperty("withnoextension") == "test");
    }

    @("resolveWhenLocationUsesEncodingSyntaxResolves") unittest
    {
        auto result = resolve("classpath:utf-8.properties[encoding=utf-8]",
                ["resources/utf-8.properties": "smiley=\U0001F603"]);
        assert(result.getProperty("smiley") == "\U0001F603");
    }
}

@("resolveWhenLocationContainsBracketsResolves") unittest
{
    auto result = resolve("classpath:config[a]/application.properties",
            ["resources/config[a]/application.properties": "brackets=test"]);
    assert(result.getProperty("brackets") == "test");
}

@("resolveProfileSpecificReturnsProfileSpecificFiles") unittest
{
    const loaded = resources(resolve("classpath:/",
            ["resources/application-dev.properties": "a=b"], ["--spring.profiles.active=dev"]));
    assert(loaded == ["class path resource [application-dev.properties]"]);
}

@("resolveProfileSpecificWhenLocationIsFileReturnsEmptyList") unittest
{
    const loaded = resources(resolve("classpath:/configdata/properties/application.properties",
            [
                "resources/configdata/properties/application.properties": "a=b",
                "resources/configdata/properties/application-dev.properties": "c=d"
    ], ["--spring.profiles.active=dev"]));
    assert(loaded == ["class path resource [configdata/properties/application.properties]"]);
}

@("resolveWhenOptionalAndLoaderIsUnknownShouldNotFail") unittest
{
    resolve("optional:some-unknown-loader:dummy.properties", null);
}

@("resolveWhenOptionalAndLoaderIsUnknownAndExtensionIsUnknownShouldNotFail") unittest
{
    resolve("optional:some-unknown-loader:dummy.some-unknown-extension", null);
}

@("resolveWhenOptionalAndExtensionIsUnknownShouldNotFail") unittest
{
    resolve("optional:file:dummy.some-unknown-extension", null);
}

import boot_tests.support : RegisterTests;

mixin RegisterTests;
