// Ported from spring-boot v4.2.0: module/spring-boot-web-server/src/test/java/org/springframework/boot/web/server/autoconfigure/servlet/ServletWebServerFactoryCustomizerTests.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: the mocked `ConfigurableServletWebServerFactory` is web_server_test_support's
// recording `MockServletWebServerFactory`; Flint's customizer takes the properties alone (no environment,
// customizers or SSL bundles). The display name, default servlet, SSL, JSP and locale charset settings wait behind
// FlintServletWebServerFactorySettings, MIME mappings behind FlintServerMimeMappings, and the session behind
// FlintServletSession.
module servlet_web_server_factory_customizer_test;

import flint.boot.context.properties.bind : Binder;
import flint.boot.context.properties.source : ConfigurationPropertySource, MapConfigurationPropertySource;
import flint.boot.web.server : Compression, Http2, Shutdown;
import flint.boot.web.server.autoconfigure : ServerProperties, ServletWebServerFactoryCustomizer;
import flint.engine.aot.descriptor : descriptorOf;
import flint.java.util : Optional;
import web_server_test_support : MockServletWebServerFactory;

@safe:

private ServerProperties bindProperties(string[2][] map)
{
    auto binder = new Binder([
        cast(ConfigurationPropertySource) new MapConfigurationPropertySource("test", map)
    ]);
    foreach (descriptor; [
        descriptorOf!Shutdown(), descriptorOf!Compression(), descriptorOf!Http2(),
        descriptorOf!(ServerProperties.Servlet)(), descriptorOf!(Optional!int)()
    ])
        binder.getDescriptors().add(descriptor);
    return binder.bindOrCreate!ServerProperties("server");
}

// The factory settings Boot's customizer applies beyond the port, address, context path and shutdown.
version (FlintServletWebServerFactorySettings)
{
    @("ServletWebServerFactoryCustomizerTests.testDefaultDisplayName") unittest
    {
        auto factory = new MockServletWebServerFactory;
        new ServletWebServerFactoryCustomizer(new ServerProperties).customize(factory);
        assert(factory.getDisplayName() == "application");
    }

    @("ServletWebServerFactoryCustomizerTests.testCustomizeDisplayName") unittest
    {
        auto properties = new ServerProperties;
        properties.getServlet().setApplicationDisplayName("TestName");
        auto factory = new MockServletWebServerFactory;
        new ServletWebServerFactoryCustomizer(properties).customize(factory);
        assert(factory.getDisplayName() == "TestName");
    }

    @("ServletWebServerFactoryCustomizerTests.testCustomizeDefaultServlet") unittest
    {
        auto properties = new ServerProperties;
        properties.getServlet().setRegisterDefaultServlet(false);
        auto factory = new MockServletWebServerFactory;
        new ServletWebServerFactoryCustomizer(properties).customize(factory);
        assert(!factory.isRegisterDefaultServlet());
    }

    @("ServletWebServerFactoryCustomizerTests.testCustomizeSsl") unittest
    {
        import flint.boot.web.server : Ssl;

        auto properties = new ServerProperties;
        auto ssl = new Ssl;
        properties.setSsl(ssl);
        auto factory = new MockServletWebServerFactory;
        new ServletWebServerFactoryCustomizer(properties).customize(factory);
        assert(factory.getSsl() is ssl);
    }

    @("ServletWebServerFactoryCustomizerTests.testCustomizeJsp") unittest
    {
        auto factory = new MockServletWebServerFactory;
        new ServletWebServerFactoryCustomizer(new ServerProperties).customize(factory);
        assert(factory.getJsp() !is null);
    }

    @("ServletWebServerFactoryCustomizerTests.customizeServletDisplayName") unittest
    {
        auto factory = new MockServletWebServerFactory;
        new ServletWebServerFactoryCustomizer(bindProperties([
                ["server.servlet.application-display-name", "MyBootApp"]
        ])).customize(factory);
        assert(factory.getDisplayName() == "MyBootApp");
    }

    @("ServletWebServerFactoryCustomizerTests.noLocaleCharsetMapping") unittest
    {
        auto factory = new MockServletWebServerFactory;
        new ServletWebServerFactoryCustomizer(new ServerProperties).customize(factory);
        assert(factory.getLocaleCharsetMappings() is null);
    }

    @("ServletWebServerFactoryCustomizerTests.customLocaleCharsetMappings") unittest
    {
        auto factory = new MockServletWebServerFactory;
        new ServletWebServerFactoryCustomizer(bindProperties([
                ["server.servlet.encoding.mapping.en", "UTF-8"],
                ["server.servlet.encoding.mapping.fr_FR", "UTF-8"]
        ])).customize(factory);
        assert(factory.getLocaleCharsetMappings().length == 2);
    }
}

// `server.mime-mappings`.
version (FlintServerMimeMappings)
{
    @("ServletWebServerFactoryCustomizerTests.withNoCustomMimeMappingsThenEmptyMimeMappingsIsAdded") unittest
    {
        auto factory = new MockServletWebServerFactory;
        new ServletWebServerFactoryCustomizer(new ServerProperties).customize(factory);
        assert(factory.getMimeMappings().getAll().length == 0);
    }

    @("ServletWebServerFactoryCustomizerTests.withCustomMimeMappingsThenPopulatedMimeMappingsIsAdded") unittest
    {
        auto properties = new ServerProperties;
        properties.getMimeMappings().add("a", "alpha");
        properties.getMimeMappings().add("b", "bravo");
        auto factory = new MockServletWebServerFactory;
        new ServletWebServerFactoryCustomizer(properties).customize(factory);
        assert(factory.getMimeMappings().getAll().length == 2);
    }
}

// `server.servlet.session.*`.
version (FlintServletSession)
{
    @("ServletWebServerFactoryCustomizerTests.customizeSessionProperties") unittest
    {
        auto factory = new MockServletWebServerFactory;
        new ServletWebServerFactoryCustomizer(bindProperties([
                ["server.servlet.session.timeout", "123"],
                ["server.servlet.session.tracking-modes", "cookie,url"],
                ["server.servlet.session.cookie.name", "testname"],
                ["server.servlet.session.cookie.domain", "testdomain"],
                ["server.servlet.session.cookie.path", "/testpath"],
                ["server.servlet.session.cookie.http-only", "true"],
                ["server.servlet.session.cookie.secure", "true"],
                ["server.servlet.session.cookie.max-age", "60"]
        ])).customize(factory);
        auto session = factory.getSession();
        assert(session.getTimeout().total!"seconds" == 123);
        auto cookie = session.getCookie();
        assert(cookie.getName() == "testname" && cookie.getDomain() == "testdomain");
        assert(cookie.getPath() == "/testpath" && cookie.getHttpOnly());
        assert(cookie.getMaxAge().total!"seconds" == 60);
    }

    @("ServletWebServerFactoryCustomizerTests.sessionStoreDir") unittest
    {
        auto factory = new MockServletWebServerFactory;
        new ServletWebServerFactoryCustomizer(bindProperties([
                ["server.servlet.session.store-dir", "mydirectory"]
        ])).customize(factory);
        assert(factory.getSession().getStoreDir() == "mydirectory");
    }
}

@("ServletWebServerFactoryCustomizerTests.testCustomizeTomcatPort") unittest
{
    auto properties = new ServerProperties;
    properties.setPort(Optional!int.of(8080));
    auto factory = new MockServletWebServerFactory;
    factory.port = -1;
    new ServletWebServerFactoryCustomizer(properties).customize(factory);
    assert(factory.port == 8080);
}

@("ServletWebServerFactoryCustomizerTests.whenShutdownPropertyIsSetThenShutdownIsCustomized") unittest
{
    auto factory = new MockServletWebServerFactory;
    new ServletWebServerFactoryCustomizer(bindProperties([["server.shutdown", "immediate"]])).customize(factory);
    assert(factory.shutdown == Shutdown.IMMEDIATE);
}
