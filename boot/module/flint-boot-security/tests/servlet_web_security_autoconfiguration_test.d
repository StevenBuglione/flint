// Ported from spring-boot v4.2.0: module/spring-boot-security/src/test/java/org/springframework/boot/security/autoconfigure/web/servlet/ServletWebSecurityAutoConfigurationTests.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: the auto-configurations' beans are called directly, as Flint AOT's generated
// definitions call them, and the bean-presence cases assert the conditions Flint AOT compiles (a class filtered from
// the class path is a `@ConditionalOnClass` name, a user bean a `@ConditionalOnMissingBean` type, a non-web context
// a `@ConditionalOnWebApplication`). Not ported: the two RSA public key binding cases (Flint has no `RSAPublicKey`
// or JWT support to bind to).
module servlet_web_security_autoconfiguration_test;

import flint.boot.autoconfigure.condition : ConditionalOnClass, ConditionalOnMissingBean, ConditionalOnWebApplication;
import flint.boot.context.properties.bind : Binder;
import flint.boot.context.properties.source : ConfigurationPropertySource, MapConfigurationPropertySource;
import flint.boot.security.autoconfigure.web.servlet : ConditionalOnDefaultServletWebSecurity,
    EnableWebSecurityConfiguration,
    SecurityFilterAutoConfiguration,
    SecurityFilterChainConfiguration, SecurityFilterProperties, ServletWebSecurityAutoConfiguration;
import flint.boot.web.server.servlet : DelegatingFilterProxyRegistrationBean;
import flint.engine.aot.descriptor : descriptorOf;
import flint.engine.aot.name : typeNameOf;
import flint.jakarta.servlet : DispatcherType;
import flint.security.web : SecurityFilterChain;
import std.traits : getUDAs, hasUDA;

@safe:

// The class names `@ConditionalOnClass` on `symbol` requires.
private string[] requiredClasses(alias symbol)()
{
    string[] names;
    static foreach (condition; getUDAs!(symbol, ConditionalOnClass))
        names ~= condition.name;
    return names;
}

// The securityFilterChainRegistration bean, with `entries` as the context's properties.
private DelegatingFilterProxyRegistrationBean registration(string[2][] entries)
{
    auto binder = new Binder([
        cast(ConfigurationPropertySource) new MapConfigurationPropertySource("test", entries)
    ]);
    binder.getDescriptors().add(descriptorOf!DispatcherType());
    binder.getDescriptors().add(descriptorOf!(DispatcherType[])());
    auto properties = binder.bindOrCreate!SecurityFilterProperties("flint.security.filter");
    return new SecurityFilterAutoConfiguration().securityFilterChainRegistration(properties);
}

private bool sameElements(const DispatcherType[] actual, const DispatcherType[] expected) pure nothrow
{
    if (actual.length != expected.length)
        return false;
    foreach (type; expected)
    {
        bool found;
        foreach (candidate; actual)
            found |= candidate == type;
        if (!found)
            return false;
    }
    return true;
}

@("ServletWebSecurityAutoConfigurationTests.testWebConfiguration")
unittest
{
    import flint.context.annotation : Import;
    import flint.security.config.annotation.web.builders : HttpSecurity;
    import flint.security.config.annotation.web.configuration : EnableWebSecurity;

    string[] imported;
    static foreach (annotation; getUDAs!(ServletWebSecurityAutoConfiguration, Import))
        foreach (type; annotation.value)
            imported ~= type.name;
    assert(imported == [
        typeNameOf!SecurityFilterChainConfiguration, typeNameOf!EnableWebSecurityConfiguration
    ]);
    static assert(hasUDA!(EnableWebSecurityConfiguration, EnableWebSecurity));
    // The one default chain, over the AuthenticationManager @EnableWebSecurity builds from the UserDetailsService.
    import flint.boot.security.autoconfigure : SecurityProperties, UserDetailsServiceAutoConfiguration;
    import flint.security.config.annotation.authentication.builders : AuthenticationManagerBuilder;

    auto auth = new AuthenticationManagerBuilder;
    auth.userDetailsService(new UserDetailsServiceAutoConfiguration()
            .inMemoryUserDetailsManager(new SecurityProperties, null));
    const SecurityFilterChain chain = new SecurityFilterChainConfiguration().defaultSecurityFilterChain(
            new HttpSecurity(auth.build()));
    assert(chain !is null);
}

@("ServletWebSecurityAutoConfigurationTests.enableWebSecurityIsConditionalOnClass")
unittest
{
    import flint.security.config.annotation.web.configuration : EnableWebSecurity;

    assert(requiredClasses!ServletWebSecurityAutoConfiguration() == [typeNameOf!EnableWebSecurity]);
}

@("ServletWebSecurityAutoConfigurationTests.filterChainBeanIsConditionalOnClassSecurityFilterChain")
unittest
{
    static assert(hasUDA!(SecurityFilterChainConfiguration, ConditionalOnDefaultServletWebSecurity));
    assert(requiredClasses!ConditionalOnDefaultServletWebSecurity()[0] == typeNameOf!SecurityFilterChain);
}

@("ServletWebSecurityAutoConfigurationTests.securityConfigurerBacksOffWhenOtherSecurityFilterChainBeanPresent")
unittest
{
    static assert(hasUDA!(SecurityFilterChainConfiguration, ConditionalOnDefaultServletWebSecurity));
    string[] missing;
    static foreach (condition; getUDAs!(ConditionalOnDefaultServletWebSecurity, ConditionalOnMissingBean))
        foreach (type; condition.value)
            missing ~= type.name;
    assert(missing == [typeNameOf!SecurityFilterChain]);
}

@("ServletWebSecurityAutoConfigurationTests.testFilterIsNotRegisteredInNonWeb")
unittest
{
    auto conditions = getUDAs!(SecurityFilterAutoConfiguration, ConditionalOnWebApplication);
    static assert(conditions.length == 1);
    assert(conditions[0].type == ConditionalOnWebApplication.Type.SERVLET);
}

@("ServletWebSecurityAutoConfigurationTests.testDefaultFilterOrder")
unittest
{
    // OrderedFilter.REQUEST_WRAPPER_FILTER_MAX_ORDER is 0.
    assert(registration(null).getOrder() == 0 - 100);
}

@("ServletWebSecurityAutoConfigurationTests.testCustomFilterOrder")
unittest
{
    assert(registration([["spring.security.filter.order", "12345"]]).getOrder() == 12_345);
}

@("ServletWebSecurityAutoConfigurationTests.defaultFilterDispatcherTypes")
unittest
{
    import std.traits : EnumMembers;

    assert(sameElements(registration(null).getDispatcherTypes(), [EnumMembers!DispatcherType]));
}

@("ServletWebSecurityAutoConfigurationTests.customFilterDispatcherTypes")
unittest
{
    const types = registration([["spring.security.filter.dispatcher-types", "INCLUDE,ERROR"]]).getDispatcherTypes();
    assert(sameElements(types, [DispatcherType.INCLUDE, DispatcherType.ERROR]));
}

// Flint's AbstractFilterRegistrationBean.getDispatcherTypes reports [REQUEST] for an empty set (the binding itself
// yields []), where Boot keeps the empty set it was given.
@("ServletWebSecurityAutoConfigurationTests.emptyFilterDispatcherTypesDoNotThrowException")
unittest
{
    assert(registration([["spring.security.filter.dispatcher-types", ""]]).getDispatcherTypes().length == 0);
}

// Boot's PathPatternRequestMatcherBuilderConfiguration is not ported (it joins with PathPatternRequestMatcher.Builder
// and DispatcherServletPath).
version (FlintPathPatternRequestMatcherBuilder)
{
    @("ServletWebSecurityAutoConfigurationTests."
            ~ "whenDispatcherServletPathIsSetPathPatternRequestMatcherBuilderHasCustomBasePath")
    unittest
    {
        import flint.boot.security.autoconfigure.web.servlet : PathPatternRequestMatcherBuilderConfiguration;
        import flint.boot.webmvc.autoconfigure : DispatcherServletPath;

        static final class Path : DispatcherServletPath
        {
            string getPath()
            {
                return "/dispatcher-servlet";
            }
        }

        auto builder = new PathPatternRequestMatcherBuilderConfiguration().pathPatternRequestMatcherBuilder(new Path);
        assert(builder.getBasePath() == "/dispatcher-servlet");
    }

    @("ServletWebSecurityAutoConfigurationTests." ~ "givenACustomPathPatternRequestMatcherBuilder"
            ~ "WhenDispatcherServletPathIsSetBuilderBasePathIsNotCustomized")
    unittest
    {
        import flint.boot.security.autoconfigure.web.servlet : PathPatternRequestMatcherBuilderConfiguration;
        import flint.security.web.servlet.util.matcher : PathPatternRequestMatcher;

        string[] missing;
        alias bean = PathPatternRequestMatcherBuilderConfiguration.pathPatternRequestMatcherBuilder;
        static foreach (condition; getUDAs!(bean, ConditionalOnMissingBean))
            foreach (type; condition.value)
                missing ~= type.name;
        assert(missing == [typeNameOf!(PathPatternRequestMatcher.Builder)]);
        assert(PathPatternRequestMatcher.withDefaults().getBasePath() == "");
    }
}
