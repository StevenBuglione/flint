// Ported from spring-boot v4.2.0: module/spring-boot-webmvc/src/main/java/org/springframework/boot/webmvc/autoconfigure/actuate/web/WebMvcEndpointManagementContextConfiguration.java
// with module/spring-boot-actuator-autoconfigure/src/main/java/org/springframework/boot/actuate/autoconfigure/endpoint/web/WebEndpointAutoConfiguration.java's
// exposure filter.
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: the endpoints are the `ExposableWebEndpoint` beans, filtered by
// `management.endpoints.web.exposure.*` (health by default), where Boot discovers annotated endpoints; the management
// context is the application's (no separate management port).

/// `org.springframework.boot.webmvc.autoconfigure.actuate.web`: actuator endpoints in Spring MVC.
module flint.boot.webmvc.autoconfigure.actuate.web;

import flint.boot.actuate.autoconfigure.endpoint.web : IncludeExcludeEndpointFilter, WebEndpointProperties;
import flint.boot.actuate.endpoint.web : EndpointMapping, ExposableWebEndpoint;
import flint.boot.autoconfigure : AutoConfiguration;
import flint.boot.autoconfigure.condition : ConditionalOnClass, ConditionalOnMissingBean, ConditionalOnWebApplication;
import flint.boot.context.properties : ClassRef, EnableConfigurationProperties;
import flint.boot.webmvc.actuate.endpoint.web : WebMvcEndpointHandlerMapping;
import flint.context.annotation : Bean;
import flint.engine.aot.name : typeNameOf;

@safe:

/// Auto-configuration of the actuator's web endpoints in Spring MVC: the exposed endpoints at
/// `management.endpoints.web.base-path`, with the links resource.
@AutoConfiguration
@ConditionalOnWebApplication(ConditionalOnWebApplication.Type.SERVLET)
@ConditionalOnClass(null, [
    "flint.web.servlet.DispatcherServlet", "flint.boot.actuate.endpoint.web.ExposableWebEndpoint"
])
@EnableConfigurationProperties([ClassRef(typeNameOf!WebEndpointProperties)])
final class WebMvcEndpointManagementContextConfiguration
{
    /// The mapping of the exposed endpoints.
    @Bean
    @ConditionalOnMissingBean
    WebMvcEndpointHandlerMapping webEndpointServletHandlerMapping(ExposableWebEndpoint[] endpoints,
            WebEndpointProperties properties)
    {
        auto filter = new IncludeExcludeEndpointFilter(properties.getExposure().getInclude(),
                properties.getExposure().getExclude(), "health");
        ExposableWebEndpoint[] exposed;
        foreach (endpoint; endpoints)
        {
            if (filter.match(endpoint.getEndpointId().toString()))
                exposed ~= endpoint;
        }
        return new WebMvcEndpointHandlerMapping(new EndpointMapping(properties.getBasePath()),
                exposed, properties.getDiscovery().isEnabled());
    }
}
