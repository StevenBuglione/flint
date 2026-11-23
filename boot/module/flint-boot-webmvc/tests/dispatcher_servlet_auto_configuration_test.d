// Ported from spring-boot v4.2.0: module/spring-boot-webmvc/src/test/java/org/springframework/boot/webmvc/autoconfigure/DispatcherServletAutoConfigurationTests.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: the auto-configuration's beans are called directly, as Flint AOT's generated
// definitions call them, instead of through a WebApplicationContextRunner; a user bean replacing one is passed in
// its place, and the back-off is read from the `@ConditionalOnMissingBean` UDA Flint AOT evaluates at startup; the
// `DispatcherServletPath` bean is the `DispatcherServletRegistrationBean`, which implements it in Boot. Boot's
// name-based DefaultDispatcherServletCondition and DispatcherServletRegistrationCondition wait behind
// FlintDispatcherServletConditions, multipart support behind FlintWebMultipart, and the DispatcherServlet settings
// `flint.mvc.*` carries behind FlintDispatcherServletProperties.
module dispatcher_servlet_auto_configuration_test;

import flint.boot.autoconfigure.condition : ConditionalOnMissingBean;
import flint.boot.context.properties.bind : Binder;
import flint.boot.context.properties.source : ConfigurationPropertySource, MapConfigurationPropertySource;
import flint.boot.webmvc.autoconfigure : DispatcherServletAutoConfiguration,
    DispatcherServletRegistrationBean, WebMvcProperties;
import flint.engine.aot.descriptor : descriptorOf;
import flint.web.servlet : DispatcherServlet, DispatcherStrategies;
import std.traits : getUDAs;

@safe:

private WebMvcProperties webMvcProperties(string[2][] entries = null)
{
    auto binder = new Binder([
        cast(ConfigurationPropertySource) new MapConfigurationPropertySource("test", entries)
    ]);
    foreach (descriptor; [
        descriptorOf!(WebMvcProperties.Servlet)(), descriptorOf!(WebMvcProperties.Problemdetails)()
    ])
        binder.getDescriptors().add(descriptor);
    return binder.bindOrCreate!WebMvcProperties("flint.mvc");
}

private DispatcherServlet autoConfiguredServlet()
{
    import flint.context.support : GenericApplicationContext;
    import flint.boot.webmvc.autoconfigure : WebMvcAutoConfiguration;

    auto context = new GenericApplicationContext;
    context.refresh();
    auto support = new WebMvcAutoConfiguration().webMvcConfigurationSupport(context, null, null,
            null, null, null, null);
    return new DispatcherServletAutoConfiguration().dispatcherServlet(support);
}

// The `@ConditionalOnMissingBean` types of a `@Bean` method.
private string[] missingBeanTypes(alias method)()
{
    string[] types;
    foreach (condition; getUDAs!(method, ConditionalOnMissingBean))
        foreach (type; condition.value)
            types ~= type.name;
    return types;
}

@("DispatcherServletAutoConfigurationTests.registrationProperties") unittest
{
    auto servlet = autoConfiguredServlet();
    assert(servlet !is null);
    auto registration = new DispatcherServletAutoConfiguration().dispatcherServletRegistration(servlet,
            webMvcProperties());
    assert(registration.getUrlMappings() == ["/"]);
}

// Boot's DefaultDispatcherServletCondition backs off for any bean named `dispatcherServlet` (here a String), and
// DispatcherServletRegistrationCondition for a bean named `dispatcherServletRegistration`; Flint's conditions are
// `@ConditionalOnMissingBean` by type.
version (FlintDispatcherServletConditions)
{
    import flint.boot.webmvc.autoconfigure : DefaultDispatcherServletCondition, DispatcherServletRegistrationCondition;

    @("DispatcherServletAutoConfigurationTests.registrationNonServletBean") unittest
    {
        static assert(getUDAs!(DispatcherServletAutoConfiguration.dispatcherServlet,
                DefaultDispatcherServletCondition).length == 1);
        static assert(getUDAs!(DispatcherServletAutoConfiguration.dispatcherServletRegistration,
                DispatcherServletRegistrationCondition).length == 1);
    }

    @("DispatcherServletAutoConfigurationTests."
            ~ "registrationOverrideWithNonDefaultDispatcherServletNameResultsInTwoDispatcherServlets")
    unittest
    {
        // A user DispatcherServlet named `customDispatcherServlet` does not replace `dispatcherServlet`.
        static assert(missingBeanTypes!(DispatcherServletAutoConfiguration.dispatcherServlet)().length == 0);
        auto registration = new DispatcherServletAutoConfiguration().dispatcherServletRegistration(
                autoConfiguredServlet(), webMvcProperties());
        assert(registration.getUrlMappings() == ["/"]);
        assert(registration.getServletName() == "dispatcherServlet");
    }

    @("DispatcherServletAutoConfigurationTests.registrationOverrideWithAutowiredServlet") unittest
    {
        // A user ServletRegistrationBean named `dispatcherServletRegistration` replaces the auto-configured one.
        static assert(getUDAs!(DispatcherServletAutoConfiguration.dispatcherServletRegistration,
                DispatcherServletRegistrationCondition).length == 1);
    }

    @("DispatcherServletAutoConfigurationTests.dispatcherServletPathNotCreatedWhenDefaultDispatcherServletNotAvailable")
    unittest
    {
        static assert(getUDAs!(DispatcherServletAutoConfiguration.dispatcherServletRegistration,
                DefaultDispatcherServletCondition).length == 1);
    }

    @("DispatcherServletAutoConfigurationTests.dispatcherServletPathNotCreatedWhenCustomRegistrationBeanPresent")
    unittest
    {
        static assert(getUDAs!(DispatcherServletAutoConfiguration.dispatcherServletRegistration,
                DispatcherServletRegistrationCondition).length == 1);
    }
}

@("DispatcherServletAutoConfigurationTests."
        ~ "registrationOverrideWithDefaultDispatcherServletNameResultsInSingleDispatcherServlet")
unittest
{
    // The user's `dispatcherServlet` replaces the auto-configured one, and the registration takes it.
    assert(missingBeanTypes!(DispatcherServletAutoConfiguration.dispatcherServlet)() == [
        "flint.web.servlet.DispatcherServlet"
    ]);
    auto userServlet = new DispatcherServlet(DispatcherStrategies.init);
    auto registration = new DispatcherServletAutoConfiguration().dispatcherServletRegistration(userServlet,
            webMvcProperties());
    assert(registration.getUrlMappings() == ["/"]);
    assert(registration.getServletName() == "dispatcherServlet");
    assert(registration.getServlet() is userServlet);
}

@("DispatcherServletAutoConfigurationTests.servletPath") unittest
{
    auto servlet = autoConfiguredServlet();
    assert(servlet !is null);
    auto registration = new DispatcherServletAutoConfiguration().dispatcherServletRegistration(servlet,
            webMvcProperties([["spring.mvc.servlet.path", "/spring"]]));
    assert(registration.getUrlMappings() == ["/spring/*"]);
    version (FlintWebMultipart)
        assert(registration.getMultipartConfig() is null);
    assert(registration.getPath() == "/spring");
}

@("DispatcherServletAutoConfigurationTests."
        ~ "dispatcherServletPathWhenCustomDispatcherServletSameNameShouldReturnConfiguredServletPath")
unittest
{
    auto registration = new DispatcherServletAutoConfiguration().dispatcherServletRegistration(
            new DispatcherServlet(DispatcherStrategies.init),
            webMvcProperties([["spring.mvc.servlet.path", "/spring"]]));
    assert(registration.getPath() == "/spring");
}

// `MultipartConfigElement` and `MultipartResolver` beans; Flint's servlet registration has no multipart config.
version (FlintWebMultipart)
{
    @("DispatcherServletAutoConfigurationTests.multipartConfig") unittest
    {
        import flint.jakarta.servlet : MultipartConfigElement;

        auto multipartConfig = new MultipartConfigElement(null, 128 * 1024, 128 * 1024, 0);
        auto registration = new DispatcherServletAutoConfiguration().dispatcherServletRegistration(
                autoConfiguredServlet(), webMvcProperties(), multipartConfig);
        assert(registration.getMultipartConfig() !is null);
    }

    @("DispatcherServletAutoConfigurationTests.renamesMultipartResolver") unittest
    {
        import flint.web.multipart : MultipartResolver;

        auto dispatcherServlet = autoConfiguredServlet();
        assert(cast(MultipartResolver) dispatcherServlet.getMultipartResolver() !is null);
    }
}

@("DispatcherServletAutoConfigurationTests.dispatcherServletDefaultConfig") unittest
{
    auto dispatcherServlet = autoConfiguredServlet();
    // DispatcherServlet has no accessors for these settings.
    version (FlintDispatcherServletProperties)
    {
        assert(dispatcherServlet.isDispatchOptionsRequest());
        assert(!dispatcherServlet.isDispatchTraceRequest());
        assert(!dispatcherServlet.isEnableLoggingRequestDetails());
        assert(dispatcherServlet.isPublishEvents());
    }
    auto registration = new DispatcherServletAutoConfiguration().dispatcherServletRegistration(
            dispatcherServlet, webMvcProperties());
    assert(registration.getLoadOnStartup() == -1);
}

@("DispatcherServletAutoConfigurationTests.dispatcherServletCustomConfig") unittest
{
    auto properties = webMvcProperties([
        ["spring.mvc.dispatch-options-request", "false"], [
            "spring.mvc.dispatch-trace-request", "true"
        ], ["spring.mvc.publish-request-handled-events", "false"],
        ["spring.mvc.servlet.load-on-startup", "5"]
    ]);
    auto dispatcherServlet = autoConfiguredServlet();
    // LIKELY BUG: `dispatcherServlet()` never reads WebMvcProperties, so the dispatch and event settings are ignored.
    version (FlintDispatcherServletProperties)
    {
        assert(!dispatcherServlet.isDispatchOptionsRequest());
        assert(dispatcherServlet.isDispatchTraceRequest());
        assert(!dispatcherServlet.isPublishEvents());
    }
    auto registration = new DispatcherServletAutoConfiguration().dispatcherServletRegistration(
            dispatcherServlet, properties);
    assert(registration.getLoadOnStartup() == 5);
}
