// Ported from spring-boot v4.2.0: module/spring-boot-security/src/test/java/org/springframework/boot/security/autoconfigure/web/servlet/SecurityFilterAutoConfigurationTests.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: the case security_test.d does not hold. Refreshing a context without
// SecurityAutoConfiguration becomes the conditions Flint AOT compiles for SecurityFilterAutoConfiguration, which name
// no type of SecurityAutoConfiguration, and its bean called with the filter properties alone.
module security_filter_autoconfiguration_upstream_test;

import flint.boot.autoconfigure.condition : ConditionalOnBean;
import flint.boot.security.autoconfigure.web.servlet : SecurityFilterAutoConfiguration, SecurityFilterProperties;
import std.traits : getUDAs;

@safe:

@("SecurityFilterAutoConfigurationTests.filterAutoConfigurationWorksWithoutSecurityAutoConfiguration")
unittest
{
    // The registration only waits for the springSecurityFilterChain bean.
    string[] names;
    static foreach (condition; getUDAs!(SecurityFilterAutoConfiguration.securityFilterChainRegistration,
            ConditionalOnBean))
        names ~= condition.name;
    assert(names == ["springSecurityFilterChain"]);
    static assert(getUDAs!(SecurityFilterAutoConfiguration, ConditionalOnBean).length == 0);
    const registration = new SecurityFilterAutoConfiguration().securityFilterChainRegistration(
            new SecurityFilterProperties);
    assert(registration !is null);
}
