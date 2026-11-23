// Ported from spring-boot v4.2.0: core/spring-boot/src/test/java/org/springframework/boot/context/config/
// InvalidConfigDataPropertyExceptionTests.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: AssertJ assertions become D asserts; one unittest per upstream @Test. Flint's
// exception is created for a property name and a location; `throwIfPropertyFound(contributor)` is what loading
// config data does, so those tests load a document holding the property through `ConfigDataEnvironment`, and the
// property is named by its canonical `flint.*` key.
module boot_tests.invalid_config_data_property_exception_test;

import boot_tests.support : assertThrows;
import boot_tests.upstream_support : MemoryReader;
import flint.boot.context.config : ConfigDataEnvironment, ConfigDataEnvironmentOptions,
    InvalidConfigDataPropertyException;

@safe:

/// Load `files`, with `profiles` active.
private void load(string[string] files, string profiles = null)
{
    ConfigDataEnvironmentOptions options;
    options.reader = new MemoryReader(files);
    if (profiles.length)
        options.args = ["--spring.profiles.active=" ~ profiles];
    new ConfigDataEnvironment(options).processAndApply();
}

version (FlintInvalidConfigDataPropertyApi)
{
    // Gap: the exception has no property, replacement or origin (only a property name and a location).
    import flint.boot.context.properties.source : ConfigurationProperty, ConfigurationPropertyName;
    import flint.boot.origin : TextResourceOrigin;

    private ConfigurationPropertyName invalid()
    {
        return ConfigurationPropertyName.of("invalid");
    }

    private ConfigurationPropertyName replacement()
    {
        return ConfigurationPropertyName.of("replacement");
    }

    private ConfigurationProperty property()
    {
        return new ConfigurationProperty(null, invalid(), "bad", "origin");
    }

    @("createHasCorrectMessage") unittest
    {
        assert(new InvalidConfigDataPropertyException(property(), false, replacement(), "test")
                .msg == "Property 'invalid' imported from location 'test' is invalid and should be replaced with "
                ~ "'replacement' [origin: origin]");
    }

    @("createWhenNoLocationHasCorrectMessage") unittest
    {
        assert(new InvalidConfigDataPropertyException(property(), false, replacement(), null)
                .msg == "Property 'invalid' is invalid and should be replaced with 'replacement' [origin: origin]");
    }

    @("createWhenNoReplacementHasCorrectMessage") unittest
    {
        assert(new InvalidConfigDataPropertyException(property(), false, null, "test")
                .msg == "Property 'invalid' imported from location 'test' is invalid [origin: origin]");
    }

    @("createWhenNoOriginHasCorrectMessage") unittest
    {
        auto withoutOrigin = new ConfigurationProperty(null, invalid(), "bad", null);
        assert(new InvalidConfigDataPropertyException(withoutOrigin, false, replacement(), "test").msg
                == "Property 'invalid' imported from location 'test' is invalid and should be replaced with "
                ~ "'replacement'");
    }

    @("getPropertyReturnsProperty") unittest
    {
        auto expected = property();
        auto exception = new InvalidConfigDataPropertyException(expected, false, replacement(), "test");
        assert(exception.getProperty() is expected);
    }

    @("getLocationReturnsLocation") unittest
    {
        auto exception = new InvalidConfigDataPropertyException(property(), false, replacement(), "test");
        assert(exception.getLocation() == "test");
    }

    @("getReplacementReturnsReplacement") unittest
    {
        auto exception = new InvalidConfigDataPropertyException(property(), false, replacement(), "test");
        assert(exception.getReplacement().equals(replacement()));
    }
}

@("createWhenProfileSpecificHasCorrectMessage") unittest
{
    assert(new InvalidConfigDataPropertyException("invalid", "test")
            .msg == "Property 'invalid' imported from location 'test' is invalid in a profile specific resource");
}

version (FlintInvalidConfigDataPropertyMessage)
{
    // Gap: `spring.profiles` in config data is reported as invalid "in a profile specific resource", without
    // Boot's replacement hint `spring.config.activate.on-profile`.
    @("throwOrWarnWhenHasInvalidPropertyThrowsException") unittest
    {
        assertThrows!InvalidConfigDataPropertyException(() {
            load(["resources/application.properties": "spring.profiles=a\n"]);
        }, "Property 'spring.profiles' is invalid and should be replaced with 'spring.config.activate.on-profile'");
    }
}

@("throwOrWarnWhenWhenHasInvalidProfileSpecificPropertyThrowsException") unittest
{
    foreach (name; ["include", "active", "default"])
    {
        assertThrows!InvalidConfigDataPropertyException(() {
            load(["resources/application-dev.properties": "spring.profiles." ~ name ~ "=a\n"], "dev");
        }, "Property 'flint.profiles." ~ name ~ "' imported from location '");
        assertThrows!InvalidConfigDataPropertyException(() {
            load(["resources/application-dev.properties": "spring.profiles." ~ name ~ "=a\n"], "dev");
        }, "is invalid in a profile specific resource");
    }
}

version (FlintConfigDataOptions)
{
    // Gap: config data has no options (ConfigData.Option.IGNORE_PROFILES) to exempt a resource.
    @("throwOrWarnWhenWhenHasInvalidProfileSpecificPropertyOnIgnoringProfilesContributorDoesNotThrowException") unittest
    {
        import flint.boot.context.config : ConfigDataOption;

        ConfigDataEnvironmentOptions options;
        options.reader = new MemoryReader([
            "resources/application-dev.properties": "spring.profiles.active=a\n"
        ]);
        options.args = ["--spring.profiles.active=dev"];
        options.configDataOptions = [ConfigDataOption.IGNORE_PROFILES];
        new ConfigDataEnvironment(options).processAndApply();
    }
}

@("throwOrWarnWhenHasNoInvalidPropertyDoesNothing") unittest
{
    load(null);
}

import boot_tests.support : RegisterTests;

mixin RegisterTests;
