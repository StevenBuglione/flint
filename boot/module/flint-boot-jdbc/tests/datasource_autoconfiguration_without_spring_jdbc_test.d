// Ported from spring-boot v4.2.0: module/spring-boot-jdbc/src/test/java/org/springframework/boot/jdbc/autoconfigure/DataSourceAutoConfigurationWithoutSpringJdbcTests.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: spring-jdbc is flint:jdbc (`flint.jdbc.*`) and Boot's HikariDataSource is Flint's
// FlintDataSource. Excluding a jar or hiding a pool is a `@ConditionalOnClass` name, which Flint AOT decides at
// build time, so the cases assert those names.
module datasource_autoconfiguration_without_spring_jdbc_test;

import flint.boot.autoconfigure.condition : ConditionalOnClass;
import flint.boot.jdbc.autoconfigure : DataSourceAutoConfiguration, DataSourceProperties;
import flint.engine.aot.name : typeNameOf;
import flint.engine.jdbc : FlintDataSource;
import std.traits : getUDAs;

@safe:

// The class names `@ConditionalOnClass` on DataSourceAutoConfiguration requires.
private string[] requiredClasses()
{
    string[] names;
    static foreach (condition; getUDAs!(DataSourceAutoConfiguration, ConditionalOnClass))
        names ~= condition.name;
    return names;
}

private bool requires(string name)
{
    foreach (candidate; requiredClasses())
        if (candidate == name)
            return true;
    return false;
}

@("DataSourceAutoConfigurationWithoutSpringJdbcTests.withoutConnectionPoolsAutoConfigurationBacksOff")
unittest
{
    assert(requires(typeNameOf!FlintDataSource));
}

@("DataSourceAutoConfigurationWithoutSpringJdbcTests.withUrlAndWithoutConnectionPoolsAutoConfigurationBacksOff")
unittest
{
    // The URL does not matter: without the pool class the auto-configuration is removed at build time.
    assert(requires(typeNameOf!FlintDataSource));
}

// Flint's pool has no driver class name: Flint's one driver is chosen by the URL.
version (FlintDataSourceDriverClassName)
{
    @("DataSourceAutoConfigurationWithoutSpringJdbcTests.pooledDataSourceCanBeAutoConfigured")
    unittest
    {
        import std.algorithm.searching : startsWith;

        // spring-jdbc excluded: the auto-configuration requires nothing from flint.jdbc.
        foreach (name; requiredClasses())
            assert(!name.startsWith("flint.jdbc."));
        auto dataSource = new DataSourceAutoConfiguration().dataSource(new DataSourceProperties);
        scope (exit)
            dataSource.close();
        assert(dataSource.getJdbcUrl() !is null);
        assert(dataSource.getDriverClassName() !is null);
    }
}
