// Ported from spring-boot v4.2.0: core/spring-boot/src/test/java/org/springframework/boot/context/config/ConfigDataEnvironmentPostProcessorIntegrationTests.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: each test keeps its upstream name and behaviour; the class-path and file resources
// the upstream tests read are given in memory, with `flint.*` keys, and system properties become command-line
// arguments (a native binary has no JVM system properties).
module boot_tests.config_data_test;

import boot_tests.support : assertThrows;
import flint.boot.context.config : ConfigDataEnvironment, ConfigDataEnvironmentOptions,
    ConfigDataLocationNotFoundException, ConfigDataResourceReader, ConfigDataResult,
    InvalidConfigDataPropertyException;

@safe:

private final class MemoryReader : ConfigDataResourceReader
{
    string[string] files;

    this(string[string] files)
    {
        this.files = files;
    }

    const(ubyte)[] read(string path)
    {
        if (auto content = path in files)
            return cast(const(ubyte)[])*content;
        return null;
    }

    string[] subdirectories(string directory)
    {
        import std.algorithm.searching : startsWith;
        import std.algorithm.sorting : sort;
        import std.string : indexOf;

        string[] result;
        foreach (path; files.keys)
        {
            if (!path.startsWith(directory ~ "/"))
                continue;
            const rest = path[directory.length + 1 .. $];
            const slash = rest.indexOf('/');
            if (slash > 0)
            {
                const sub = directory ~ "/" ~ rest[0 .. slash];
                bool seen;
                foreach (existing; result)
                    seen = seen || existing == sub;
                if (!seen)
                    result ~= sub;
            }
        }
        result.sort();
        return result;
    }

    bool directoryExists(string directory)
    {
        import std.algorithm.searching : startsWith;

        foreach (path; files.keys)
        {
            if (path.startsWith(directory ~ "/"))
                return true;
        }
        return false;
    }
}

private ConfigDataResult run(string[string] files, string[] args = null,
        string[string] environment = null, string[] additionalProfiles = null, string[string] defaults = null)
{
    ConfigDataEnvironmentOptions options;
    options.args = args;
    options.environment = environment;
    options.additionalProfiles = additionalProfiles;
    options.defaultProperties = defaults;
    options.reader = new MemoryReader(files);
    return new ConfigDataEnvironment(options).processAndApply();
}

@("runLoadsApplicationPropertiesOnClasspath") unittest
{
    auto result = run(["resources/application.properties": "foo=bucket\n"]);
    assert(result.getProperty("foo") == "bucket");
}

@("runLoadsApplicationYamlOnClasspath") unittest
{
    auto result = run(["resources/application.yaml": "yamlkey: yamlvalue\n"]);
    assert(result.getProperty("yamlkey") == "yamlvalue");
}

@("runLoadsFileWithCustomName") unittest
{
    auto result = run([
        "resources/moreproperties.properties": "the.property=fromotherpropertiesfile\n"
    ], ["--flint.config.name=moreproperties"]);
    assert(result.getProperty("the.property") == "fromotherpropertiesfile");
}

@("runWhenNoActiveProfilesLoadsDefaultProfileFile") unittest
{
    auto result = run([
        "resources/application.properties": "my.property=fromapplicationproperties\n",
        "resources/application-default.properties": "my.property=fromdefaultpropertiesfile\n"
    ]);
    assert(result.getProperty("my.property") == "fromdefaultpropertiesfile");
    assert(result.getProfiles().getActive().length == 0);
    assert(result.getProfiles().getDefault() == ["default"]);
}

@("runWhenHasCustomDefaultProfileLoadsDefaultProfileFile") unittest
{
    auto result = run([
        "resources/application-thedefault.properties": "the.property=fromdefaultprofile\n"
    ], ["--flint.profiles.default=thedefault"]);
    assert(result.getProperty("the.property") == "fromdefaultprofile");
}

@("runWhenHasLocalFileLoadsWithLocalFileTakingPrecedenceOverClasspath") unittest
{
    auto result = run([
        "resources/application.properties": "my.property=fromapplicationproperties\n",
        "application.properties": "my.property=fromlocalfile\n"
    ]);
    assert(result.getProperty("my.property") == "fromlocalfile");
}

@("runWhenHasSystemPropertyLoadsWithSystemPropertyTakingPrecedence") unittest
{
    auto result = run([
        "resources/application.properties": "my.property=fromapplicationproperties\n"
    ], ["--my.property=fromsystem"]);
    assert(result.getProperty("my.property") == "fromsystem");
}

@("runWhenHasDefaultPropertiesIncludesDefaultPropertiesLast") unittest
{
    auto result = run([
        "resources/application.properties": "my.property=fromapplicationproperties\n"
    ], null, null, null, [
        "my.property": "fromdefaultproperties",
        "my.other": "fromdefaultproperties"
    ]);
    assert(result.getProperty("my.property") == "fromapplicationproperties");
    assert(result.getProperty("my.other") == "fromdefaultproperties");
    assert(result.getSources()[$ - 1].getUnderlyingSourceName() == "defaultProperties");
}

@("runWhenHasDefaultPropertiesWithConfigNameLoadsExpectedProperties") unittest
{
    auto result = run(["resources/testproperties.properties": "the.property=frompropertiesfile\n"],
            null, null, null, ["flint.config.name": "testproperties"]);
    assert(result.getProperty("the.property") == "frompropertiesfile");
}

@("runWhenHasActiveProfilesFromDefaultPropertiesAndFileLoadsWithActiveProfilesFromFileTakingPrecedence") unittest
{
    auto result = run([
        "resources/application.properties": "flint.profiles.active=dev\n",
        "resources/application-dev.properties": "my.property=fromdevpropertiesfile\n",
        "resources/application-other.properties": "my.property=fromotherpropertiesfile\n"
    ], null, null, null, ["flint.profiles.active": "other"]);
    assert(result.getProfiles().getActive() == ["dev"]);
    assert(result.getProperty("my.property") == "fromdevpropertiesfile");
}

@("runWhenProgrammaticallySetProfilesLoadsWithSetProfilesTakePrecedenceOverDefaultProfile") unittest
{
    auto result = run([
        "resources/application-default.properties": "my.property=fromdefaultpropertiesfile\n",
        "resources/application-other.properties": "my.property=fromotherpropertiesfile\n"
    ], null, null, ["other"]);
    assert(result.getProfiles().getActive() == ["other"]);
    assert(result.getProperty("my.property") == "fromotherpropertiesfile");
}

@("runWhenTwoProfilesSetProgrammaticallyLoadsWithPreservedProfileOrder") unittest
{
    auto result = run([
        "resources/application-other.properties": "my.property=fromotherpropertiesfile\n",
        "resources/application-dev.properties": "my.property=fromdevpropertiesfile\n"
    ], null, null, ["other", "dev"]);
    assert(result.getProfiles().getActive() == ["other", "dev"]);
    assert(result.getProperty("my.property") == "fromdevpropertiesfile");
}

@("runWhenDuplicateProfileSetProgrammaticallyAndViaPropertyLoadsWithProfiles") unittest
{
    auto result = run(null, ["--flint.profiles.active=dev,other"], null, ["dev"]);
    assert(result.getProfiles().getActive() == ["dev", "other"]);
}

@("runWhenProfilesActivatedViaBracketNotationSetsProfiles") unittest
{
    auto result = run(null, ["--flint.profiles.active[0]=dev", "--flint.profiles.active[1]=other"]);
    assert(result.getProfiles().getActive() == ["dev", "other"]);
}

@("runWhenProfileActivatedViaSystemEnvironmentVariableWithPrefix") unittest
{
    // Upstream sets SPRING_PROFILES_ACTIVE under a prefix; Flint's own variable is FLINT_PROFILES_ACTIVE, and the
    // SPRING_ spelling is accepted as its alias.
    auto files = ["resources/application-dev.properties": "my.property=fromdevpropertiesfile\n"];
    auto flintResult = run(files, null, ["FLINT_PROFILES_ACTIVE": "dev"]);
    assert(flintResult.getProfiles().getActive() == ["dev"]);
    assert(flintResult.getProperty("my.property") == "fromdevpropertiesfile");
    auto springResult = run(files, null, ["SPRING_PROFILES_ACTIVE": "dev"]);
    assert(springResult.getProfiles().getActive() == ["dev"]);
}

@("loadWhenHasConfigLocationAsFile") unittest
{
    auto result = run(["specific.properties": "my.property=fromspecificlocation\n"],
            ["--flint.config.location=file:specific.properties"]);
    assert(result.getProperty("my.property") == "fromspecificlocation");
}

@("loadWhenHasRelativeConfigLocationUsesFileLocation") unittest
{
    auto result = run(["config/specific.properties": "my.property=fromspecificlocation\n"],
            ["--flint.config.location=config/specific.properties"]);
    assert(result.getProperty("my.property") == "fromspecificlocation");
}

@("loadWhenCustomDefaultProfileAndActiveFromPreviousSourceDoesNotActivateDefault") unittest
{
    auto result = run(["resources/application-customdefault.properties": "customdefault=true\n"],
            ["--flint.profiles.default=customdefault", "--flint.profiles.active=dev"]);
    assert(result.getProfiles().getActive() == ["dev"]);
    assert(result.getProperty("customdefault") is null);
}

@("runWhenConfigLocationHasUnknownFileExtensionFailsFast") unittest
{
    import flint.java.lang : IllegalStateException;

    assertThrows!IllegalStateException(() {
        run(["application.unknown": "x=y\n"], ["--flint.config.location=file:application.unknown"]);
    }, "is not known to any PropertySourceLoader");
}

@("runWhenConfigLocationHasOptionalMissingDirectoryContinuesToLoad") unittest
{
    auto result = run(["resources/application.properties": "foo=bucket\n"],
            ["--flint.config.additional-location=optional:file:missing/"]);
    assert(result.getProperty("foo") == "bucket");
}

@("runWhenConfigLocationHasNonOptionalMissingFileDirectoryThrowsResourceNotFoundException") unittest
{
    assertThrows!ConfigDataLocationNotFoundException(() {
        run(null, ["--flint.config.location=file:missing/"]);
    }, "does not exist");
}

@("runWhenUsingInvalidPropertyThrowsException") unittest
{
    assertThrows!InvalidConfigDataPropertyException(() {
        run([
            "resources/application.yaml": "a: b\n---\nflint:\n  config:\n    activate:\n      on-profile: dev\n"
            ~ "  profiles:\n    active: prod\n"
        ], ["--flint.profiles.active=dev"]);
    }, "is invalid in a profile specific resource");
}

@("runWhenOptionalWildcardDirectoryHasNoSubdirectoriesDoesNotThrow") unittest
{
    auto result = run(["resources/application.properties": "foo=bucket\n"]);
    assert(result.getProperty("foo") == "bucket");
}

// Flint tests for the rest of Phase 1's config data behaviour.

@("flint.multiDocumentOnProfile") unittest
{
    enum yaml = "server:\n  port: 8080\n---\nflint:\n  config:\n    activate:\n      on-profile: prod\nserver:\n"
        ~ "  port: 80\n---\nspring:\n  config:\n    activate:\n      on-profile: \"!prod\"\ngreeting: dev\n";
    auto defaults = run(["resources/application.yaml": yaml]);
    assert(defaults.getProperty("server.port") == "8080");
    assert(defaults.getProperty("greeting") == "dev");
    auto prod = run(["resources/application.yaml": yaml], ["--flint.profiles.active=prod"]);
    assert(prod.getProperty("server.port") == "80");
    assert(prod.getProperty("greeting") is null);
}

@("flint.springKeysAreAliases") unittest
{
    auto result = run([
        "resources/application.properties": "spring.application.name=demo\nspring.profiles.active=x\n"
    ]);
    assert(result.getProperty("flint.application.name") == "demo");
    assert(result.getProfiles().getActive() == ["x"]);
}

@("flint.flintKeyWinsOverSpringKeyInOneSource") unittest
{
    auto result = run(
            [
        "resources/application.properties": "spring.application.name=spring\nflint.application.name=flint\n"
    ]);
    assert(result.getProperty("flint.application.name") == "flint");
}

@("flint.profileGroupsAndIncludes") unittest
{
    auto result = run([
        "resources/application.yaml": "flint:\n  profiles:\n    include: base\n    group:\n      prod: [db, metrics]\n"
    ], ["--flint.profiles.active=prod"]);
    assert(result.getProfiles().getActive() == ["base", "prod", "db", "metrics"]);
}

@("flint.propertiesWinOverYamlAtOneLocation") unittest
{
    auto result = run([
        "resources/application.yaml": "key: yaml\n",
        "resources/application.properties": "key=properties\n"
    ]);
    assert(result.getProperty("key") == "properties");
}

@("flint.configDirectoryOverridesRootAndWildcardDirectories") unittest
{
    auto result = run([
        "resources/application.properties": "a=classpath\nb=classpath\nc=classpath\n",
        "resources/config/application.properties": "a=classpath-config\n",
        "config/application.properties": "b=file-config\n",
        "config/extra/application.properties": "c=file-config-extra\n"
    ]);
    assert(result.getProperty("a") == "classpath-config");
    assert(result.getProperty("b") == "file-config");
    assert(result.getProperty("c") == "file-config-extra");
}

@("flint.locationGroupsOrderProfileFiles") unittest
{
    // The documented `prod,live` example: with `;` both locations are one group, so live wins in both.
    string[string] files = [
        "cfg/application-live.properties": "who=cfg-live\n",
        "ext/application-live.properties": "who=ext-live\n",
        "ext/application-prod.properties": "who=ext-prod\nonly=ext-prod\n"
    ];
    auto grouped = run(files, [
        "--flint.config.location=file:cfg/;file:ext/", "--flint.profiles.active=prod,live"
    ]);
    assert(grouped.getProperty("who") == "ext-live");
    auto separate = run(files, [
        "--flint.config.location=file:cfg/,file:ext/", "--flint.profiles.active=prod,live"
    ]);
    assert(separate.getProperty("who") == "ext-live");
    assert(separate.getProperty("only") == "ext-prod");
}

@("flint.origins") unittest
{
    import flint.boot.context.properties.source : ConfigurationPropertyName, ConfigurationPropertySources;

    auto result = run(["resources/application.yaml": "server:\n  port: 9000\n"]);
    auto property = ConfigurationPropertySources.find(result.getSources(), ConfigurationPropertyName.of("server.port"));
    assert(property.getOrigin() == "class path resource [application.yaml] - 2:9", property.getOrigin());
}

import boot_tests.support : RegisterTests;

mixin RegisterTests;
