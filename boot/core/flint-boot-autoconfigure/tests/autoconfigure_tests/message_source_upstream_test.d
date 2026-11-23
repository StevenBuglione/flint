// Ported from spring-boot v4.2.0: core/spring-boot-autoconfigure/src/test/java/org/springframework/boot/autoconfigure/context/MessageSourceAutoConfigurationTests.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: the test methods message_source_test.d does not port (it holds
// testDefaultMessageSource, testMultipleMessageSourceCreated and testUseCodeAsDefaultMessageOn); the
// auto-configuration's beans are called directly, as Flint AOT's generated definitions call them, and back-off is
// read from the `@ConditionalOnMissingBean` UDAs Flint AOT evaluates; `@WithResource` files are served by a
// ProtocolResolver on the message source's ResourceLoader; the settings `hasFieldOrPropertyWithValue` reads are
// read through a ResourceBundleMessageSource subclass the configurer configures, as `messageSource()` does; the
// user-defined ReloadableResourceBundleMessageSource is that subclass. Boot's ResourceBundleCondition waits behind
// FlintResourceBundleCondition, `common-messages` behind FlintMessageSourceCommonMessages, and the condition's
// `SearchStrategy.CURRENT` behind FlintMessageSourceSearchCurrent. Not ported:
// testMessageSourceFromPropertySourceAnnotation (`@Disabled` upstream) and shouldRegisterDefaultHints (GraalVM
// `RuntimeHints`).
module autoconfigure_tests.message_source_upstream_test;

import flint.boot.autoconfigure.condition : ConditionalOnMissingBean;
import flint.boot.autoconfigure.context : MessageSourceAutoConfiguration, MessageSourceProperties,
    ResourceBasedMessageSourceConfigurer;
import flint.boot.context.properties.bind : Binder;
import flint.boot.context.properties.source : ConfigurationPropertySource, MapConfigurationPropertySource;
import flint.context.support : ResourceBundleMessageSource;
import flint.core.io : ByteArrayResource, DefaultResourceLoader, ProtocolResolver, Resource, ResourceLoader;
import flint.java.util : Locale;
import std.traits : getUDAs, hasUDA;

@safe:

// `@WithResource(name = ..., content = ...)`: serves the named files.
private final class WithResources : ProtocolResolver
{
    private string[string] files;

    this(string[string] files) pure nothrow @nogc
    {
        this.files = files;
    }

    Resource resolve(string location, ResourceLoader)
    {
        import std.algorithm.searching : startsWith;

        const name = location.startsWith("classpath:") ? location["classpath:".length .. $] : location;
        if (auto content = name in files)
            return new ByteArrayResource(cast(immutable(ubyte)[])*content, name);
        return null;
    }
}

private string[string] withTestMessagesPropertiesResource()
{
    return ["test/messages.properties": "foo=bar"];
}

/// A ResourceBundleMessageSource whose settings can be read.
final class InspectableMessageSource : ResourceBundleMessageSource
{
    /// `cacheMillis`.
    long cacheMillis()
    {
        return getCacheMillis();
    }

    /// `fallbackToSystemLocale`.
    bool fallbackToSystemLocale()
    {
        return isFallbackToSystemLocale();
    }

    /// `alwaysUseMessageFormat`.
    bool alwaysUseMessageFormat()
    {
        return isAlwaysUseMessageFormat();
    }

    /// `useCodeAsDefaultMessage`.
    bool useCodeAsDefaultMessage()
    {
        return isUseCodeAsDefaultMessage();
    }
}

private MessageSourceProperties properties(string[2][] entries)
{
    import core.time : Duration;
    import flint.engine.aot.descriptor : descriptorOf;
    import flint.java.util : Optional;

    auto binder = new Binder([
        cast(ConfigurationPropertySource) new MapConfigurationPropertySource("test", entries)
    ]);
    binder.getDescriptors().add(descriptorOf!(Optional!Duration)());
    binder.getDescriptors().add(descriptorOf!(string[])());
    return binder.bindOrCreate!MessageSourceProperties("flint.messages");
}

// `withPropertyValues(entries)` with the `files` resources: the auto-configured `messageSource`, configured by the
// auto-configured configurer.
private InspectableMessageSource messageSource(string[2][] entries, string[string] files = null)
{
    auto configuration = new MessageSourceAutoConfiguration;
    auto source = new InspectableMessageSource;
    auto loader = new DefaultResourceLoader;
    loader.addProtocolResolver(new WithResources(files));
    source.setResourceLoader(loader);
    configuration.resourceBasedMessageSourceConfigurer(properties(entries)).configure(source);
    return source;
}

// Boot creates the ResourceBundleMessageSource only when a bundle for the basename exists; Flint AOT's startup
// conditions do not read resources, so it is always created.
version (FlintResourceBundleCondition)
{
    @("MessageSourceAutoConfigurationTests.resourceBasedMessageSourceConfigurerIsAvailableWithoutResourceBundle")
    unittest
    {
        import flint.boot.autoconfigure.context : ResourceBundleCondition;

        assert(new MessageSourceAutoConfiguration().resourceBasedMessageSourceConfigurer(properties(null)) !is null);
        static assert(hasUDA!(MessageSourceAutoConfiguration.messageSource, ResourceBundleCondition));
    }
}

@("MessageSourceAutoConfigurationTests.resourceBasedMessageSourceConfigurerCanConfigureUserDefinedMessageSource")
unittest
{
    auto configurer = new MessageSourceAutoConfiguration().resourceBasedMessageSourceConfigurer(
            properties([
            ["spring.messages.cache-duration", "10s"],
            ["spring.messages.fallback-to-system-locale", "false"],
            ["spring.messages.always-use-message-format", "true"],
            ["spring.messages.use-code-as-default-message", "true"]
    ]));
    auto userMessageSource = new InspectableMessageSource;
    configurer.configure(userMessageSource);
    assert(userMessageSource.cacheMillis() == 10_000L);
    assert(!userMessageSource.fallbackToSystemLocale());
    assert(userMessageSource.alwaysUseMessageFormat());
    assert(userMessageSource.useCodeAsDefaultMessage());
}

// A ResourceBasedMessageSourceConfigurer that records what it configured.
private final class RecordingConfigurer : ResourceBasedMessageSourceConfigurer
{
    imported!"flint.context.support".AbstractResourceBasedMessageSource configured;

    this()
    {
        super(new MessageSourceProperties);
    }

    override void configure(imported!"flint.context.support".AbstractResourceBasedMessageSource messageSource)
    {
        configured = messageSource;
    }
}

@("MessageSourceAutoConfigurationTests.autoConfiguredMessageSourceUsesUserDefinedConfigurer") unittest
{
    static assert(hasUDA!(MessageSourceAutoConfiguration.resourceBasedMessageSourceConfigurer,
            ConditionalOnMissingBean));
    auto configurer = new RecordingConfigurer;
    const source = new MessageSourceAutoConfiguration().messageSource(configurer);
    assert(configurer.configured is source);
}

@("MessageSourceAutoConfigurationTests.propertiesBundleWithSlashIsDetected") unittest
{
    auto source = messageSource([["spring.messages.basename", "test/messages"]], withTestMessagesPropertiesResource);
    assert(source.getMessage("foo", null, "Foo message", Locale.UK) == "bar");
}

// LIKELY BUG: Java's ResourceBundle reads the basename `test.messages` as `test/messages.properties`; Flint's
// ResourceBundleMessageSource looks for `test.messages.properties` and answers the default message.
version (FlintMessageSourceDottedBasename)
{
    @("MessageSourceAutoConfigurationTests.propertiesBundleWithDotIsDetected") unittest
    {
        string[2][] entries = [["spring.messages.basename", "test.messages"]];
        auto source = messageSource(entries, withTestMessagesPropertiesResource);
        const message = source.getMessage("foo", null, "Foo message", Locale.UK);
        assert(message == "bar", message);
    }
}

@("MessageSourceAutoConfigurationTests.testEncodingWorks") unittest
{
    auto source = messageSource([["spring.messages.basename", "test/swedish"]],
            ["test/swedish.properties": "foo=Some text with some swedish öäå!"]);
    assert(source.getMessage("foo", null, "Foo message", Locale.UK) == "Some text with some swedish öäå!");
}

@("MessageSourceAutoConfigurationTests.testCacheDurationNoUnit") unittest
{
    assert(messageSource([
            ["spring.messages.basename", "test/messages"], ["spring.messages.cache-duration", "10"]
    ], withTestMessagesPropertiesResource).cacheMillis() == 10 * 1000);
}

@("MessageSourceAutoConfigurationTests.testCacheDurationWithUnit") unittest
{
    assert(messageSource([
            ["spring.messages.basename", "test/messages"], ["spring.messages.cache-duration", "1m"]
    ], withTestMessagesPropertiesResource).cacheMillis() == 60 * 1000);
}

// `flint.messages.common-messages`: the configurer does not load them yet.
version (FlintMessageSourceCommonMessages)
{
    @("MessageSourceAutoConfigurationTests.testCommonMessages") unittest
    {
        auto source = messageSource([
            ["spring.messages.basename", "test/messages"],
            ["spring.messages.common-messages", "classpath:test/common-messages.properties"]
        ], ["test/messages.properties": "foo=bar", "test/common-messages.properties": "hello=world"]);
        assert(source.getMessage("hello", null, "Hello!", Locale.UK) == "world");
    }

    @("MessageSourceAutoConfigurationTests.testCommonMessagesWhenNotFound") unittest
    {
        import std.algorithm.searching : canFind;

        string message;
        try
            cast(void) messageSource([
                ["spring.messages.basename", "test/messages"],
                ["spring.messages.common-messages", "classpath:test/common-messages.properties"]
        ], withTestMessagesPropertiesResource);
        catch (Exception e)
            message = e.msg.idup;
        assert(message.canFind(
                "Failed to load common messages from 'class path resource [test/common-messages.properties]'"));
    }
}

@("MessageSourceAutoConfigurationTests.testFallbackDefault") unittest
{
    assert(messageSource([["spring.messages.basename", "test/messages"]],
            withTestMessagesPropertiesResource).fallbackToSystemLocale());
}

@("MessageSourceAutoConfigurationTests.testFallbackTurnOff") unittest
{
    assert(!messageSource([
            ["spring.messages.basename", "test/messages"],
            ["spring.messages.fallback-to-system-locale", "false"]
    ], withTestMessagesPropertiesResource).fallbackToSystemLocale());
}

@("MessageSourceAutoConfigurationTests.testFormatMessageDefault") unittest
{
    assert(!messageSource([["spring.messages.basename", "test/messages"]],
            withTestMessagesPropertiesResource).alwaysUseMessageFormat());
}

@("MessageSourceAutoConfigurationTests.testFormatMessageOn") unittest
{
    assert(messageSource([
            ["spring.messages.basename", "test/messages"],
            ["spring.messages.always-use-message-format", "true"]
    ], withTestMessagesPropertiesResource).alwaysUseMessageFormat());
}

@("MessageSourceAutoConfigurationTests.testUseCodeAsDefaultMessageDefault") unittest
{
    assert(!messageSource([["spring.messages.basename", "test/messages"]],
            withTestMessagesPropertiesResource).useCodeAsDefaultMessage());
}

/// `TestMessageSource`: every message is its code.
final class TestMessageSource : imported!"flint.context".MessageSource
{
    string getMessage(string code, imported!"flint.engine.aot.any".Any[], string, Locale)
    {
        return code;
    }

    string getMessage(string code, imported!"flint.engine.aot.any".Any[], Locale)
    {
        return code;
    }

    string getMessage(imported!"flint.context".MessageSourceResolvable resolvable, Locale)
    {
        return resolvable.getCodes()[0];
    }
}

// `@ConditionalOnMissingBean(name = "messageSource")` on the auto-configured source.
private ConditionalOnMissingBean messageSourceCondition()
{
    static foreach (attribute; __traits(getAttributes, MessageSourceAutoConfiguration.messageSource))
        static if (is(typeof(attribute) == ConditionalOnMissingBean))
            return attribute;
}

@("MessageSourceAutoConfigurationTests.existingMessageSourceIsPreferred") unittest
{
    import flint.context.support : GenericApplicationContext;

    assert(messageSourceCondition().name == ["messageSource"]);
    auto context = new GenericApplicationContext;
    context.getBeanFactory().registerSingleton("messageSource", new TestMessageSource);
    context.refresh();
    scope (exit)
        context.close();
    assert(context.getMessage("foo", null, null, Locale.init) == "foo");
}

// Boot looks for the `messageSource` bean in the current context only (`search = SearchStrategy.CURRENT`), so one in
// a parent context does not stop the child's; Flint's condition searches the whole hierarchy.
version (FlintMessageSourceSearchCurrent)
{
    @("MessageSourceAutoConfigurationTests.existingMessageSourceInParentIsIgnored") unittest
    {
        import flint.boot.autoconfigure.condition : SearchStrategy;

        assert(messageSourceCondition().search == SearchStrategy.CURRENT);
        assert(messageSource([["spring.messages.basename", "test/messages"]],
                withTestMessagesPropertiesResource).getMessage("foo", null, "Foo message", Locale.UK) == "bar");
    }
}

@("MessageSourceAutoConfigurationTests.messageSourceWithNonStandardBeanNameIsIgnored") unittest
{
    // A user MessageSource named `codeReturningMessageSource` does not match the `messageSource` name condition.
    assert(messageSourceCondition().name == ["messageSource"] && messageSourceCondition().value.length == 0);
    auto source = messageSource([["spring.messages.basename", "test/messages"]], withTestMessagesPropertiesResource);
    assert(source.getMessage("foo", null, Locale.US) == "bar");
}
