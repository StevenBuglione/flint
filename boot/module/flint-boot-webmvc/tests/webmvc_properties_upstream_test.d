// Ported from spring-boot v4.2.0: module/spring-boot-webmvc/src/test/java/org/springframework/boot/webmvc/autoconfigure/WebMvcPropertiesTests.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: the upstream tests, next to webmvc_properties_test.d's Flint defaults and binding
// tests; `Bindable.ofInstance` is `Binder.bind` with `flint.mvc` descriptors. `Servlet.getServletMapping`,
// `getServletPrefix` and the wildcard check of `setPath` wait behind FlintWebMvcServletMapping.
module webmvc_properties_upstream_test;

@safe:

// WebMvcProperties.Servlet derives its mapping and prefix from the path and rejects wildcards; Flint's keeps the path.
version (FlintWebMvcServletMapping)
{
    import flint.boot.context.properties.bind : BindException, Binder;
    import flint.boot.context.properties.source : ConfigurationPropertySource, MapConfigurationPropertySource;
    import flint.boot.webmvc.autoconfigure : WebMvcProperties;
    import flint.engine.aot.descriptor : descriptorOf;

    private WebMvcProperties bind(string name, string value)
    {
        auto binder = new Binder([
            cast(ConfigurationPropertySource) new MapConfigurationPropertySource("test", [
                [name, value]
            ])
        ]);
        binder.getDescriptors().add(descriptorOf!(WebMvcProperties.Servlet)());
        return binder.bind!WebMvcProperties("flint.mvc").get();
    }

    @("WebMvcPropertiesTests.servletPathWhenEndsWithSlashHasValidMappingAndPrefix") unittest
    {
        auto properties = bind("spring.mvc.servlet.path", "/foo/");
        assert(properties.getServlet().getServletMapping() == "/foo/*");
        assert(properties.getServlet().getServletPrefix() == "/foo");
    }

    @("WebMvcPropertiesTests.servletPathWhenDoesNotEndWithSlashHasValidMappingAndPrefix") unittest
    {
        auto properties = bind("spring.mvc.servlet.path", "/foo");
        assert(properties.getServlet().getServletMapping() == "/foo/*");
        assert(properties.getServlet().getServletPrefix() == "/foo");
    }

    @("WebMvcPropertiesTests.servletPathWhenHasWildcardThrowsException") unittest
    {
        import std.algorithm.searching : canFind;

        bool thrown;
        try
            bind("spring.mvc.servlet.path", "/*");
        catch (BindException e)
            thrown = e.next !is null && e.next.msg.canFind("'path' must not contain wildcards");
        assert(thrown);
    }
}
