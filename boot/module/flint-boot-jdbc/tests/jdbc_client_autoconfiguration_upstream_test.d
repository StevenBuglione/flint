// Ported from spring-boot v4.2.0: module/spring-boot-jdbc/src/test/java/org/springframework/boot/jdbc/autoconfigure/JdbcClientAutoConfigurationTests.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: the bean-presence cases, as the conditions Flint AOT compiles;
// jdbcClientWhenExistingJdbcTemplateIsCreated is in jdbc_template_autoconfiguration_test.d.
module jdbc_client_autoconfiguration_upstream_test;

import flint.boot.autoconfigure.condition : ConditionalOnMissingBean, ConditionalOnSingleCandidate;
import flint.boot.jdbc.autoconfigure : JdbcClientAutoConfiguration;
import flint.engine.aot.name : typeNameOf;
import flint.jdbc.core.namedparam : NamedParameterJdbcTemplate;
import flint.jdbc.core.simple : JdbcClient;
import std.traits : getUDAs;

@safe:

@("JdbcClientAutoConfigurationTests.jdbcClientWhenNoAvailableJdbcTemplateIsNotCreated")
unittest
{
    // Without JdbcTemplateAutoConfiguration there is no NamedParameterJdbcTemplate candidate.
    string candidate;
    static foreach (condition; getUDAs!(JdbcClientAutoConfiguration, ConditionalOnSingleCandidate))
        candidate = condition.value.name;
    assert(candidate == typeNameOf!NamedParameterJdbcTemplate);
}

@("JdbcClientAutoConfigurationTests.jdbcClientWithCustomJdbcClientIsNotCreated")
unittest
{
    string[] missing;
    static foreach (condition; getUDAs!(JdbcClientAutoConfiguration, ConditionalOnMissingBean))
        foreach (type; condition.value)
            missing ~= type.name;
    assert(missing == [typeNameOf!JdbcClient]);
}
