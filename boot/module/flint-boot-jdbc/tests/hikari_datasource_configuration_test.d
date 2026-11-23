// Ported from spring-boot v4.2.0: module/spring-boot-jdbc/src/test/java/org/springframework/boot/jdbc/autoconfigure/HikariDataSourceConfigurationTests.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: Boot's HikariDataSource is Flint's FlintDataSource, which the auto-configuration
// creates and then binds with `flint.datasource.hikari.*` (alias `spring.datasource.hikari.*`), as Flint AOT's
// generated definition does for the bean's @ConfigurationProperties. Not ported: the four CRaC checkpoint-restore
// cases (a JVM feature with no Flint counterpart).
module hikari_datasource_configuration_test;

import flint.boot.context.properties.bind : Bindable, Binder;
import flint.boot.context.properties.source : ConfigurationPropertySource, MapConfigurationPropertySource;
import flint.boot.jdbc.autoconfigure : DataSourceAutoConfiguration, DataSourceProperties, EmbeddedDatabaseConnection;
import flint.engine.aot.descriptor : descriptorOf;
import flint.engine.jdbc : FlintDataSource;

@safe:

private enum PREFIX = "spring.datasource.hikari.";

// The auto-configured pool, with `entries` as the context's properties.
private FlintDataSource dataSource(string[2][] entries)
{
    auto binder = new Binder([
        cast(ConfigurationPropertySource) new MapConfigurationPropertySource("test", entries)
    ]);
    binder.getDescriptors().add(descriptorOf!EmbeddedDatabaseConnection());
    auto dataSource = new DataSourceAutoConfiguration().dataSource(
            binder.bindOrCreate!DataSourceProperties("flint.datasource"));
    binder.bind!FlintDataSource("flint.datasource.hikari", Bindable!FlintDataSource.ofInstance(dataSource));
    return dataSource;
}

@("HikariDataSourceConfigurationTests.testDataSourceExists")
unittest
{
    import flint.javax.sql : DataSource;
    import std.traits : ReturnType;

    static assert(is(ReturnType!(DataSourceAutoConfiguration.dataSource) : DataSource));
    auto ds = dataSource(null);
    scope (exit)
        ds.close();
    assert(ds !is null);
}

@("HikariDataSourceConfigurationTests.nameIsAliasedToPoolName")
unittest
{
    auto ds = dataSource([["spring.datasource.name", "myDS"]]);
    scope (exit)
        ds.close();
    assert(ds.getPoolName() == "myDS");
}

@("HikariDataSourceConfigurationTests.poolNameTakesPrecedenceOverName")
unittest
{
    auto ds = dataSource([["spring.datasource.name", "myDS"], [PREFIX ~ "pool-name", "myHikariDS"]]);
    scope (exit)
        ds.close();
    assert(ds.getPoolName() == "myHikariDS");
}

// FlintDataSource has Hikari's core settings only: no maxLifetime, dataSourceProperties or dataSourceClassName.
version (FlintHikariPoolSettings)
{
    @("HikariDataSourceConfigurationTests.testDataSourcePropertiesOverridden")
    unittest
    {
        auto ds = dataSource([
            [PREFIX ~ "jdbc-url", "jdbc:foo//bar/spam"],
            ["spring.datasource.hikari.max-lifetime", "1234"]
        ]);
        assert(ds.getJdbcUrl() == "jdbc:foo//bar/spam");
        assert(ds.getMaxLifetime() == 1234);
    }

    @("HikariDataSourceConfigurationTests.testDataSourceGenericPropertiesOverridden")
    unittest
    {
        auto ds = dataSource([
            [PREFIX ~ "data-source-properties.dataSourceClassName", "org.h2.JDBCDataSource"]
        ]);
        assert(ds.getDataSourceProperties().getProperty("dataSourceClassName") == "org.h2.JDBCDataSource");
    }

    @("HikariDataSourceConfigurationTests.configureDataSourceClassNameWithNoEmbeddedDatabaseAvailable")
    unittest
    {
        auto ds = dataSource([
            ["spring.datasource.url", "jdbc:example//"],
            [
                "spring.datasource.hikari.data-source-class-name",
                "flint.jdbc.datasource.SimpleDriverDataSource"
            ]
        ]);
        assert(ds.getDataSourceClassName() == "flint.jdbc.datasource.SimpleDriverDataSource");
        ds.getConnection().close();
    }

    @("HikariDataSourceConfigurationTests.configureDataSourceClassNameToOverrideUseOfAnEmbeddedDatabase")
    unittest
    {
        auto ds = dataSource([
            ["spring.datasource.url", "jdbc:example//"],
            [
                "spring.datasource.hikari.data-source-class-name",
                "flint.jdbc.datasource.SimpleDriverDataSource"
            ]
        ]);
        assert(ds.getDataSourceClassName() == "flint.jdbc.datasource.SimpleDriverDataSource");
        ds.getConnection().close();
    }

    @("HikariDataSourceConfigurationTests.testDataSourceDefaultsPreserved")
    unittest
    {
        auto ds = dataSource(null);
        scope (exit)
            ds.close();
        assert(ds.getMaxLifetime() == 1_800_000);
    }
}

// Boot's JdbcConnectionDetails is not ported: the pool reads the properties.
version (FlintJdbcConnectionDetails)
{
    @("HikariDataSourceConfigurationTests.usesCustomConnectionDetailsWhenDefined")
    unittest
    {
        import flint.boot.jdbc.autoconfigure : JdbcConnectionDetails;

        static final class TestJdbcConnectionDetails : JdbcConnectionDetails
        {
            string getJdbcUrl()
            {
                return "jdbc:customdb://customdb.example.com:12345/database-1";
            }

            string getUsername()
            {
                return "user-1";
            }

            string getPassword()
            {
                return "password-1";
            }

            string getDriverClassName()
            {
                return "org.postgresql.Driver";
            }
        }

        auto properties = new DataSourceProperties;
        auto hikari = new DataSourceAutoConfiguration().dataSource(properties, new TestJdbcConnectionDetails);
        assert(hikari.getUsername() == "user-1");
        assert(hikari.getPassword() == "password-1");
        assert(hikari.getDriverClassName() == "org.postgresql.Driver");
        assert(hikari.getJdbcUrl() == "jdbc:customdb://customdb.example.com:12345/database-1");
    }
}
