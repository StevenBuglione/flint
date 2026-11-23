// Ported from spring-boot v4.2.0: module/spring-boot-jdbc/src/test/java/org/springframework/boot/jdbc/autoconfigure/DataSourceAutoConfigurationTests.java
// with DataSourceTransactionManagerAutoConfigurationTests.java from the same directory.
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: the auto-configurations' beans are called directly, as Flint AOT's generated
// definitions call them, instead of through an ApplicationContextRunner; the pool is Flint's `FlintDataSource` over
// in-memory SQLite (Boot's tests use Hikari over H2); the alternative-pool, JNDI and connection-details cases are
// not ported (Flint has one pool and no JNDI).
module datasource_autoconfiguration_test;

import flint.boot.context.properties.bind : Bindable, Binder;
import flint.boot.context.properties.source : ConfigurationPropertySource, MapConfigurationPropertySource;
import flint.boot.jdbc.autoconfigure : DataSourceAutoConfiguration, DataSourceProperties,
    DataSourceTransactionManagerAutoConfiguration, EmbeddedDatabaseConnection;
import flint.engine.aot.descriptor : descriptorOf;
import flint.engine.jdbc : FlintDataSource;

@safe:

private DataSourceProperties properties(string[2][] entries)
{
    auto binder = new Binder([
        cast(ConfigurationPropertySource) new MapConfigurationPropertySource("test", entries)
    ]);
    binder.getDescriptors().add(descriptorOf!EmbeddedDatabaseConnection());
    return binder.bindOrCreate!DataSourceProperties("flint.datasource");
}

@("testDefaultDataSourceExists") unittest
{
    auto dataSource = new DataSourceAutoConfiguration().dataSource(properties(null));
    scope (exit)
        dataSource.close();
    import std.algorithm.searching : startsWith;

    assert(dataSource.getJdbcUrl().startsWith("jdbc:sqlite:file:"));
    assert(dataSource.getUsername() == "sa");
}

@("testDataSourceHasEmbeddedDefault") unittest
{
    auto dataSource = new DataSourceAutoConfiguration().dataSource(
            properties([["flint.datasource.generate-unique-name", "false"]]));
    scope (exit)
        dataSource.close();
    assert(dataSource.getJdbcUrl() == "jdbc:sqlite:file:testdb?mode=memory&cache=shared");
}

@("testDataSourceUrlHasEmbeddedDefault: an explicit URL, user and pool name") unittest
{
    auto dataSource = new DataSourceAutoConfiguration().dataSource(properties([
            ["spring.datasource.url", "jdbc:sqlite::memory:"], ["flint.datasource.username",
                "app"], ["flint.datasource.name", "main"]
    ]));
    scope (exit)
        dataSource.close();
    assert(dataSource.getJdbcUrl() == "jdbc:sqlite::memory:");
    assert(dataSource.getUsername() == "app");
    assert(dataSource.getPoolName() == "main");
}

@("testBadUrl") unittest
{
    import flint.boot.jdbc.autoconfigure : DataSourceBeanCreationException;

    bool thrown;
    try
        new DataSourceAutoConfiguration().dataSource(
                properties([["flint.datasource.embedded-database-connection", "none"]]));
    catch (DataSourceBeanCreationException)
        thrown = true;
    assert(thrown);
}

@("Flint: flint.datasource.hikari.* binds onto the pool") unittest
{
    auto dataSource = new DataSourceAutoConfiguration().dataSource(properties(null));
    scope (exit)
        dataSource.close();
    auto binder = new Binder([
        cast(ConfigurationPropertySource) new MapConfigurationPropertySource("test",
                [["flint.datasource.hikari.maximum-pool-size", "3"]])
    ]);
    binder.bind!FlintDataSource("flint.datasource.hikari", Bindable!FlintDataSource.ofInstance(dataSource));
    assert(dataSource.getMaximumPoolSize() == 3);
}

@("transactionManagerExists: a JdbcTransactionManager over the DataSource") unittest
{
    auto dataSource = new DataSourceAutoConfiguration().dataSource(properties(null));
    auto manager = new DataSourceTransactionManagerAutoConfiguration().transactionManager(dataSource);
    assert(manager.getDataSource() is dataSource);
}

// The cases below open real connections: they need the pinned SQLite, linked when FlintNativeSqlite is set (as in
// engine-jdbc's driver tests).
version (FlintNativeSqlite)
{
    private int selectOne(FlintDataSource dataSource)
    {
        auto connection = dataSource.getConnection();
        scope (exit)
            connection.close();
        auto result = connection.createStatement().executeQuery("SELECT 1");
        assert(result.next());
        return result.getInt(1);
    }

    @("testDefaultDataSourceExists: the embedded database answers") unittest
    {
        auto dataSource = new DataSourceAutoConfiguration().dataSource(properties(null));
        scope (exit)
            dataSource.close();
        assert(selectOne(dataSource) == 1);
    }

    @("transactionManagerCommits") unittest
    {
        auto dataSource = new DataSourceAutoConfiguration().dataSource(properties(null));
        scope (exit)
            dataSource.close();
        auto manager = new DataSourceTransactionManagerAutoConfiguration().transactionManager(dataSource);
        import flint.transaction : TransactionDefinition;

        auto status = manager.getTransaction(TransactionDefinition.withDefaults());
        manager.commit(status);
        assert(status.isCompleted());
    }
}
