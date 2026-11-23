// Ported from spring-boot v4.2.0: module/spring-boot-jackson/src/test/java/org/springframework/boot/jackson/autoconfigure/JacksonAutoConfigurationTests.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: the test methods jackson_autoconfiguration_test.d does not port (it holds
// customPropertyNamingStrategyField and enableSerializationFeature for JSON); the auto-configuration's beans are
// called directly, as Flint AOT's generated definitions call them, instead of through an ApplicationContextRunner,
// and back-off is read from the `@ConditionalOnMissingBean` UDAs Flint AOT evaluates; Jackson's `mapper.isEnabled`
// for streaming features is the mapper's `tokenStreamFactory().isEnabled`. `@EnumSource MapperType` loops over the
// mapper types flint.jackson has: JSON; CBOR and XML (and their own tests) wait behind FlintJacksonDataformats.
// Not ported: shouldFindAndAddModulesByDefault and shouldNotFindAndAddModulesWhenDisabled (they look for Jackson's
// KotlinModule) and shouldRegisterPropertyNamingStrategyHints (GraalVM `RuntimeHints`).
module jackson_auto_configuration_upstream_test;

import flint.boot.autoconfigure.condition : ConditionalOnMissingBean;
import flint.boot.context.properties.bind : Binder;
import flint.boot.context.properties.source : ConfigurationPropertySource, MapConfigurationPropertySource;
import flint.boot.jackson.autoconfigure : JacksonAutoConfiguration, JacksonProperties,
    JsonMapperBuilderCustomizer, StandardJsonMapperBuilderCustomizer;
import flint.engine.aot.descriptor : descriptorOf;
import flint.jackson.annotation : JsonInclude;
import flint.jackson.core : StreamReadFeature, StreamWriteFeature, enabledByDefault;
import flint.jackson.core.json : JsonReadFeature, JsonWriteFeature, enabledByDefault;
import flint.jackson.databind : ConstructorDetector, JsonMapper;
import flint.jackson.databind.cfg : DateTimeFeature, DeserializationFeature, EnumFeature,
    MapperFeature, SerializationFeature, enabledByDefault;
import std.traits : EnumMembers, getUDAs, hasUDA;

@safe:

version (FlintJacksonDataformats)
    private enum MapperType
    {
        CBOR,
        JSON,
        XML
    }
else
    private enum MapperType
    {
        JSON
    }

private JacksonProperties properties(string[2][] entries)
{
    import flint.jackson.annotation : JsonAutoDetect, PropertyAccessor;
    import flint.java.util : Map, Optional;

    auto binder = new Binder([
        cast(ConfigurationPropertySource) new MapConfigurationPropertySource("test", entries)
    ]);
    foreach (descriptor; [
        descriptorOf!(Map!(SerializationFeature, bool))(), descriptorOf!SerializationFeature(),
        descriptorOf!(Map!(DeserializationFeature, bool))(),
        descriptorOf!DeserializationFeature(), descriptorOf!(Map!(MapperFeature, bool))(),
        descriptorOf!MapperFeature(), descriptorOf!(Map!(DateTimeFeature, bool))(),
        descriptorOf!DateTimeFeature(), descriptorOf!(Map!(EnumFeature, bool))(),
        descriptorOf!EnumFeature(), descriptorOf!(Map!(StreamReadFeature, bool))(),
        descriptorOf!StreamReadFeature(), descriptorOf!(Map!(StreamWriteFeature, bool))(),
        descriptorOf!StreamWriteFeature(), descriptorOf!(Map!(JsonReadFeature, bool))(),
        descriptorOf!JsonReadFeature(), descriptorOf!(Map!(JsonWriteFeature, bool))(),
        descriptorOf!JsonWriteFeature(), descriptorOf!(JacksonProperties.Datatype)(),
        descriptorOf!(JacksonProperties.Json)(),
        descriptorOf!(JacksonProperties.ConstructorDetectorStrategy)(),
        descriptorOf!(Optional!(JsonInclude.Include))(), descriptorOf!(JsonInclude.Include)(),
        descriptorOf!(Optional!bool)(),
        descriptorOf!(Map!(PropertyAccessor, JsonAutoDetect.Visibility))(),
        descriptorOf!PropertyAccessor(), descriptorOf!(JsonAutoDetect.Visibility)()
    ])
        binder.getDescriptors().add(descriptor);
    return binder.bindOrCreate!JacksonProperties("flint.jackson");
}

private JsonMapper.Builder mapperBuilder(string[2][] entries = null)
{
    auto configuration = new JacksonAutoConfiguration;
    JsonMapperBuilderCustomizer[] customizers = [
        configuration.standardJsonMapperBuilderCustomizer(properties(entries))
    ];
    return configuration.jsonMapperBuilder(customizers);
}

// `mapperType.getMapper(context)`.
private JsonMapper getMapper(MapperType mapperType, string[2][] entries = null)
{
    final switch (mapperType)
    {
    case MapperType.JSON:
        return new JacksonAutoConfiguration().jacksonJsonMapper(mapperBuilder(entries));
        version (FlintJacksonDataformats)
        {
    case MapperType.CBOR:
            return new JacksonAutoConfiguration().cborMapper(entries);
    case MapperType.XML:
            return new JacksonAutoConfiguration().xmlMapper(entries);
        }
    }
}

// Whether a `@Bean` method carries `@ConditionalOnMissingBean` (backs off for a user bean).
private enum bool backsOff(alias method) = hasUDA!(method, ConditionalOnMissingBean);

// The types its `@ConditionalOnMissingBean` names; none means the method's return type.
private string[] missingBeanTypes(alias method)()
{
    string[] types;
    static foreach (attribute; __traits(getAttributes, method))
        static if (is(typeof(attribute) == ConditionalOnMissingBean))
            foreach (type; attribute.value)
                types ~= type.name;
    return types;
}

// Boot's JsonFactory bean and StandardJsonFactoryBuilderCustomizer (with `flint.jackson.factory.constraints.*`);
// Flint's mapper builds its own JsonFactory.
version (FlintJacksonFactoryBeans)
{
    @("JacksonAutoConfigurationTests.definesFactory") unittest
    {
        foreach (mapperType; [EnumMembers!MapperType])
            assert(new JacksonAutoConfiguration().jsonFactory(null) !is null);
    }

    @("JacksonAutoConfigurationTests.factoryBacksOffWhenCustomFactoryIsDefined") unittest
    {
        foreach (mapperType; [EnumMembers!MapperType])
            static assert(backsOff!(JacksonAutoConfiguration.jsonFactory));
    }

    @("JacksonAutoConfigurationTests.standardJsonFactoryBuilderCustomizerDoesNotBackOffWhenCustomizerIsDefined")
    unittest
    {
        static assert(!backsOff!(JacksonAutoConfiguration.standardJsonFactoryBuilderCustomizer));
    }

    @("JacksonAutoConfigurationTests.customStreamReadConstraintsAreAppliedToAutoConfiguredFactory") unittest
    {
        foreach (mapperType; [EnumMembers!MapperType])
        {
            const constraints = getMapper(mapperType, [
                ["spring.jackson.factory.constraints.read.max-document-length", "1000"],
                ["spring.jackson.factory.constraints.read.max-name-length", "1001"],
                ["spring.jackson.factory.constraints.read.max-nesting-depth", "1002"],
                ["spring.jackson.factory.constraints.read.max-number-length", "1003"],
                ["spring.jackson.factory.constraints.read.max-string-length", "1004"],
                ["spring.jackson.factory.constraints.read.max-token-count", "1005"]
            ]).tokenStreamFactory().streamReadConstraints();
            assert(constraints.getMaxDocumentLength() == 1000 && constraints.getMaxNameLength() == 1001);
            assert(constraints.getMaxNestingDepth() == 1002 && constraints.getMaxNumberLength() == 1003);
            assert(constraints.getMaxStringLength() == 1004 && constraints.getMaxTokenCount() == 1005);
        }
    }

    @("JacksonAutoConfigurationTests.customStreamWriteConstraintsAreAppliedToAutoConfiguredFactory") unittest
    {
        foreach (mapperType; [EnumMembers!MapperType])
            assert(getMapper(mapperType, [
                    ["spring.jackson.factory.constraints.write.max-nesting-depth", "1000"]
        ]).tokenStreamFactory().streamWriteConstraints().getMaxNestingDepth() == 1000);
    }

    @("JacksonAutoConfigurationTests.defaultStreamWriteConstraintsMatchJacksonDefaults") unittest
    {
        import flint.jackson.core : StreamReadConstraints;

        foreach (mapperType; [EnumMembers!MapperType])
            assert(getMapper(mapperType).tokenStreamFactory().streamWriteConstraints()
                    .getMaxNestingDepth() == StreamReadConstraints.DEFAULT_MAX_DEPTH);
    }
}

@("JacksonAutoConfigurationTests.definesMapper") unittest
{
    foreach (mapperType; [EnumMembers!MapperType])
        assert(getMapper(mapperType) !is null);
}

@("JacksonAutoConfigurationTests.definesMapperBuilder") unittest
{
    foreach (mapperType; [EnumMembers!MapperType])
        assert(mapperBuilder() !is null);
}

@("JacksonAutoConfigurationTests.mapperBacksOffWhenCustomMapperIsDefined") unittest
{
    foreach (mapperType; [EnumMembers!MapperType])
        static assert(backsOff!(JacksonAutoConfiguration.jacksonJsonMapper));
}

@("JacksonAutoConfigurationTests.mapperDoesNotBackOffWhenObjectMapperIsDefined") unittest
{
    import std.traits : ReturnType;

    // The condition names no type, so it is the method's JsonMapper, which a plain ObjectMapper bean is not.
    foreach (mapperType; [EnumMembers!MapperType])
    {
        assert(missingBeanTypes!(JacksonAutoConfiguration.jacksonJsonMapper)().length == 0);
        static assert(is(ReturnType!(JacksonAutoConfiguration.jacksonJsonMapper) == JsonMapper));
    }
}

@("JacksonAutoConfigurationTests.mapperBuilderDoesNotBackOffWhenMapperIsDefined") unittest
{
    import std.traits : ReturnType;

    foreach (mapperType; [EnumMembers!MapperType])
    {
        assert(missingBeanTypes!(JacksonAutoConfiguration.jsonMapperBuilder)().length == 0);
        static assert(is(ReturnType!(JacksonAutoConfiguration.jsonMapperBuilder) == JsonMapper.Builder));
    }
}

@("JacksonAutoConfigurationTests.standardJsonMapperBuilderCustomizerDoesNotBackOffWhenCustomizerIsDefined") unittest
{
    static assert(!backsOff!(JacksonAutoConfiguration.standardJsonMapperBuilderCustomizer));
    assert(cast(StandardJsonMapperBuilderCustomizer) new JacksonAutoConfiguration()
            .standardJsonMapperBuilderCustomizer(new JacksonProperties) !is null);
}

// CBOR and XML: flint.jackson has neither dataformat.
version (FlintJacksonDataformats)
{
    import flint.boot.jackson.autoconfigure : CborMapperBuilderCustomizer,
        StandardCborMapperBuilderCustomizer, StandardXmlMapperBuilderCustomizer, XmlMapperBuilderCustomizer;

    @("JacksonAutoConfigurationTests.standardCborMapperBuilderCustomizerDoesNotBackOffWhenCustomizerIsDefined")
    unittest
    {
        static assert(!backsOff!(JacksonAutoConfiguration.standardCborMapperBuilderCustomizer));
    }

    @("JacksonAutoConfigurationTests.standardXmlMapperBuilderCustomizerDoesNotBackOffWhenCustomizerIsDefined")
    unittest
    {
        static assert(!backsOff!(JacksonAutoConfiguration.standardXmlMapperBuilderCustomizer));
    }

    @("JacksonAutoConfigurationTests.standardCborFactoryBuilderCustomizerDoesNotBackOffWhenCustomizerIsDefined")
    unittest
    {
        static assert(!backsOff!(JacksonAutoConfiguration.standardCborFactoryBuilderCustomizer));
    }

    @("JacksonAutoConfigurationTests.standardXmlFactoryBuilderCustomizerDoesNotBackOffWhenCustomizerIsDefined")
    unittest
    {
        static assert(!backsOff!(JacksonAutoConfiguration.standardXmlFactoryBuilderCustomizer));
    }

    @("JacksonAutoConfigurationTests.customModulesRegisteredByCborMapperBuilderCustomizerShouldBeRetained") unittest
    {
        assert(getMapper(MapperType.CBOR).registeredModules().length >= 3);
    }

    @("JacksonAutoConfigurationTests.customModulesRegisteredByXmlMapperBuilderCustomizerShouldBeRetained") unittest
    {
        assert(getMapper(MapperType.XML).registeredModules().length >= 3);
    }

    @("JacksonAutoConfigurationTests.customTimeZoneFormattingADateToCbor") unittest
    {
        import flint.java.util : Date;

        assert(getMapper(MapperType.CBOR, [
                ["spring.jackson.time-zone", "GMT+10"], ["spring.jackson.date-format", "z"]
        ]).writeValueAsBytes(new Date(1_436_966_242_231L)) == [
            105, 71, 77, 84, 43, 49, 48, 58, 48, 48
        ]);
    }

    @("JacksonAutoConfigurationTests.customTimeZoneFormattingADateToXml") unittest
    {
        import flint.java.util : Date;

        assert(getMapper(MapperType.XML, [
                ["spring.jackson.time-zone", "GMT+10"], ["spring.jackson.date-format", "z"]
        ]).writeValueAsString(new Date(1_436_966_242_231L)) == "<Date>GMT+10:00</Date>");
    }

    @("JacksonAutoConfigurationTests.additionalCborMapperBuilderCustomization") unittest
    {
        assert(getMapper(MapperType.CBOR).serializationConfig().getDateFormat() !is null);
    }

    @("JacksonAutoConfigurationTests.additionalXmlMapperBuilderCustomization") unittest
    {
        assert(getMapper(MapperType.XML).serializationConfig().getDateFormat() !is null);
    }

    @("JacksonAutoConfigurationTests.cborMapperBuilderIsNotSharedAcrossMultipleInjectionPoints") unittest
    {
        auto configuration = new JacksonAutoConfiguration;
        assert(configuration.cborMapperBuilder(null) !is configuration.cborMapperBuilder(null));
    }

    @("JacksonAutoConfigurationTests.xmlMapperBuilderIsNotSharedAcrossMultipleInjectionPoints") unittest
    {
        auto configuration = new JacksonAutoConfiguration;
        assert(configuration.xmlMapperBuilder(null) !is configuration.xmlMapperBuilder(null));
    }

    @("JacksonAutoConfigurationTests.shouldRegisterProblemDetailsMixinWithXmlMapper") unittest
    {
        import flint.http : ProblemDetail;

        auto problemDetail = ProblemDetail.forStatus(404);
        problemDetail.setProperty("spring", "boot");
        assert(getMapper(MapperType.XML).writeValueAsString(problemDetail) == "<problem xmlns=\"urn:ietf:rfc:7807\">"
                ~ "<status>404</status><title>Not Found</title><spring>boot</spring></problem>");
    }

    @("JacksonAutoConfigurationTests.whenUsingJackson2DefaultsCborMapperShouldBeConfiguredUsingConfigureForJackson2")
    unittest
    {
        assert(getMapper(MapperType.CBOR, [["spring.jackson.use-jackson2-defaults", "true"]]) !is null);
    }

    @("JacksonAutoConfigurationTests.whenUsingJackson2DefaultsXmlMapperShouldBeConfiguredUsingConfigureForJackson2")
    unittest
    {
        assert(getMapper(MapperType.XML, [["spring.jackson.use-jackson2-defaults", "true"]]) !is null);
    }
}

// Jackson modules: module beans, `@JacksonComponent` serializers, `@JacksonMixin` and the mapper's registered modules.
version (FlintJacksonModules)
{
    import flint.jackson.databind.module_ : SimpleModule;

    @("JacksonAutoConfigurationTests.doubleModuleRegistration") unittest
    {
        auto module_ = new SimpleModule;
        auto builder = mapperBuilder();
        builder.addModule(module_);
        builder.addModule(module_);
        assert(builder.build().registeredModules().length == 1);
    }

    @("JacksonAutoConfigurationTests.jsonMixinModuleShouldBeAutoConfiguredWithBasePackages") unittest
    {
        import flint.boot.jackson : JacksonMixinModule;

        assert(new JacksonAutoConfiguration().jsonMixinModule(null) !is null);
    }

    @("JacksonAutoConfigurationTests.moduleBeansAndWellKnownModulesAreRegisteredWithTheMapperBuilder") unittest
    {
        foreach (mapperType; [EnumMembers!MapperType])
            assert(getMapper(mapperType).registeredModules().length != 0);
    }

    @("JacksonAutoConfigurationTests.customModulesRegisteredByJsonMapperBuilderCustomizerShouldBeRetained") unittest
    {
        auto builder = mapperBuilder();
        builder.addModule(new SimpleModule("module-A"));
        builder.addModule(new SimpleModule("module-B"));
        assert(builder.build().registeredModules().length >= 2);
    }

    @("JacksonAutoConfigurationTests.jacksonComponentThatInjectsJsonMapperCausesBeanCurrentlyInCreationException")
    unittest
    {
        import flint.boot.jackson : JacksonComponentModule;

        assert(new JacksonAutoConfiguration().jacksonComponentModule(null) !is null);
    }
}

// `flint.jackson.date-format`, `time-zone`, `locale` and `default-leniency`: they wait on flint.java.time's
// formatting and the builder methods that use it (StandardJsonMapperBuilderCustomizer's comment).
version (FlintJacksonDateFormat)
{
    import flint.java.text : SimpleDateFormat;

    @("JacksonAutoConfigurationTests.noCustomDateFormat") unittest
    {
        import flint.jackson.databind.util : StdDateFormat;

        foreach (mapperType; [EnumMembers!MapperType])
            assert(cast(StdDateFormat) getMapper(mapperType).serializationConfig().getDateFormat() !is null);
    }

    @("JacksonAutoConfigurationTests.customDateFormat") unittest
    {
        foreach (mapperType; [EnumMembers!MapperType])
        {
            auto format = cast(SimpleDateFormat) getMapper(mapperType,
                    [["spring.jackson.date-format", "yyyyMMddHHmmss"]]).serializationConfig().getDateFormat();
            assert(format !is null && format.toPattern() == "yyyyMMddHHmmss");
        }
    }

    @("JacksonAutoConfigurationTests.customDateFormatClass") unittest
    {
        enum dateFormatClass = "jackson_auto_configuration_upstream_test.MyDateFormat";
        foreach (mapperType; [EnumMembers!MapperType])
        {
            auto mapper = getMapper(mapperType, [["spring.jackson.date-format", dateFormatClass]]);
            assert(cast(SimpleDateFormat) mapper.serializationConfig().getDateFormat() !is null);
        }
    }

    @("JacksonAutoConfigurationTests.customTimeZoneFormattingADateToJson") unittest
    {
        import flint.java.util : Date;

        assert(getMapper(MapperType.JSON, [
                ["spring.jackson.time-zone", "GMT+10"], ["spring.jackson.date-format", "z"]
        ]).writeValueAsString(new Date(1_436_966_242_231L)) == `"GMT+10:00"`);
    }

    @("JacksonAutoConfigurationTests.enableDefaultLeniency") unittest
    {
        foreach (mapperType; [EnumMembers!MapperType])
        {
            auto mapper = getMapper(mapperType, [["spring.jackson.default-leniency", "true"]]);
            assert(mapper.readTree(`{"birthDate":"2010-12-30"}`) !is null);
        }
    }

    @("JacksonAutoConfigurationTests.disableDefaultLeniency") unittest
    {
        foreach (mapperType; [EnumMembers!MapperType])
            assert(getMapper(mapperType, [["spring.jackson.default-leniency", "false"]])
                    .serializationConfig().getDefaultLeniency() == false);
    }

    @("JacksonAutoConfigurationTests.additionalJsonMapperBuilderCustomization") unittest
    {
        auto builder = mapperBuilder();
        builder.defaultDateFormat(new SimpleDateFormat("yyyy-MM-dd HH:mm:ss"));
        assert(cast(SimpleDateFormat) builder.build().serializationConfig().getDateFormat() !is null);
    }
}

@("JacksonAutoConfigurationTests.noCustomPropertyNamingStrategy") unittest
{
    foreach (mapperType; [EnumMembers!MapperType])
        assert(getMapper(mapperType).serializationConfig().naming is null);
}

// LIKELY BUG: Boot accepts a PropertyNamingStrategy class name for `flint.jackson.property-naming-strategy`;
// Flint only knows the PropertyNamingStrategies constants and fails the mapper with "Constant named ... not found".
version (FlintJacksonNamingStrategyClass)
{
    @("JacksonAutoConfigurationTests.customPropertyNamingStrategyClass") unittest
    {
        foreach (mapperType; [EnumMembers!MapperType])
        {
            auto mapper = getMapper(mapperType, [
                [
                    "spring.jackson.property-naming-strategy",
                    "flint.jackson.databind.PropertyNamingStrategies.SnakeCaseStrategy"
                ]
            ]);
            assert(mapper.serializationConfig().naming !is null);
        }
    }
}

@("JacksonAutoConfigurationTests.disableSerializationFeature") unittest
{
    foreach (mapperType; [EnumMembers!MapperType])
    {
        auto mapper = getMapper(mapperType, [
            ["spring.jackson.serialization.wrap_exceptions", "false"]
        ]);
        assert(enabledByDefault(SerializationFeature.WRAP_EXCEPTIONS));
        assert(!mapper.isEnabled(SerializationFeature.WRAP_EXCEPTIONS));
    }
}

@("JacksonAutoConfigurationTests.enableDeserializationFeature") unittest
{
    foreach (mapperType; [EnumMembers!MapperType])
    {
        auto mapper = getMapper(mapperType, [
            ["spring.jackson.deserialization.use_big_decimal_for_floats", "true"]
        ]);
        assert(!enabledByDefault(DeserializationFeature.USE_BIG_DECIMAL_FOR_FLOATS));
        assert(mapper.isEnabled(DeserializationFeature.USE_BIG_DECIMAL_FOR_FLOATS));
    }
}

@("JacksonAutoConfigurationTests.disableDeserializationFeature") unittest
{
    foreach (mapperType; [EnumMembers!MapperType])
    {
        auto mapper = getMapper(mapperType, [
            ["spring.jackson.deserialization.fail-on-null-for-primitives", "false"]
        ]);
        assert(enabledByDefault(DeserializationFeature.FAIL_ON_NULL_FOR_PRIMITIVES));
        assert(!mapper.isEnabled(DeserializationFeature.FAIL_ON_NULL_FOR_PRIMITIVES));
    }
}

@("JacksonAutoConfigurationTests.enableMapperFeature") unittest
{
    foreach (mapperType; [EnumMembers!MapperType])
    {
        auto mapper = getMapper(mapperType, [
            ["spring.jackson.mapper.require_setters_for_getters", "true"]
        ]);
        assert(!enabledByDefault(MapperFeature.REQUIRE_SETTERS_FOR_GETTERS));
        assert(mapper.serializationConfig().isEnabled(MapperFeature.REQUIRE_SETTERS_FOR_GETTERS));
    }
}

@("JacksonAutoConfigurationTests.disableMapperFeature") unittest
{
    foreach (mapperType; [EnumMembers!MapperType])
    {
        auto mapper = getMapper(mapperType, [
            ["spring.jackson.mapper.infer-property-mutators", "false"]
        ]);
        assert(enabledByDefault(MapperFeature.INFER_PROPERTY_MUTATORS));
        assert(!mapper.serializationConfig().isEnabled(MapperFeature.INFER_PROPERTY_MUTATORS));
    }
}

@("JacksonAutoConfigurationTests.enableJsonReadFeature") unittest
{
    auto mapper = getMapper(MapperType.JSON, [
        ["spring.jackson.json.read.allow_single_quotes", "true"]
    ]);
    assert(!enabledByDefault(JsonReadFeature.ALLOW_SINGLE_QUOTES));
    assert(mapper.tokenStreamFactory().isEnabled(JsonReadFeature.ALLOW_SINGLE_QUOTES));
}

@("JacksonAutoConfigurationTests.enableJsonWriteFeature") unittest
{
    auto mapper = getMapper(MapperType.JSON, [
        ["spring.jackson.json.write.write_numbers_as_strings", "true"]
    ]);
    const feature = JsonWriteFeature.WRITE_NUMBERS_AS_STRINGS;
    assert(!enabledByDefault(feature));
    assert(mapper.tokenStreamFactory().isEnabled(feature));
}

@("JacksonAutoConfigurationTests.disableJsonWriteFeature") unittest
{
    auto mapper = getMapper(MapperType.JSON, [
        ["spring.jackson.json.write.write_hex_upper_case", "false"]
    ]);
    assert(enabledByDefault(JsonWriteFeature.WRITE_HEX_UPPER_CASE));
    assert(!mapper.tokenStreamFactory().isEnabled(JsonWriteFeature.WRITE_HEX_UPPER_CASE));
}

@("JacksonAutoConfigurationTests.enableDatetimeFeature") unittest
{
    foreach (mapperType; [EnumMembers!MapperType])
    {
        auto mapper = getMapper(mapperType, [
            ["spring.jackson.datatype.datetime.write-dates-as-timestamps", "true"]
        ]);
        const feature = DateTimeFeature.WRITE_DATES_AS_TIMESTAMPS;
        assert(!enabledByDefault(feature));
        assert(mapper.isEnabled(feature));
    }
}

@("JacksonAutoConfigurationTests.disableDatetimeFeature") unittest
{
    foreach (mapperType; [EnumMembers!MapperType])
    {
        auto mapper = getMapper(mapperType,
                [["spring.jackson.datatype.datetime.adjust-dates-to-context-time-zone", "false"]]);
        assert(enabledByDefault(DateTimeFeature.ADJUST_DATES_TO_CONTEXT_TIME_ZONE));
        assert(!mapper.isEnabled(DateTimeFeature.ADJUST_DATES_TO_CONTEXT_TIME_ZONE));
    }
}

// LIKELY BUG: Boot binds the enum features from `datatype.enum.*` (`Datatype.getEnum()`); Flint's getter is
// `getEnumFeatures()`, so it binds `datatype.enum-features.*` and `flint.jackson.datatype.enum.*` is ignored.
version (FlintJacksonDatatypeEnumBinding)
{
    @("JacksonAutoConfigurationTests.enableEnumFeature") unittest
    {
        foreach (mapperType; [EnumMembers!MapperType])
        {
            auto mapper = getMapper(mapperType, [
                ["spring.jackson.datatype.enum.write-enums-to-lowercase", "true"]
            ]);
            assert(!enabledByDefault(EnumFeature.WRITE_ENUMS_TO_LOWERCASE));
            assert(mapper.serializationConfig().isEnabled(EnumFeature.WRITE_ENUMS_TO_LOWERCASE));
        }
    }
}

// `flint.jackson.datatype.json-node.*` follows with flint.jackson's JsonNodeFeature.
version (FlintJacksonJsonNodeFeature)
{
    @("JacksonAutoConfigurationTests.disableJsonNodeFeature") unittest
    {
        import flint.jackson.databind.cfg : JsonNodeFeature;

        foreach (mapperType; [EnumMembers!MapperType])
        {
            auto mapper = getMapper(mapperType, [
                ["spring.jackson.datatype.json-node.write-null-properties", "false"]
            ]);
            assert(enabledByDefault(JsonNodeFeature.WRITE_NULL_PROPERTIES));
            assert(!mapper.isEnabled(JsonNodeFeature.WRITE_NULL_PROPERTIES));
        }
    }
}

@("JacksonAutoConfigurationTests.enableWriteFeature") unittest
{
    foreach (mapperType; [EnumMembers!MapperType])
    {
        auto mapper = getMapper(mapperType, [
            ["spring.jackson.write.write-bigdecimal-as-plain", "true"]
        ]);
        assert(!enabledByDefault(StreamWriteFeature.WRITE_BIGDECIMAL_AS_PLAIN));
        assert(mapper.tokenStreamFactory().isEnabled(StreamWriteFeature.WRITE_BIGDECIMAL_AS_PLAIN));
    }
}

@("JacksonAutoConfigurationTests.enableReadFeature") unittest
{
    foreach (mapperType; [EnumMembers!MapperType])
    {
        auto mapper = getMapper(mapperType, [
            ["spring.jackson.read.strict-duplicate-detection", "true"]
        ]);
        assert(!enabledByDefault(StreamReadFeature.STRICT_DUPLICATE_DETECTION));
        assert(mapper.tokenStreamFactory().isEnabled(StreamReadFeature.STRICT_DUPLICATE_DETECTION));
    }
}

// Jackson's default inclusion is `JsonInclude.Value.empty()` (USE_DEFAULTS for values and contents); flint.jackson
// stores the effective ALWAYS, which serializes the same.
version (FlintJacksonUseDefaultsInclusion)
{
    @("JacksonAutoConfigurationTests.defaultPropertyInclusion") unittest
    {
        foreach (mapperType; [EnumMembers!MapperType])
        {
            const config = getMapper(mapperType).serializationConfig();
            assert(config.defaultContentInclusion == JsonInclude.Include.USE_DEFAULTS);
            assert(config.defaultInclusion == JsonInclude.Include.USE_DEFAULTS);
        }
    }
}

@("JacksonAutoConfigurationTests.customPropertyInclusion") unittest
{
    foreach (mapperType; [EnumMembers!MapperType])
    {
        const config = getMapper(mapperType, [
            ["spring.jackson.default-property-inclusion", "non_null"]
        ]).serializationConfig();
        assert(config.defaultContentInclusion == JsonInclude.Include.NON_NULL);
        assert(config.defaultInclusion == JsonInclude.Include.NON_NULL);
    }
}

@("JacksonAutoConfigurationTests.constructorDetectorWithNoStrategyUseDefault") unittest
{
    foreach (mapperType; [EnumMembers!MapperType])
    {
        const cd = getMapper(mapperType).serializationConfig().constructorDetector;
        assert(cd == ConstructorDetector.DEFAULT);
        assert(!cd.requireCtorAnnotation);
    }
}

@("JacksonAutoConfigurationTests.constructorDetectorWithDefaultStrategy") unittest
{
    foreach (mapperType; [EnumMembers!MapperType])
    {
        const cd = getMapper(mapperType, [["spring.jackson.constructor-detector", "default"]]).serializationConfig()
            .constructorDetector;
        assert(cd == ConstructorDetector.DEFAULT);
        assert(!cd.requireCtorAnnotation);
    }
}

// flint.jackson's ConstructorDetector has no single-argument mode: `use-properties-based` and `use-delegating` fail
// the mapper with "is not supported by flint.jackson yet".
version (FlintJacksonConstructorDetectorModes)
{
    import flint.jackson.databind.cfg : SingleArgConstructor;

    @("JacksonAutoConfigurationTests.constructorDetectorWithUsePropertiesBasedStrategy") unittest
    {
        foreach (mapperType; [EnumMembers!MapperType])
        {
            const cd = getMapper(mapperType, [
                ["spring.jackson.constructor-detector", "use-properties-based"]
            ]).serializationConfig().constructorDetector;
            assert(cd.singleArgMode() == SingleArgConstructor.PROPERTIES);
            assert(!cd.requireCtorAnnotation && !cd.allowJDKTypeConstructors());
        }
    }

    @("JacksonAutoConfigurationTests.constructorDetectorWithUseDelegatingStrategy") unittest
    {
        foreach (mapperType; [EnumMembers!MapperType])
        {
            const cd = getMapper(mapperType, [
                ["spring.jackson.constructor-detector", "use-delegating"]
            ]).serializationConfig().constructorDetector;
            assert(cd.singleArgMode() == SingleArgConstructor.DELEGATING);
            assert(!cd.requireCtorAnnotation && !cd.allowJDKTypeConstructors());
        }
    }
}

// LIKELY BUG: Jackson's EXPLICIT_ONLY only refuses to guess the mode of single-argument creators
// (`SingleArgConstructor.REQUIRE_MODE`, `requireCtorAnnotation()` false); flint.jackson's EXPLICIT_ONLY requires
// `@JsonCreator` on every non-default constructor, so `explicit-only` rejects multi-argument creators Boot accepts.
version (FlintJacksonExplicitOnlyDetector)
{
    @("JacksonAutoConfigurationTests.constructorDetectorWithExplicitOnlyStrategy") unittest
    {
        foreach (mapperType; [EnumMembers!MapperType])
        {
            const cd = getMapper(mapperType, [
                ["spring.jackson.constructor-detector", "explicit-only"]
            ]).serializationConfig().constructorDetector;
            assert(!cd.requireCtorAnnotation);
        }
    }
}

@("JacksonAutoConfigurationTests.writeDurationAsTimestampsDefault") unittest
{
    import flint.java.time : Duration;

    foreach (mapperType; [EnumMembers!MapperType])
        assert(getMapper(mapperType).writeValueAsString(Duration.ofHours(2)) == `"PT2H"`);
}

/// `VisibilityBean`: a private field, a public field and a package getter.
final class VisibilityBean
{
    private string property1;
    /// The public field.
    string property2;

    package string getProperty3()
    {
        return null;
    }
}

// LIKELY BUG: `flint.jackson.visibility.*` is bound but StandardJsonMapperBuilderCustomizer never applies it.
version (FlintJacksonVisibility)
{
    @("JacksonAutoConfigurationTests.writeWithVisibility") unittest
    {
        foreach (mapperType; [EnumMembers!MapperType])
        {
            auto builder = mapperBuilder([
                ["spring.jackson.visibility.getter", "none"],
                ["spring.jackson.visibility.field", "any"]
            ]);
            builder.descriptor(descriptorOf!VisibilityBean());
            auto mapper = new JacksonAutoConfiguration().jacksonJsonMapper(builder);
            auto written = mapper.readTree(mapper.writeValueAsString(new VisibilityBean));
            assert(written.has("property1") && written.has("property2") && written.size() == 2);
        }
    }
}

@("JacksonAutoConfigurationTests.jsonMapperBuilderIsNotSharedAcrossMultipleInjectionPoints") unittest
{
    import flint.context.annotation : Scope;

    static assert(getUDAs!(JacksonAutoConfiguration.jsonMapperBuilder, Scope)[0].value == "prototype");
    auto configuration = new JacksonAutoConfiguration;
    const builderOne = configuration.jsonMapperBuilder(null);
    const builderTwo = configuration.jsonMapperBuilder(null);
    assert(builderOne !is null && builderTwo !is null);
    assert(builderOne !is builderTwo);
}

// Boot's JacksonAutoConfiguration registers ProblemDetailJacksonMixin; ProblemDetail lives in flint:web, which
// boot-jackson does not depend on.
version (FlintJacksonProblemDetailMixin)
{
    @("JacksonAutoConfigurationTests.shouldRegisterProblemDetailsMixinWithJsonMapper") unittest
    {
        import flint.http : ProblemDetail;

        auto problemDetail = ProblemDetail.forStatus(404);
        problemDetail.setProperty("spring", "boot");
        assert(getMapper(MapperType.JSON)
                .writeValueAsString(problemDetail) == `{"status":404,"title":"Not Found","spring":"boot"}`);
    }
}

// `JsonMapper.builder().configureForJackson2()`, which flint.jackson does not have.
version (FlintJacksonConfigureForJackson2)
{
    @("JacksonAutoConfigurationTests.whenUsingJackson2DefaultsJsonMapperShouldBeConfiguredUsingConfigureForJackson2")
    unittest
    {
        auto jsonMapper = getMapper(MapperType.JSON, [
            ["spring.jackson.use-jackson2-defaults", "true"]
        ]);
        auto jackson2ConfiguredJsonMapper = JsonMapper.builder().configureForJackson2().build();
        foreach (feature; [EnumMembers!DeserializationFeature])
            assert(jsonMapper.isEnabled(feature) == (feature == DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES
                    ? false : jackson2ConfiguredJsonMapper.isEnabled(feature)));
        foreach (feature; [EnumMembers!JsonReadFeature])
            assert(jsonMapper.tokenStreamFactory()
                    .isEnabled(feature) == jackson2ConfiguredJsonMapper.tokenStreamFactory().isEnabled(feature));
    }
}

@("JacksonAutoConfigurationTests.defaultStreamReadConstraintsMatchJacksonDefaults") unittest
{
    import flint.jackson.core : StreamReadConstraints;

    foreach (mapperType; [EnumMembers!MapperType])
    {
        const constraints = getMapper(mapperType).tokenStreamFactory().streamReadConstraints();
        version (FlintJacksonFactoryBeans)
        {
            // The document length and token count limits.
            assert(constraints.getMaxDocumentLength() == StreamReadConstraints.DEFAULT_MAX_DOC_LEN);
            assert(constraints.getMaxTokenCount() == StreamReadConstraints.DEFAULT_MAX_TOKEN_COUNT);
        }
        assert(constraints.maxNameLength == StreamReadConstraints.DEFAULT_MAX_NAME_LEN);
        assert(constraints.maxNestingDepth == StreamReadConstraints.DEFAULT_MAX_DEPTH);
        assert(constraints.maxNumberLength == StreamReadConstraints.DEFAULT_MAX_NUM_LEN);
        assert(constraints.maxStringLength == StreamReadConstraints.DEFAULT_MAX_STRING_LEN);
    }
}

// Boot's SpringBeanHandlerInstantiator creates `@JsonSerialize(using = ...)` handlers as beans; Flint AOT
// instantiates them from the descriptors.
version (FlintJacksonHandlerInstantiator)
{
    @("JacksonAutoConfigurationTests.mapperHasASpringBeanHandlerInstantiator") unittest
    {
        import flint.boot.jackson : SpringBeanHandlerInstantiator;

        foreach (mapperType; [EnumMembers!MapperType])
            assert(cast(SpringBeanHandlerInstantiator) getMapper(mapperType).serializationConfig()
                    .getHandlerInstantiator() !is null);
    }
}
