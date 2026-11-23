// Ported from spring-boot v4.2.0: module/spring-boot-web-server/src/test/java/org/springframework/boot/web/server/autoconfigure/ServerPropertiesTests.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: the upstream tests, next to server_properties_test.d's Flint defaults and binding
// tests; `Bindable.ofInstance` is `Binder.bind` with the `server` descriptors; `InetAddress address` is the address
// text. `server.mime-mappings`, `server.max-http-request-header-size` (`DataSize`) and
// `Compression.getAllMimeTypes` wait behind FlintServerMimeMappings, FlintDataSize and FlintCompressionAllMimeTypes.
module server_properties_upstream_test;

import flint.boot.context.properties.bind : Binder;
import flint.boot.context.properties.source : ConfigurationPropertySource, MapConfigurationPropertySource;
import flint.boot.web.server : Compression, Http2, Shutdown;
import flint.boot.web.server.autoconfigure : ServerProperties;
import flint.engine.aot.descriptor : descriptorOf;
import flint.java.util : Optional;

@safe:

private ServerProperties bind(string name, string value)
{
    auto binder = new Binder([
        cast(ConfigurationPropertySource) new MapConfigurationPropertySource("test", [[name, value]])
    ]);
    foreach (descriptor; [
        descriptorOf!Shutdown(), descriptorOf!Compression(), descriptorOf!Http2(),
        descriptorOf!(ServerProperties.Servlet)(), descriptorOf!(Optional!int)(),
        descriptorOf!(string[])()
    ])
        binder.getDescriptors().add(descriptor);
    return binder.bindOrCreate!ServerProperties("server");
}

@("ServerPropertiesTests.testAddressBinding") unittest
{
    assert(bind("server.address", "127.0.0.1").getAddress() == "127.0.0.1");
}

@("ServerPropertiesTests.testPortBinding") unittest
{
    const port = bind("server.port", "9000").getPort();
    assert(port.isPresent());
    assert(port.get() == 9000);
}

@("ServerPropertiesTests.testServerHeaderDefault") unittest
{
    assert(new ServerProperties().getServerHeader() is null);
}

@("ServerPropertiesTests.testServerHeader") unittest
{
    assert(bind("server.server-header", "Custom Server").getServerHeader() == "Custom Server");
}

@("ServerPropertiesTests.testTrailingSlashOfContextPathIsRemoved") unittest
{
    assert(bind("server.servlet.context-path", "/foo/").getServlet().getContextPath() == "/foo");
}

@("ServerPropertiesTests.testSlashOfContextPathIsDefaultValue") unittest
{
    assert(bind("server.servlet.context-path", "/").getServlet().getContextPath().length == 0);
}

@("ServerPropertiesTests.testContextPathWithLeadingWhitespace") unittest
{
    assert(bind("server.servlet.context-path", " /assets").getServlet().getContextPath() == "/assets");
}

@("ServerPropertiesTests.testContextPathWithTrailingWhitespace") unittest
{
    assert(bind("server.servlet.context-path", "/assets/copy/ ").getServlet().getContextPath() == "/assets/copy");
}

@("ServerPropertiesTests.testContextPathWithLeadingAndTrailingWhitespace") unittest
{
    assert(bind("server.servlet.context-path", " /assets ").getServlet().getContextPath() == "/assets");
}

@("ServerPropertiesTests.testContextPathWithLeadingAndTrailingWhitespaceAndContextWithSpace") unittest
{
    const contextPath = bind("server.servlet.context-path", "  /assets /copy/    ").getServlet().getContextPath();
    assert(contextPath == "/assets /copy");
}

// `server.mime-mappings` (MimeMappings) follows with the servlet container settings.
version (FlintServerMimeMappings)
{
    @("ServerPropertiesTests.testDefaultMimeMapping") unittest
    {
        assert(new ServerProperties().getMimeMappings().isEmpty());
    }

    @("ServerPropertiesTests.testCustomizedMimeMapping") unittest
    {
        import flint.boot.web.server : MimeMappings;

        auto expectedMappings = new MimeMappings;
        expectedMappings.add("mjs", "text/javascript");
        assert(bind("server.mime-mappings.mjs", "text/javascript").getMimeMappings()
                .getAll() == expectedMappings.getAll());
    }
}

// `server.max-http-request-header-size` is a `DataSize`, which flint:core does not have yet.
version (FlintDataSize)
{
    import flint.util.unit : DataSize;

    @("ServerPropertiesTests.testCustomizeMaxHttpRequestHeaderSize") unittest
    {
        assert(bind("server.max-http-request-header-size", "1MB")
                .getMaxHttpRequestHeaderSize() == DataSize.ofMegabytes(1));
    }

    @("ServerPropertiesTests.testCustomizeMaxHttpRequestHeaderSizeUseBytesByDefault") unittest
    {
        assert(bind("server.max-http-request-header-size", "1024")
                .getMaxHttpRequestHeaderSize() == DataSize.ofKilobytes(1));
    }

    @("ServerPropertiesTests.defaultMaxHttpRequestHeaderSizeMatchesTomcatsDefault") unittest
    {
        // Tomcat's `Http11Nio2Protocol.getMaxHttpRequestHeaderSize()`: 8 KiB.
        assert(new ServerProperties().getMaxHttpRequestHeaderSize().toBytes() == 8192);
    }
}

// `Compression.getAllMimeTypes()`: the MIME types with `additional-mime-types` appended.
version (FlintCompressionAllMimeTypes)
{
    @("ServerPropertiesTests.additionalCompressionMimeTypesAreAddedToDefaults") unittest
    {
        import std.algorithm.searching : canFind;

        auto all = bind("server.compression.additional-mime-types", "application/zip").getCompression()
            .getAllMimeTypes();
        foreach (type; new Compression().getMimeTypes())
            assert(all.canFind(type));
        assert(all.canFind("application/zip"));
    }
}
