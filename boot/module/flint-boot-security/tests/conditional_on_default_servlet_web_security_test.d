// Ported from spring-boot v4.2.0: module/spring-boot-security/src/test/java/org/springframework/boot/security/autoconfigure/web/servlet/ConditionalOnDefaultServletWebSecurityTests.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: the condition is the meta-annotations Flint AOT merges onto the annotated
// configuration, so the cases assert those; the configuration's bean is called directly.
module conditional_on_default_servlet_web_security_test;

import flint.boot.autoconfigure.condition : ConditionalOnClass, ConditionalOnMissingBean;
import flint.boot.security.autoconfigure.web.servlet : ConditionalOnDefaultServletWebSecurity;
import flint.context.annotation : Bean;
import flint.engine.aot.name : typeNameOf;
import flint.security.web : SecurityFilterChain;
import std.traits : getUDAs;

@safe:

@ConditionalOnDefaultServletWebSecurity private final class TestConfiguration
{
    @Bean string testBean()
    {
        return "test";
    }
}

@("ConditionalOnDefaultServletWebSecurityTests.matchesWithoutSecurityFilterChainBean")
unittest
{
    import flint.engine.aot.descriptor : descriptorOf;

    // The merged conditions only ask for Spring Security's web classes, which are present.
    auto descriptor = descriptorOf!TestConfiguration();
    assert(descriptor.annotation(typeNameOf!ConditionalOnClass) !is null);
    string[] classes;
    static foreach (condition; getUDAs!(ConditionalOnDefaultServletWebSecurity, ConditionalOnClass))
        classes ~= condition.name;
    assert(classes == [
        typeNameOf!SecurityFilterChain, "flint.security.config.annotation.web.builders.HttpSecurity"
    ]);
    assert(new TestConfiguration().testBean() == "test");
}

@("ConditionalOnDefaultServletWebSecurityTests.doesNotMatchWhenSecurityFilterChainBeanIsDefined")
unittest
{
    import flint.engine.aot.descriptor : descriptorOf;

    assert(descriptorOf!TestConfiguration().annotation(typeNameOf!ConditionalOnMissingBean) !is null);
    string[] missing;
    static foreach (condition; getUDAs!(ConditionalOnDefaultServletWebSecurity, ConditionalOnMissingBean))
        foreach (type; condition.value)
            missing ~= type.name;
    assert(missing == [typeNameOf!SecurityFilterChain]);
}
