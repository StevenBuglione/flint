/// Flint tests: `server.*` carries Boot's defaults and binds with Boot's keys.
module server_properties_test;

import flint.boot.context.properties.bind : Binder;
import flint.boot.context.properties.source : ConfigurationPropertySource, MapConfigurationPropertySource;
import flint.boot.web.server : Compression, Http2, Shutdown;
import flint.boot.web.server.autoconfigure : ServerProperties;
import flint.engine.aot.descriptor : descriptorOf;
import flint.java.util : Optional;

@safe:

unittest
{
    auto properties = new ServerProperties;
    assert(properties.getPort().isEmpty());
    assert(properties.getShutdown() == Shutdown.GRACEFUL);
    assert(!properties.getCompression().isEnabled());
    assert(properties.getCompression().getMimeTypes().length == 8);
    assert(properties.getServlet().getApplicationDisplayName() == "application");
    assert(properties.getServlet().getContextPath() is null);
    assert(properties.getFlint().getThreads() == 0);
}

unittest
{
    auto source = new MapConfigurationPropertySource("test", [
        ["server.address", "127.0.0.1"], ["server.shutdown", "immediate"],
        ["server.compression.enabled", "true"], ["server.servlet.context-path", "/api"],
        ["SERVER_HTTP2_ENABLED", "true"], ["server.port", "8081"], ["server.flint.threads", "3"]
    ]);
    auto binder = new Binder([cast(ConfigurationPropertySource) source]);
    foreach (descriptor; [
        descriptorOf!Shutdown(), descriptorOf!Compression(), descriptorOf!Http2(),
        descriptorOf!(ServerProperties.Servlet)(), descriptorOf!(ServerProperties.Flint)(),
        descriptorOf!(Optional!int)()
    ])
        binder.getDescriptors().add(descriptor);
    auto properties = binder.bind!ServerProperties("server").get();
    assert(properties.getAddress() == "127.0.0.1");
    assert(properties.getShutdown() == Shutdown.IMMEDIATE);
    assert(properties.getCompression().isEnabled());
    assert(properties.getServlet().getContextPath() == "/api");
    assert(properties.getPort().get() == 8081);
    assert(properties.getFlint().getThreads() == 3);
}
