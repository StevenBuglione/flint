// Ported from spring-boot v4.2.0: module/spring-boot-jackson/src/test/java/org/springframework/boot/jackson/autoconfigure/JacksonAutoConfigurationTests.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: the auto-configuration's beans are called directly, as Flint AOT's generated
// definitions call them, instead of through an ApplicationContextRunner.
module jackson_autoconfiguration_test;

import flint.boot.context.properties.bind : Binder;
import flint.boot.context.properties.source : ConfigurationPropertySource, MapConfigurationPropertySource;
import flint.boot.jackson.autoconfigure : JacksonAutoConfiguration, JacksonProperties, JsonMapperBuilderCustomizer;
import flint.engine.aot.descriptor : descriptorOf;
import flint.jackson.databind : JsonMapper;

@safe:

/// A JavaBean value (a record-style struct's creator properties do not take the naming strategy in flint.jackson
/// yet; reported to third-party-apis).
final class Person
{
    private string firstName;
    private int ageInYears;

    /// A person.
    this(string firstName, int ageInYears)
    {
        this.firstName = firstName;
        this.ageInYears = ageInYears;
    }

    /// The first name.
    string getFirstName() const
    {
        return firstName;
    }

    /// The age.
    int getAgeInYears() const
    {
        return ageInYears;
    }
}

private JsonMapper mapper(string[2][] entries)
{
    auto binder = new Binder([
        cast(ConfigurationPropertySource) new MapConfigurationPropertySource("test", entries)
    ]);
    import flint.java.util : Map;
    import flint.jackson.databind.cfg : SerializationFeature;

    binder.getDescriptors().add(descriptorOf!(Map!(SerializationFeature, bool))());
    binder.getDescriptors().add(descriptorOf!SerializationFeature());
    auto properties = binder.bindOrCreate!JacksonProperties("flint.jackson");

    auto configuration = new JacksonAutoConfiguration;
    JsonMapperBuilderCustomizer[] customizers = [
        configuration.standardJsonMapperBuilderCustomizer(properties)
    ];
    auto builder = configuration.jsonMapperBuilder(customizers);
    builder.descriptor(descriptorOf!Person());
    return configuration.jacksonJsonMapper(builder);
}

@("defaultJsonMapper") unittest
{
    const json = mapper(null).writeValueAsString(new Person("Ada", 36));
    assert(json == `{"ageInYears":36,"firstName":"Ada"}` || json == `{"firstName":"Ada","ageInYears":36}`, json);
}

@("customPropertyNamingStrategyField") unittest
{
    const json = mapper([["spring.jackson.property-naming-strategy", "SNAKE_CASE"]]).writeValueAsString(
            new Person("Ada", 36));
    import std.algorithm.searching : canFind;

    assert(json.canFind(`"first_name":"Ada"`) && json.canFind(`"age_in_years":36`), json);
}

@("enableSerializationFeature") unittest
{
    const json = mapper([["flint.jackson.serialization.indent-output", "true"]]).writeValueAsString(
            new Person("Ada", 36));
    import std.algorithm.searching : canFind;

    assert(json.canFind("\n"), json);
}
