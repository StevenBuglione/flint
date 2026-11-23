// Ported from spring-boot v4.2.0: module/spring-boot-security/src/test/java/org/springframework/boot/security/autoconfigure/UserDetailsServiceAutoConfigurationTests.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: the cases security_test.d does not hold. The auto-configuration's bean is called
// directly, as Flint AOT's generated definitions call it, and the bean-presence cases assert the conditions Flint AOT
// compiles (the web application type, the beans it yields to); the generated-password output is captured through
// the SLF4J binding's appender instead of Boot's OutputCaptureExtension. Not ported: the AuthenticationManagerResolver,
// JwtDecoder and alternative-form-of-authentication cases (OAuth2 client and resource server, SAML), whose types
// Flint's Spring Security does not have.
module user_details_service_autoconfiguration_upstream_test;

import flint.boot.autoconfigure.condition : ConditionalOnMissingBean, ConditionalOnWebApplication;
import flint.boot.security.autoconfigure : SecurityProperties, UserDetailsServiceAutoConfiguration;
import flint.engine.aot.name : typeNameOf;
import std.traits : getUDAs;

@safe:

// The bean types the auto-configuration yields to.
private string[] missingBeans()
{
    string[] names;
    static foreach (condition; getUDAs!(UserDetailsServiceAutoConfiguration, ConditionalOnMissingBean))
        foreach (type; condition.value)
            names ~= type.name;
    return names;
}

private bool yieldsTo(string type)
{
    foreach (name; missingBeans())
        if (name == type)
            return true;
    return false;
}

private ConditionalOnWebApplication.Type webApplicationType()
{
    ConditionalOnWebApplication.Type type = ConditionalOnWebApplication.Type.ANY;
    static foreach (condition; getUDAs!(UserDetailsServiceAutoConfiguration, ConditionalOnWebApplication))
        type = condition.type;
    return type;
}

@("UserDetailsServiceAutoConfigurationTests.shouldSupplyUserDetailsServiceInServletApp")
unittest
{
    import flint.security.core.userdetails : UserDetailsService;

    assert(webApplicationType() == ConditionalOnWebApplication.Type.SERVLET);
    const UserDetailsService service = new UserDetailsServiceAutoConfiguration().inMemoryUserDetailsManager(
            new SecurityProperties, null);
    assert(service !is null);
}

@("UserDetailsServiceAutoConfigurationTests.shouldNotSupplyUserDetailsServiceInReactiveApp")
unittest
{
    assert(webApplicationType() != ConditionalOnWebApplication.Type.REACTIVE);
    assert(webApplicationType() != ConditionalOnWebApplication.Type.ANY);
}

@("UserDetailsServiceAutoConfigurationTests.shouldNotSupplyUserDetailsServiceInNonWebApp")
unittest
{
    // A @ConditionalOnWebApplication never matches outside a web application.
    assert(getUDAs!(UserDetailsServiceAutoConfiguration, ConditionalOnWebApplication).length == 1);
}

@("UserDetailsServiceAutoConfigurationTests.testDefaultUsernamePassword")
unittest
{
    import flint.slf4j : LoggerFactory;
    import flint.slf4j.event : LoggingEvent;
    import flint.slf4j.provider : FlintLogLoggerFactory;
    import std.algorithm.searching : canFind;

    string output;
    auto factory = cast(FlintLogLoggerFactory) LoggerFactory.getILoggerFactory();
    assert(factory !is null);
    factory.setAppender((LoggingEvent event) { output ~= event.getMessage(); });
    scope (exit)
        factory.setAppender(null);
    auto manager = new UserDetailsServiceAutoConfiguration().inMemoryUserDetailsManager(new SecurityProperties, null);
    assert(output.canFind("Using generated security password:"));
    assert(manager.loadUserByUsername("user") !is null);
}

@("UserDetailsServiceAutoConfigurationTests.defaultUserNotCreatedIfAuthenticationManagerBeanPresent")
unittest
{
    import flint.security.authentication : AuthenticationManager;

    assert(yieldsTo(typeNameOf!AuthenticationManager));
}

@("UserDetailsServiceAutoConfigurationTests.defaultUserNotCreatedIfUserDetailsServiceBeanPresent")
unittest
{
    import flint.security.core.userdetails : UserDetailsService;

    assert(yieldsTo(typeNameOf!UserDetailsService));
}

@("UserDetailsServiceAutoConfigurationTests.defaultUserNotCreatedIfAuthenticationProviderBeanPresent")
unittest
{
    import flint.security.authentication : AuthenticationProvider;

    assert(yieldsTo(typeNameOf!AuthenticationProvider));
}
