// Ported from spring-boot v4.2.0: module/spring-boot-jdbc/src/test/java/org/springframework/boot/jdbc/autoconfigure/JdbcTemplateAutoConfigurationTests.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: the cases jdbc_template_autoconfiguration_test.d does not hold. The
// auto-configuration's beans are called directly, as Flint AOT's generated definitions call them, and the
// bean-presence cases assert the conditions Flint AOT compiles (`hasSingleCandidate` is true for one candidate or
// one primary candidate). Boot's TestDataSource (HSQLDB) is a pool over in-memory SQLite; mocked templates are real
// ones.
module jdbc_template_autoconfiguration_upstream_test;

import flint.boot.autoconfigure.condition : ConditionalOnMissingBean, ConditionalOnSingleCandidate;
import flint.boot.jdbc.autoconfigure : JdbcProperties, JdbcTemplateAutoConfiguration;
import flint.engine.aot.name : typeNameOf;
import flint.engine.jdbc : FlintDataSource;
import flint.javax.sql : DataSource;
import flint.jdbc.core : JdbcOperations, JdbcTemplate;
import flint.jdbc.core.namedparam : NamedParameterJdbcOperations;
import std.traits : getUDAs;

@safe:

// The type `@ConditionalOnSingleCandidate` on `symbol` names.
private string singleCandidate(alias symbol)()
{
    string name;
    static foreach (condition; getUDAs!(symbol, ConditionalOnSingleCandidate))
        name = condition.value.name;
    return name;
}

// The bean types `@ConditionalOnMissingBean` on `symbol` yields to.
private string[] missingBeans(alias symbol)()
{
    string[] names;
    static foreach (condition; getUDAs!(symbol, ConditionalOnMissingBean))
        foreach (type; condition.value)
            names ~= type.name;
    return names;
}

// Boot's TestDataSource: an in-memory database named `name`.
private FlintDataSource testDataSource(string name)
{
    return new FlintDataSource("jdbc:sqlite:file:" ~ name ~ "?mode=memory&cache=shared");
}

private JdbcTemplate jdbcTemplate(DataSource dataSource)
{
    return new JdbcTemplateAutoConfiguration().jdbcTemplate(dataSource, new JdbcProperties, null);
}

@("JdbcTemplateAutoConfigurationTests.testJdbcTemplateExistsWithCustomDataSource")
unittest
{
    auto customDataSource = testDataSource("customDataSource");
    assert(singleCandidate!JdbcTemplateAutoConfiguration() == typeNameOf!DataSource);
    assert(jdbcTemplate(customDataSource).getDataSource() is customDataSource);
}

@("JdbcTemplateAutoConfigurationTests.testMultiDataSource")
unittest
{
    // Two DataSource beans, neither primary: neither JdbcOperations nor NamedParameterJdbcOperations is defined.
    assert(singleCandidate!JdbcTemplateAutoConfiguration() == typeNameOf!DataSource);
}

@("JdbcTemplateAutoConfigurationTests.testMultiJdbcTemplate")
unittest
{
    assert(singleCandidate!(JdbcTemplateAutoConfiguration.namedParameterJdbcTemplate)() == typeNameOf!JdbcTemplate);
}

@("JdbcTemplateAutoConfigurationTests.testMultiDataSourceUsingPrimary")
unittest
{
    assert(singleCandidate!JdbcTemplateAutoConfiguration() == typeNameOf!DataSource);
    auto test1DataSource = testDataSource("test1");
    auto template_ = jdbcTemplate(test1DataSource);
    auto named = new JdbcTemplateAutoConfiguration().namedParameterJdbcTemplate(template_);
    assert(template_.getDataSource() is test1DataSource);
    assert(named.getJdbcOperations() is template_);
}

@("JdbcTemplateAutoConfigurationTests.testMultiJdbcTemplateUsingPrimary")
unittest
{
    assert(singleCandidate!(JdbcTemplateAutoConfiguration.namedParameterJdbcTemplate)() == typeNameOf!JdbcTemplate);
    auto test1Template = new JdbcTemplate(testDataSource("test1Template"));
    auto named = new JdbcTemplateAutoConfiguration().namedParameterJdbcTemplate(test1Template);
    assert(named.getJdbcOperations() is test1Template);
}

@("JdbcTemplateAutoConfigurationTests.testExistingCustomJdbcTemplate")
unittest
{
    assert(missingBeans!(JdbcTemplateAutoConfiguration.jdbcTemplate)() == [
        typeNameOf!JdbcOperations
    ]);
}

@("JdbcTemplateAutoConfigurationTests.testExistingCustomNamedParameterJdbcTemplate")
unittest
{
    assert(missingBeans!(JdbcTemplateAutoConfiguration.namedParameterJdbcTemplate)() == [
        typeNameOf!NamedParameterJdbcOperations
    ]);
}

// Boot's DatabaseInitializationDependencyConfigurer is not ported: a bean that queries the database while it is
// created (here through JdbcTemplate) is not ordered after the script-based initializer.
version (FlintDatabaseInitializationDependencies)
{
    @("JdbcTemplateAutoConfigurationTests.testDependencyToScriptBasedDataSourceInitialization")
    unittest
    {
        import flint.boot.sql.init.dependency : DatabaseInitializationDependencyConfigurer;
        import flint.context.annotation : Import;

        bool imported;
        static foreach (annotation; getUDAs!(JdbcTemplateAutoConfiguration, Import))
            foreach (type; annotation.value)
                imported |= type.name == typeNameOf!DatabaseInitializationDependencyConfigurer;
        assert(imported);
    }
}
