// Ported from spring-boot v4.2.0: module/spring-boot-jdbc/src/test/java/org/springframework/boot/jdbc/autoconfigure/DataSourceInitializationAutoConfigurationTests.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: the auto-configuration's bean is called directly, as Flint AOT's generated
// definitions call it, and the bean-presence cases assert the conditions Flint AOT compiles (a class filtered from
// the class path is a `@ConditionalOnClass` name, a user bean a `@ConditionalOnMissingBean` type).
module datasource_initialization_autoconfiguration_test;

import flint.boot.autoconfigure.condition : ConditionalOnClass, ConditionalOnMissingBean,
    ConditionalOnSingleCandidate;
import flint.boot.jdbc.autoconfigure : DataSourceInitializationAutoConfiguration;
import flint.boot.jdbc.init : DataSourceScriptDatabaseInitializer;
import flint.boot.sql.autoconfigure.init : ApplicationScriptDatabaseInitializer, SqlInitializationProperties;
import flint.engine.aot.name : typeNameOf;
import flint.engine.jdbc : FlintDataSource;
import flint.javax.sql : DataSource;
import std.traits : getUDAs;

@safe:

// The bean types `@ConditionalOnMissingBean` on the auto-configuration yields to.
private string[] missingBeans()
{
    string[] names;
    static foreach (condition; getUDAs!(DataSourceInitializationAutoConfiguration, ConditionalOnMissingBean))
        foreach (type; condition.value)
            names ~= type.name;
    return names;
}

@("DataSourceInitializationAutoConfigurationTests.whenNoDataSourceIsAvailableThenAutoConfigurationBacksOff")
unittest
{
    string candidate;
    static foreach (condition; getUDAs!(DataSourceInitializationAutoConfiguration, ConditionalOnSingleCandidate))
        candidate = condition.value.name;
    assert(candidate == typeNameOf!DataSource);
}

@("DataSourceInitializationAutoConfigurationTests.whenDataSourceIsAvailableThenDataSourceInitializerIsAutoConfigured")
unittest
{
    auto dataSource = new FlintDataSource("jdbc:sqlite::memory:");
    const DataSourceScriptDatabaseInitializer initializer = new DataSourceInitializationAutoConfiguration()
        .dataSourceScriptDatabaseInitializer(dataSource, new SqlInitializationProperties);
    assert(initializer !is null);
}

@("DataSourceInitializationAutoConfigurationTests."
        ~ "whenAnApplicationInitializerIsDefinedThenInitializerIsNotAutoConfigured")
unittest
{
    assert(missingBeans() == [typeNameOf!ApplicationScriptDatabaseInitializer]);
}

@("DataSourceInitializationAutoConfigurationTests."
        ~ "whenAnInitializerIsDefinedThenApplicationInitializerIsStillAutoConfigured")
unittest
{
    // A plain DataSourceScriptDatabaseInitializer is not an ApplicationScriptDatabaseInitializer, the only type the
    // auto-configuration yields to.
    static assert(!is(DataSourceScriptDatabaseInitializer : ApplicationScriptDatabaseInitializer));
    assert(missingBeans() == [typeNameOf!ApplicationScriptDatabaseInitializer]);
}

@("DataSourceInitializationAutoConfigurationTests."
        ~ "whenADataSourceIsAvailableAndSpringJdbcIsNotThenAutoConfigurationBacksOff")
unittest
{
    import flint.jdbc.datasource.init : DatabasePopulator;

    string[] classes;
    static foreach (condition; getUDAs!(DataSourceInitializationAutoConfiguration, ConditionalOnClass))
        classes ~= condition.name;
    assert(classes == [typeNameOf!DatabasePopulator]);
}

// Boot's @ConditionalOnSqlInitialization is not ported: with flint.sql.init.mode=never the initializer bean is still
// defined (it then runs no scripts).
version (FlintConditionalOnSqlInitialization)
{
    @("DataSourceInitializationAutoConfigurationTests."
            ~ "whenDataSourceIsAvailableAndModeIsNeverThenInitializerIsNotAutoConfigured")
    unittest
    {
        import flint.boot.sql.autoconfigure.init : ConditionalOnSqlInitialization;
        import std.traits : hasUDA;

        static assert(hasUDA!(DataSourceInitializationAutoConfiguration, ConditionalOnSqlInitialization));
    }
}

// Boot's DatabaseInitializationDependencyConfigurer is not ported: @DependsOnDatabaseInitialization beans get no
// depends-on the script-based initializer.
version (FlintDatabaseInitializationDependencies)
{
    @("DataSourceInitializationAutoConfigurationTests." ~ "whenBeanIsAnnotatedAsDependingOnDatabaseInitialization"
            ~ "ThenItDependsOnDataSourceScriptDatabaseInitializer")
    unittest
    {
        import flint.boot.sql.init.dependency : DatabaseInitializationDependencyConfigurer;
        import flint.context.annotation : Import;

        bool imported;
        static foreach (annotation; getUDAs!(DataSourceInitializationAutoConfiguration, Import))
            foreach (type; annotation.value)
                imported |= type.name == typeNameOf!DatabaseInitializationDependencyConfigurer;
        assert(imported);
    }
}
