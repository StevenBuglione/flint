// Ported from spring-boot v4.2.0: module/spring-boot-jdbc/src/test/java/org/springframework/boot/jdbc/autoconfigure/JdbcTemplateAutoConfigurationTests.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: the auto-configuration's bean is called directly, as Flint AOT's generated
// definitions call it, instead of through an ApplicationContextRunner; the bean-presence, multi-DataSource and
// NamedParameterJdbcTemplate cases are not ported (conditions are evaluated by Flint AOT, and flint:jdbc has no
// NamedParameterJdbcTemplate yet).
module jdbc_template_autoconfiguration_test;

import flint.boot.context.properties.bind : Binder;
import flint.boot.context.properties.source : ConfigurationPropertySource, MapConfigurationPropertySource;
import flint.boot.jdbc.autoconfigure : DataSourceAutoConfiguration, DataSourceProperties,
    JdbcProperties, JdbcTemplateAutoConfiguration;
import flint.engine.aot.descriptor : descriptorOf;
import flint.jdbc.core : JdbcTemplate;
import flint.jdbc.support : SQLExceptionTranslator, SQLStateSQLExceptionTranslator;

@safe:

private JdbcTemplate jdbcTemplate(string[2][] entries, SQLExceptionTranslator[] translators = null)
{
    import core.time : Duration;
    import flint.java.util : Optional;

    auto binder = new Binder([
        cast(ConfigurationPropertySource) new MapConfigurationPropertySource("test", entries)
    ]);
    binder.getDescriptors().add(descriptorOf!(JdbcProperties.Template)());
    binder.getDescriptors().add(descriptorOf!(Optional!Duration)());
    auto properties = binder.bindOrCreate!JdbcProperties("flint.jdbc");
    auto dataSource = new DataSourceAutoConfiguration().dataSource(new DataSourceProperties);
    return new JdbcTemplateAutoConfiguration().jdbcTemplate(dataSource, properties, translators);
}

@("testJdbcTemplateExists") unittest
{
    auto template_ = jdbcTemplate(null);
    assert(template_.getDataSource() !is null);
    assert(template_.isIgnoreWarnings());
    assert(template_.getFetchSize() == -1);
    assert(template_.getQueryTimeout() == -1);
    assert(template_.getMaxRows() == -1);
    assert(!template_.isSkipResultsProcessing());
    assert(!template_.isSkipUndeclaredResults());
    assert(!template_.isResultsMapCaseInsensitive());
}

@("testJdbcTemplateWithCustomProperties") unittest
{
    auto template_ = jdbcTemplate([
        ["spring.jdbc.template.ignore-warnings", "false"], [
            "spring.jdbc.template.fetch-size", "100"
        ], ["spring.jdbc.template.query-timeout", "60"], ["spring.jdbc.template.max-rows", "1000"],
        ["spring.jdbc.template.skip-results-processing", "true"],
        ["spring.jdbc.template.skip-undeclared-results", "true"],
        ["spring.jdbc.template.results-map-case-insensitive", "true"]
    ]);
    assert(template_.getDataSource() !is null);
    assert(!template_.isIgnoreWarnings());
    assert(template_.getFetchSize() == 100);
    assert(template_.getQueryTimeout() == 60);
    assert(template_.getMaxRows() == 1000);
    assert(template_.isSkipResultsProcessing());
    assert(template_.isSkipUndeclaredResults());
    assert(template_.isResultsMapCaseInsensitive());
}

@("Flint: flint.jdbc.template.query-timeout with a duration suffix") unittest
{
    assert(jdbcTemplate([["flint.jdbc.template.query-timeout", "2m"]]).getQueryTimeout() == 120);
}

@("shouldConfigureJdbcTemplateWithSQLExceptionTranslatorIfPresent") unittest
{
    auto translator = new SQLStateSQLExceptionTranslator;
    assert(jdbcTemplate(null, [translator]).getExceptionTranslator() is translator);
}

@("shouldNotConfigureJdbcTemplateWithSQLExceptionTranslatorIfNotUnique") unittest
{
    auto translator1 = new SQLStateSQLExceptionTranslator;
    auto translator2 = new SQLStateSQLExceptionTranslator;
    const translator = jdbcTemplate(null, [translator1, translator2]).getExceptionTranslator();
    assert(translator !is translator1 && translator !is translator2);
}
