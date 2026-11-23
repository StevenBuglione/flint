// Ported from spring-boot v4.2.0: core/spring-boot/src/test/java/org/springframework/boot/context/config/
// ConfigDataEnvironmentPostProcessorIntegrationTests.java: the tests boot_tests/config_data_test.d does not port.
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: each test keeps its upstream name and behaviour; `@WithResource` files are
// in-memory class path resources (`resources/...`), `@TempDir` files are in-memory files, a custom ResourceLoader is
// a `ConfigDataResourceReader`, `setAdditionalProfiles` is the programmatic additional profiles, an environment
// property source is a command-line argument or a default property, and `ConfigDataResourceNotFoundException` is
// Flint's `ConfigDataLocationNotFoundException`. Placeholders in a value are resolved by binding it.
module boot_tests.config_data_upstream_test;

import boot_tests.support : assertThrows;
import boot_tests.upstream_support : MemoryReader;
import flint.boot.context.config : ConfigDataEnvironment, ConfigDataEnvironmentOptions,
    ConfigDataLocationNotFoundException, ConfigDataResourceReader, ConfigDataResult,
    InvalidConfigDataPropertyException;

@safe:

private ConfigDataResult run(string[string] files, string[] args = null,
        string[] additionalProfiles = null, string[string] defaults = null)
{
    return runWith(new MemoryReader(files), args, additionalProfiles, defaults);
}

private ConfigDataResult runWith(ConfigDataResourceReader reader, string[] args = null,
        string[] additionalProfiles = null, string[string] defaults = null)
{
    ConfigDataEnvironmentOptions options;
    options.args = args;
    options.additionalProfiles = additionalProfiles;
    options.defaultProperties = defaults;
    options.reader = reader;
    return new ConfigDataEnvironment(options).processAndApply();
}

/// `environment.getProperty(name)`: the value with its placeholders resolved, or `null`.
private string property(ConfigDataResult result, string name)
{
    import flint.boot.context.properties.bind : Binder;

    return new Binder(result.getSources()).bind!string(name).orElse(null);
}

/// In-memory resources plus directories that exist without files (`@WithResourceDirectory`, an empty `@TempDir`).
final class DirectoryReader : ConfigDataResourceReader
{
    private MemoryReader files;
    private string[] directories;

    /// Part of the upstream test fixture.
    this(string[string] files, string[] directories)
    {
        this.files = new MemoryReader(files);
        this.directories = directories;
    }

    /// Part of the upstream test fixture.
    const(ubyte)[] read(string path)
    {
        return files.read(path);
    }

    /// Part of the upstream test fixture.
    string[] subdirectories(string directory)
    {
        import std.algorithm.searching : startsWith;
        import std.string : indexOf;

        string[] result = files.subdirectories(directory);
        foreach (candidate; directories)
        {
            if (candidate.startsWith(directory ~ "/") && candidate[directory.length + 1 .. $].indexOf('/') < 0)
                result ~= candidate;
        }
        return result;
    }

    /// Part of the upstream test fixture.
    bool directoryExists(string directory)
    {
        foreach (candidate; directories)
        {
            if (candidate == directory)
                return true;
        }
        return files.directoryExists(directory);
    }
}

@("runWhenUsingCustomResourceLoader") unittest
{
    static final class CustomResourceLoader : ConfigDataResourceReader
    {
        const(ubyte)[] read(string path)
        {
            if (path == "resources/custom.properties")
                return cast(const(ubyte)[]) "the.property: fromcustom";
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

    auto result = runWith(new CustomResourceLoader, ["--spring.config.name=custom"]);
    assert(result.getProperty("the.property") == "fromcustom");
}

@("runWhenPropertiesAndYamlShouldPreferProperties") unittest
{
    auto result = run([
        "resources/application.properties": "duplicate=properties\nonly-properties = properties\n",
        "resources/application.yaml": "duplicate: yaml\nonly-yaml: yaml\n"
    ]);
    assert(result.getProperty("duplicate") == "properties");
    assert(result.getProperty("only-properties") == "properties");
    assert(result.getProperty("only-yaml") == "yaml");
}

@("runWhenMultipleCustomNamesLoadsEachName") unittest
{
    auto result = run([
        "resources/moreproperties.properties": "the.property=more\nonly.more=more\n",
        "resources/testproperties.properties": "the.property=test\nonly.test=test\n"
    ], ["--spring.config.name=moreproperties,testproperties"]);
    assert(result.getProperty("the.property") == "test");
    assert(result.getProperty("only.more") == "more");
    assert(result.getProperty("only.test") == "test");
}

private string[string] applicationAndTestProperties()
{
    return [
        "resources/application.properties": "foo=bucket\nmy.property=fromapplicationproperties\n",
        "resources/testproperties.properties": "my.property=frompropertiesfile\nthe.property=frompropertiesfile\n"
    ];
}

@("runWhenHasCustomSpringConfigLocationLoadsAllFromSpecifiedLocation") unittest
{
    auto result = run(applicationAndTestProperties(),
            [
                "--spring.config.location=classpath:application.properties,classpath:testproperties.properties"
    ]);
    assert(result.getProperty("the.property") == "frompropertiesfile");
    assert(result.getProperty("my.property") == "frompropertiesfile");
    assert(result.getProperty("foo") == "bucket");
}

@("runWhenOneCustomOptionalLocationDoesNotExistLoadsOthers") unittest
{
    auto result = run(applicationAndTestProperties(),
            [
                "--spring.config.location=classpath:application.properties,classpath:testproperties.properties,"
                ~ "optional:classpath:nonexistent.properties"
    ]);
    assert(result.getProperty("my.property") == "frompropertiesfile");
    assert(result.getProperty("foo") == "bucket");
}

private enum mandatoryImportInProd = "---\nmy:\n  property: fromyamlfile\n---\n"
    ~ "spring.config.activate.on-profile: prod\nspring.config.import: file:./non-existent.yml\n";

@("runWhenProfileSpecificMandatoryLocationDoesNotExistShouldNotFail") unittest
{
    auto result = run(["resources/application.yml": mandatoryImportInProd]);
    assert(result.getProperty("my.property") == "fromyamlfile");
}

@("runWhenImportWithProfileVariantOrdersPropertySourcesCorrectly") unittest
{
    // gh-26858
    auto result = run([
        "resources/application.properties": "spring.config.import=classpath:imported.properties\n"
        ~ "my.value=application.properties\n",
        "resources/imported.properties": "my.value=imported.properties",
        "resources/application-dev.properties": "my.value=application-dev.properties"
    ], null, ["dev"]);
    assert(result.getProperty("my.value") == "application-dev.properties");
}

version (FlintConfigDataImport)
{
    // Gap: `spring.config.import` is not ported (imports are ignored).
    @("runWhenProfileSpecificMandatoryLocationDoesNotExistShouldFailWhenProfileActive") unittest
    {
        assertThrows!ConfigDataLocationNotFoundException(() {
            run(["resources/application.yml": mandatoryImportInProd], null, ["prod"]);
        }, "non-existent.yml");
    }

    @("runWhenHasImportPropertyWithProfileSpecificFileTakesPrecedence") unittest
    {
        auto result = run([
            "resources/testproperties-1.properties": "my.property=fromtestproperties-1.properties\n",
            "resources/testproperties-1-myprofile.properties": "my.property="
            ~ "fromtestproperties-1-myprofile.properties\n",
            "resources/testproperties-2.properties": "my.property=fromtestproperties-2.properties\n"
        ], [
            "--spring.config.import=classpath:testproperties-1.properties,classpath:testproperties-2.properties",
            "--spring.profiles.active=myprofile"
        ]);
        assert(result.getProperty("my.property") == "fromtestproperties-1-myprofile.properties");
    }

    @("runWhenImportUsesPlaceholder") unittest
    {
        auto result = run([
            "resources/application.properties": "my.import=imported\n"
            ~ "spring.config.import=classpath:${my.import}.properties\n",
            "resources/imported.properties": "my.value=iwasimported"
        ]);
        assert(result.getProperty("my.value") == "iwasimported");
    }

    @("runWhenImportFromEarlierDocumentUsesPlaceholder") unittest
    {
        auto result = run([
            "resources/application.properties": "my.import=imported\n#---\n"
            ~ "spring.config.import=classpath:${my.import}.properties\n",
            "resources/imported.properties": "my.value=iwasimported"
        ]);
        assert(result.getProperty("my.value") == "iwasimported");
    }

    @("runWhenImportWithProfileVariantAndDirectProfileImportOrdersPropertySourcesCorrectly") unittest
    {
        auto result = run([
            "resources/application.properties": "spring.config.import=classpath:imported.properties\n"
            ~ "my.value=application.properties\n",
            "resources/imported.properties": "my.value=imported.properties",
            "resources/imported-dev.properties": "my.value=imported-dev.properties",
            "resources/application-dev.properties": "spring.config.import=imported-dev.properties\n"
            ~ "my.value=application-dev.properties"
        ], null, ["dev"]);
        assert(result.getProperty("my.value") == "imported-dev.properties");
    }

    @("runWhenHasPropertyInProfileDocumentThrowsException") unittest
    {
        import flint.boot.context.properties.bind : BindException;

        assertThrows!BindException(() {
            run([
                "resources/application.properties": "my.import=application-import-with-placeholder-imported\n"
                ~ "#---\nspring.config.import=classpath:org/springframework/boot/context/config/${my.import}"
                ~ ".properties\n#---\nmy.import=badbadbad\nspring.config.activate.on-profile=missing\n"
            ]);
        });
    }

    @("runWhenHasPropertyInEarlierProfileDocumentThrowsException") unittest
    {
        // gh-29386
        import flint.boot.context.properties.bind : BindException;

        assertThrows!BindException(() {
            run([
                "resources/application.properties": "my.value=application\n#---\nmy.import=imported\n"
                ~ "spring.config.activate.on-profile=missing\n#---\nspring.config.import=${my.import}.properties\n",
                "resources/imported.properties": "my.value=imported"
            ]);
        });
    }

    @("runWhenHasPropertyInEarlierDocumentLoads") unittest
    {
        // gh-29386
        auto result = run(
                [
            "resources/application.properties": "my.import=imported\n#---\nmy.value=should-be-ignored\n"
            ~ "spring.config.activate.on-profile=missing\n#---\n"
            ~ "spring.config.import=classpath:${my.import}.properties\n",
            "resources/imported.properties": "my.value=imported"
        ]);
        assert(result.getProperty("my.value") == "imported");
    }

    @("runWhenImportingIncludesParentOrigin") unittest
    {
        import std.algorithm.searching : canFind;
        import flint.boot.context.properties.source : ConfigurationPropertyName, ConfigurationPropertySources;

        auto result = run([
            "resources/application.properties": "my.import=imported\n"
            ~ "spring.config.import=classpath:${my.import}.properties\n",
            "resources/imported.properties": "my.value=imported"
        ]);
        auto found = ConfigurationPropertySources.find(result.getSources(), ConfigurationPropertyName.of("my.value"));
        assert(found !is null);
        assert(found.getOrigin().canFind("imported.properties"));
        assert(found.getOrigin().canFind("application.properties"));
    }

    @("runWhenHasProfileSpecificImportWithImportImportsSecondProfileSpecificFile") unittest
    {
        // gh-26960
        auto result = run([
            "resources/application.properties": "spring.profiles.active=p1,p2\napplication=true\n",
            "resources/application-p1.properties": "application-p1=true\nspring.config.import=import.properties\n",
            "resources/import.properties": "import=true",
            "resources/import-p1.properties": "import-p1=true",
            "resources/import-p2.properties": "import-p2=true"
        ]);
        assert(result.getProperty("application") !is null);
        assert(result.getProperty("application-p1") !is null);
        assert(result.getProperty("application-p2") is null);
        assert(result.getProperty("import") !is null);
        assert(result.getProperty("import-p1") !is null);
        assert(result.getProperty("import-p2") !is null);
    }
}

@("runWhenHasCommandLinePropertiesLoadsWithCommandLineTakingPrecedence") unittest
{
    auto result = run(
            [
        "resources/application.properties": "my.property=frompropertiesfile\nthe.property=frompropertiesfile\n"
    ], ["--the.property=fromcommandline"]);
    assert(result.getProperty("the.property") == "fromcommandline");
    assert(result.getProperty("my.property") == "frompropertiesfile");
}

@("runWhenProfilesPresentBeforeConfigFileProcessingAugmentsProfileActivatedByConfigFile") unittest
{
    auto result = run([
        "resources/application.properties": "spring.profiles.active=myprofile",
        "resources/application-myprofile.properties": "the.property=fromprofilepropertiesfile",
        "resources/application-other.properties": "other.property=fromotherpropertiesfile"
    ], null, ["other"]);
    assert(result.getProfiles().getActive() == ["other", "myprofile"]);
    assert(result.getProperty("other.property") == "fromotherpropertiesfile");
    assert(result.getProperty("the.property") == "fromprofilepropertiesfile");
}

@("runWhenProfilePropertiesUsedInPlaceholdersLoadsWithResolvedPlaceholders") unittest
{
    auto result = run(
            [
        "resources/application.properties": "spring.profiles.active=myprofile\none.more=${my.property}\n",
        "resources/application-myprofile.properties": "my.property=fromprofilepropertiesfile"
    ]);
    assert(property(result, "one.more") == "fromprofilepropertiesfile");
}

@("loadWhenProfileInMultiDocumentFilesLoadsExpectedProperties") unittest
{
    auto result = run([
        "resources/application.yaml": "---\nmy:\n  property: fromyamlfile\n  other: notempty\n---\n"
        ~ "spring.config.activate.on-profile: dev\nmy:\n  property: fromdevprofile\n"
    ], null, ["dev"]);
    assert(result.getProperty("my.property") == "fromdevprofile");
    assert(result.getProperty("my.other") == "notempty");
}

private enum profileExpressions = "---\nmy:\n  property: fromyamlfile\n---\n"
    ~ "spring.config.activate.on-profile: dev & other\nmy:\n  property: devandother\n---\n"
    ~ "spring.config.activate.on-profile: (dev | other) & another\nmy:\n  property: devorotherandanother\n";

@("runWhenHasAndProfileExpressionLoadsExpectedProperties") unittest
{
    auto result = run(["resources/application.yaml": profileExpressions], null, ["dev", "other"]);
    assert(result.getProperty("my.property") == "devandother");
}

@("runWhenHasComplexProfileExpressionsLoadsExpectedProperties") unittest
{
    auto result = run(["resources/application.yaml": profileExpressions], null, ["dev", "another"]);
    assert(result.getProperty("my.property") == "devorotherandanother");
}

@("runWhenProfileExpressionsDoNotMatchLoadsExpectedProperties") unittest
{
    auto result = run(["resources/application.yaml": profileExpressions], null, ["dev"]);
    assert(result.getProperty("my.property") == "fromyamlfile");
}

@("runWhenHasActiveProfileConfigurationInMultiDocumentFileLoadsInExpectedOrder") unittest
{
    import std.algorithm.searching : canFind;

    auto result = run(
            [
        "resources/application.yml": "---\nspring:\n  profiles:\n    active: dev\nmy:\n  property: fromyamlfile\n"
        ~ "---\nspring.config.activate.on-profile: dev\nmy:\n  property: fromdevprofile\n"
    ]);
    assert(result.getProfiles().getActive() == ["dev"]);
    assert(result.getProperty("my.property") == "fromdevprofile");
    string[] names;
    foreach (source; result.getSources())
        names ~= source.getUnderlyingSourceName();
    assert(names.canFind(
            "Config resource 'class path resource [application.yml]' via location "
            ~ "'optional:classpath:/' (document #0)"));
    assert(names.canFind(
            "Config resource 'class path resource [application.yml]' via location "
            ~ "'optional:classpath:/' (document #1)"));
}

@("runWhenHasYamlWithCommaSeparatedMultipleProfilesLoadsExpectedProperties") unittest
{
    auto result = run([
        "resources/application.yml": "---\nspring:\n  profiles:\n    active: dev,healthcheck\n"
    ]);
    assert(result.getProfiles().getActive() == ["dev", "healthcheck"]);
}

@("runWhenHasYamlWithListProfilesLoadsExpectedProperties") unittest
{
    auto result = run(
            [
        "resources/application.yml": "---\nspring:\n  profiles:\n    active:\n      - dev\n      - healthcheck\n"
    ]);
    assert(result.getProfiles().getActive() == ["dev", "healthcheck"]);
}

@("loadWhenHasWhitespaceTrims") unittest
{
    auto result = run([
        "resources/application.yml": "---\nspring:\n  profiles:\n    active: dev  ,    healthcheck\n"
    ]);
    assert(result.getProfiles().getActive() == ["dev", "healthcheck"]);
}

@("runWhenCustomDefaultProfileSameAsActiveFromFileActivatesProfile") unittest
{
    auto result = run(
            [
        "resources/application.properties": "spring.profiles.active=customdefault\ncustomprofile=true\n",
        "resources/application-customdefault.properties": "customprofile-customdefault=true"
    ], ["--spring.profiles.default=customdefault"]);
    assert(result.getProperty("customprofile") !is null);
    assert(result.getProperty("customprofile-customdefault") !is null);
    assert(result.getProfiles().isAccepted("customdefault"));
}

version (FlintProfilePlaceholders)
{
    // Gap: `${...}` placeholders in spring.profiles.active/include are not resolved, so the literal text becomes a
    // profile name.
    @("runWhenActiveProfilesCanBeConfiguredUsingPlaceholdersResolvedAgainstTheEnvironmentLoadsExpectedProperties")
    unittest
    {
        auto result = run(
                [
            "resources/application.properties": "spring.profiles.active=${activeProfile:propertiesfile}"
        ], ["--activeProfile=testPropertySource"]);
        assert(result.getProfiles().getActive() == ["testPropertySource"]);
    }

    @("runWhenHasIncludedProfilesWithPlaceholderActivatesProfiles") unittest
    {
        import std.algorithm.sorting : sort;

        auto result = run(
                [
            "resources/application.properties": "spring.profiles.active=p1\nspring.profiles.include=p2\n#---\n"
            ~ "myprofile=p4\nspring.profiles.include=p3,${myprofile}\n#---\nmyotherprofile=p5\n"
            ~ "spring.profiles.include=${myotherprofile}\n"
        ]);
        auto active = result.getProfiles().getActive().dup;
        active.sort();
        assert(active == ["p1", "p2", "p3", "p4", "p5"]);
    }
}

@("runWhenHasAdditionalLocationLoadsWithAdditionalTakingPrecedenceOverDefaultLocation") unittest
{
    auto result = run([
        "resources/application.properties": "foo=bucket\nvalue=1234\n",
        "resources/override.properties": "foo=bar"
    ], ["--spring.config.additional-location=classpath:override.properties"]);
    assert(result.getProperty("foo") == "bar");
    assert(result.getProperty("value") == "1234");
}

@("runWhenMultipleAdditionalLocationsLoadsWithLastWinning") unittest
{
    auto result = run([
        "resources/application.properties": "foo=bucket\nvalue=1234\n",
        "resources/override.properties": "foo=bar",
        "resources/some.properties": "foo=spam"
    ], [
        "--spring.config.additional-location=classpath:override.properties,classpath:some.properties"
    ]);
    assert(result.getProperty("foo") == "spam");
    assert(result.getProperty("value") == "1234");
}

@("runWhenAdditionalLocationAndLocationLoadsWithAdditionalTakingPrecedenceOverConfigured") unittest
{
    auto result = run([
        "resources/application.properties": "value=1234",
        "resources/override.properties": "foo=bar",
        "resources/some.properties": "foo=spam"
    ], [
        "--spring.config.location=classpath:some.properties",
        "--spring.config.additional-location=classpath:override.properties"
    ]);
    assert(result.getProperty("foo") == "bar");
    assert(result.getProperty("value") is null);
}

version (FlintConfigDataLoaderSpi)
{
    // Gap: custom PropertySourceLoaders, ConfigDataLocationResolvers and ConfigDataLoaders cannot be registered
    // (Boot finds them through spring.factories; Flint lists its two loaders and one resolver).
    import flint.boot.env : Document, PropertySourceLoader;
    import flint.boot.context.config : ConfigDataLoader, ConfigDataLocationResolver;

    @("runWhenPropertiesFromCustomPropertySourceLoaderShouldLoadFromCustomSource") unittest
    {
        static final class TestPropertySourceLoader1 : PropertySourceLoader
        {
            string[] getFileExtensions()
            {
                return ["custom"];
            }
        }

        ConfigDataEnvironmentOptions options;
        options.reader = new MemoryReader(["resources/application.custom": ""]);
        options.propertySourceLoaders = [new TestPropertySourceLoader1];
        auto result = new ConfigDataEnvironment(options).processAndApply();
        assert(result.getProperty("customloader1") == "true");
    }

    @("runWhenResolvedIsOptionalDoesNotThrowException") unittest
    {
        ConfigDataEnvironmentOptions options;
        options.reader = new MemoryReader(null);
        options.args = ["--spring.config.location=test:optionalresult"];
        options.configDataLoaders = [cast(ConfigDataLoader) null];
        auto result = new ConfigDataEnvironment(options).processAndApply();
        assert(result.getProperty("spring") is null);
    }

    @("runWhenHasProfileSpecificImportWithCustomImportResolvesProfileSpecific") unittest
    {
        ConfigDataEnvironmentOptions options;
        options.reader = new MemoryReader([
            "resources/application.properties": "spring.config.import=test:boot"
        ]);
        options.configDataLocationResolvers = [cast(ConfigDataLocationResolver) null];
        auto result = new ConfigDataEnvironment(options).processAndApply();
        assert(result.getProperty("test:boot") !is null);
        assert(result.getProperty("test:boot:ps") !is null);
    }
}

@("runWhenCustomDefaultPropertySourceLoadsWithoutReplacingCustomSource") unittest
{
    // gh-17011
    auto result = run(["resources/gh17001.properties": "gh17001loaded=true"], null, null,
            ["mapkey": "mapvalue", "spring.config.name": "gh17001"]);
    assert(result.getProperty("mapkey") == "mapvalue");
    assert(result.getProperty("gh17001loaded") == "true");
}

@("runWhenConfigLocationHasNonOptionalMissingClasspathDirectoryThrowsLocationNotFoundException") unittest
{
    assertThrows!ConfigDataLocationNotFoundException(() {
        run(null, ["--spring.config.location=classpath:application.unknown/"]);
    });
}

@("runWhenConfigLocationHasNonOptionalEmptyFileDirectoryDoesNotThrowException") unittest
{
    runWith(new DirectoryReader(null, ["temp/application.empty"]), [
        "--spring.config.location=temp/application.empty/"
    ]);
}

@("runWhenConfigLocationHasMandatoryDirectoryThatDoesntExistThrowsException") unittest
{
    assertThrows!ConfigDataLocationNotFoundException(() {
        run(null, ["--spring.config.location=invalid/"]);
    });
}

@("runWhenConfigLocationHasNonOptionalEmptyFileDoesNotThrowException") unittest
{
    run(["temp/application.properties": ""], [
        "--spring.config.location=temp/application.properties"
    ]);
}

@("runWhenHasNonOptionalImportThrowsException") unittest
{
    assertThrows!ConfigDataLocationNotFoundException(() {
        run(null, ["--spring.config.location=classpath:missing-application.properties"]);
    });
}

version (FlintConfigOnNotFound)
{
    // Gap: `spring.config.on-not-found=ignore` is not supported; a missing mandatory location still fails.
    @("runWhenHasNonOptionalImportAndIgnoreNotFoundPropertyDoesNotThrowException") unittest
    {
        run(null, [
            "--spring.config.on-not-found=ignore",
            "--spring.config.location=classpath:missing-application.properties"
        ]);
    }
}

@("runWhenHasIncludedProfilesActivatesProfiles") unittest
{
    import std.algorithm.sorting : sort;

    auto result = run(
            [
        "resources/application.properties": "spring.profiles.active=p1\nspring.profiles.include=p2\n#---\n"
        ~ "spring.profiles.include=p3,p4\n#---\nspring.profiles.include=p5\n"
    ]);
    auto active = result.getProfiles().getActive().dup;
    active.sort();
    assert(active == ["p1", "p2", "p3", "p4", "p5"]);
}

version (FlintInactiveConfigDataAccess)
{
    // Gap: a profile include in an on-profile document fails with InvalidConfigDataPropertyException, not Boot's
    // InactiveConfigDataAccessException.
    import flint.boot.context.config : InactiveConfigDataAccessException;

    @("runWhenHasIncludedProfilesWithProfileSpecificDocumentThrowsException") unittest
    {
        assertThrows!InactiveConfigDataAccessException(() {
            run([
                "resources/application.properties": "spring.profiles.active=p1\nspring.profiles.include=p2\n#---\n"
                ~ "spring.config.activate.on-profile=p2\nspring.profiles.include=p3\n"
            ]);
        });
    }
}

@("runWhenHasIncludedProfilesWithListSyntaxWithProfileSpecificDocumentThrowsException") unittest
{
    assertThrows!InvalidConfigDataPropertyException(() {
        run(["resources/application-test.yaml": "spring:\n  profiles:\n    include:\n      - p\n"],
            ["--spring.profiles.active=test"]);
    });
}

@("runWhenHasWildcardLocationLoadsFromAllMatchingLocations") unittest
{
    auto result = run([
        "resources/config/first/application.properties": "first.property=apple",
        "resources/config/second/application.properties": "second.property=ball",
        "resources/config/third/nested/application.properties": "third.property=three"
    ], ["--spring.config.location=classpath:config/*/"]);
    assert(result.getProperty("first.property") == "apple");
    assert(result.getProperty("second.property") == "ball");
    assert(result.getProperty("third.property") is null);
}

@("runWhenOptionalWildcardFileDoesNotExistDoesNotThrowException") unittest
{
    run(null, [
        "--spring.config.location=optional:classpath:nonexistent/*/testproperties.properties"
    ]);
}

@("runWhenMandatoryWildcardFileDoesNotExistThrowsException") unittest
{
    assertThrows!ConfigDataLocationNotFoundException(() {
        run(null, ["--spring.config.location=classpath:nonexistent/*/testproperties.properties"]);
    });
}

@("runWhenMandatoryWildcardDirectoryHasEmptyDirectoryDoesNotThrowException") unittest
{
    runWith(new DirectoryReader(null, ["resources/config", "resources/config/empty"]),
            ["--spring.config.location=classpath:config/*/"]);
}

version (FlintWildcardWithoutSubdirectories)
{
    // Gap: a mandatory `config/*/` location whose directory has no subdirectories loads nothing instead of failing.
    @("runWhenMandatoryWildcardDirectoryHasNoSubdirectoriesThrows") unittest
    {
        assertThrows!ConfigDataLocationNotFoundException(() {
            runWith(new DirectoryReader(null, ["resources/config"]), [
                "--spring.config.location=classpath:config/*/"
            ]);
        }, "Config data location 'classpath:config/*/' contains no subdirectories");
    }
}

@("runWhenOptionalWildcardDirectoryDoesNotExistDoesNotThrowException") unittest
{
    run(null, ["--spring.config.location=optional:file:invalid/*/"]);
}

@("runWhenHasProfileSpecificFileWithActiveOnProfileProperty") unittest
{
    // gh-24990
    auto result = run([
        "resources/application.properties": "spring.profiles.active=test,other",
        "resources/application-test.properties": "test1=test1\n#---\nspring.config.activate.on-profile=other\n"
        ~ "test2=test2\n"
    ]);
    assert(result.getProperty("test1") == "test1");
    assert(result.getProperty("test2") == "test2");
}

version (FlintProfileNameValidation)
{
    // Gap: profile names are not validated, so `fa!l` is accepted.
    import flint.boot.context.properties.bind : BindException;

    @("invalidProfileActivePropertyThrowsException") unittest
    {
        try
        {
            run(["resources/application.properties": "spring.profiles.active=fa!l\n"]);
            assert(false, "expected a BindException");
        }
        catch (BindException ex)
        {
            import std.algorithm.searching : canFind;

            assert(ex.next !is null && ex.next.msg.canFind("must contain a letter"));
        }
    }

    @("invalidProfileIncludePropertyThrowsException") unittest
    {
        try
        {
            run(["resources/application.properties": "spring.profiles.include=fa!l\n"]);
            assert(false, "expected a BindException");
        }
        catch (BindException ex)
        {
            import std.algorithm.searching : canFind;

            assert(ex.next !is null && ex.next.msg.canFind("must contain a letter"));
        }
    }
}

@("unvalidatedProfileProperties") unittest
{
    run([
        "resources/application.properties": "spring.profiles.active=p!1\nspring.profiles.include=p!2\n"
        ~ "spring.profiles.validate=false\n"
    ]);
}

import boot_tests.support : RegisterTests;

mixin RegisterTests;
