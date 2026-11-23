// Ported from spring-boot v4.2.0: module/spring-boot-webmvc/src/test/java/org/springframework/boot/webmvc/autoconfigure/actuate/web/WebMvcEndpointManagementContextConfigurationTests.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: the configuration's bean is called directly, as Flint AOT's generated definitions
// call it, instead of through a WebApplicationContextRunner; the servlet-only condition is read from the
// `@ConditionalOnWebApplication` UDA Flint AOT evaluates. Boot's deprecated `@ServletEndpoint` support
// (`ServletEndpointRegistrar`) waits behind FlintServletEndpoints. WebMvcEndpointHandlerMappingTests'
// only test, shouldRegisterHints, is not ported: it checks GraalVM `RuntimeHints`, which Flint has no use for.
module web_mvc_endpoint_management_context_configuration_test;

import flint.boot.actuate.autoconfigure.endpoint.web : WebEndpointProperties;
import flint.boot.autoconfigure.condition : ConditionalOnWebApplication;
import flint.boot.webmvc.autoconfigure.actuate.web : WebMvcEndpointManagementContextConfiguration;
import std.traits : getUDAs;

@safe:

// Boot registers `@ServletEndpoint`s with a ServletEndpointRegistrar under the dispatcher servlet's path.
version (FlintServletEndpoints)
{
    @("WebMvcEndpointManagementContextConfigurationTests.contextShouldContainServletEndpointRegistrar") unittest
    {
        import flint.boot.webmvc.autoconfigure.actuate.web : ServletEndpointRegistrar;

        auto bean = new WebMvcEndpointManagementContextConfiguration().servletEndpointRegistrar(
                new WebEndpointProperties, null, () => "/test");
        assert(bean.getBasePath() == "/test/actuator");
    }
}

@("WebMvcEndpointManagementContextConfigurationTests."
        ~ "contextWhenNotServletBasedShouldNotContainServletEndpointRegistrar")
unittest
{
    enum conditions = getUDAs!(WebMvcEndpointManagementContextConfiguration, ConditionalOnWebApplication);
    static assert(conditions.length == 1);
    static assert(conditions[0].type == ConditionalOnWebApplication.Type.SERVLET);
}

@("WebMvcEndpointManagementContextConfigurationTests.refreshSucceedsWithoutHealth") unittest
{
    auto mapping = new WebMvcEndpointManagementContextConfiguration().webEndpointServletHandlerMapping(null,
            new WebEndpointProperties);
    assert(mapping !is null);
    assert(mapping.getEndpoints().length == 0);
}
