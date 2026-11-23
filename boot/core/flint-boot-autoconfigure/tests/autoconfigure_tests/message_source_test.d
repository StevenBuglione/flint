// Ported from spring-boot v4.2.0: core/spring-boot-autoconfigure/src/test/java/org/springframework/boot/autoconfigure/context/MessageSourceAutoConfigurationTests.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: the auto-configuration's beans are called directly, as Flint AOT's generated
// definitions call them, instead of through an ApplicationContextRunner; the bundle-content cases need embedded
// resources and run with an application.
module autoconfigure_tests.message_source_test;

import flint.boot.autoconfigure.context : MessageSourceAutoConfiguration, MessageSourceProperties;
import flint.boot.context.properties.bind : Binder;
import flint.boot.context.properties.source : ConfigurationPropertySource, MapConfigurationPropertySource;
import flint.context.support : ResourceBundleMessageSource;
import flint.java.util : Locale;

@safe:

private ResourceBundleMessageSource messageSource(string[2][] entries)
{
    import core.time : Duration;
    import flint.engine.aot.descriptor : descriptorOf;
    import flint.java.util : Optional;

    auto binder = new Binder([
        cast(ConfigurationPropertySource) new MapConfigurationPropertySource("test", entries)
    ]);
    binder.getDescriptors().add(descriptorOf!(Optional!Duration)());
    binder.getDescriptors().add(descriptorOf!(string[])());
    auto properties = binder.bindOrCreate!MessageSourceProperties("flint.messages");
    auto configuration = new MessageSourceAutoConfiguration;
    return configuration.messageSource(configuration.resourceBasedMessageSourceConfigurer(properties));
}

@("propertiesDefaults: basename messages, UTF-8, system-locale fallback") unittest
{
    auto properties = new MessageSourceProperties;
    assert(properties.getBasename() == ["messages"]);
    assert(properties.getEncoding() == "UTF-8");
    assert(properties.isFallbackToSystemLocale());
    assert(!properties.isAlwaysUseMessageFormat() && !properties.isUseCodeAsDefaultMessage());
    assert(properties.getCacheDuration().isEmpty());
}

@("testMultipleMessageSourceCreated: comma-separated basenames") unittest
{
    import std.conv : to;

    const set = messageSource([["spring.messages.basename", "test/messages,test/messages2"]]).getBasenameSet();
    assert(set == ["test/messages", "test/messages2"], set.to!string);
}

@("testUseCodeAsDefaultMessage") unittest
{
    auto source = messageSource([["flint.messages.use-code-as-default-message", "true"]]);
    assert(source.getMessage("foo", null, Locale.US) == "foo");
}

@("a missing code without a bundle takes the default message") unittest
{
    assert(messageSource(null).getMessage("foo", null, "Foo message", Locale.US) == "Foo message");
}
