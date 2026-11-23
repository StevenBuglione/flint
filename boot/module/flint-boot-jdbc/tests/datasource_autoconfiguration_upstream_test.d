// Ported from spring-boot v4.2.0: module/spring-boot-jdbc/src/test/java/org/springframework/boot/jdbc/autoconfigure/DataSourceAutoConfigurationTests.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: the cases datasource_autoconfiguration_test.d does not hold. The auto-configuration's
// bean is called directly, as Flint AOT's generated definitions call it, and the bean-presence cases assert the
// conditions Flint AOT compiles (a class filtered from the class path is a `@ConditionalOnClass` name, a user bean a
// `@ConditionalOnMissingBean` type). The embedded database is in-memory SQLite. Not ported: the Tomcat, DBCP2 and
// Oracle UCP pool cases (Flint has one pool), the R2DBC `ConnectionFactory` case (Flint has no R2DBC) and
// dbcp2UsesCustomConnectionDetailsWhenDefined (DBCP2).
module datasource_autoconfiguration_upstream_test;

import flint.boot.autoconfigure.condition : ConditionalOnClass, ConditionalOnMissingBean;
import flint.boot.context.properties.bind : Binder;
import flint.boot.context.properties.source : ConfigurationPropertySource, MapConfigurationPropertySource;
import flint.boot.jdbc.autoconfigure : DataSourceAutoConfiguration, DataSourceProperties,
    EmbeddedDatabaseConnection, isEmbeddedUrl;
import flint.engine.aot.descriptor : descriptorOf;
import flint.engine.aot.name : typeNameOf;
import flint.engine.jdbc : FlintDataSource;
import flint.javax.sql : DataSource;
import std.traits : getUDAs;

@safe:

private DataSourceProperties properties(string[2][] entries)
{
    auto binder = new Binder([
        cast(ConfigurationPropertySource) new MapConfigurationPropertySource("test", entries)
    ]);
    binder.getDescriptors().add(descriptorOf!EmbeddedDatabaseConnection());
    return binder.bindOrCreate!DataSourceProperties("flint.datasource");
}

// The class names `@ConditionalOnClass` on `symbol` requires.
private string[] requiredClasses(alias symbol)()
{
    string[] names;
    static foreach (condition; getUDAs!(symbol, ConditionalOnClass))
        names ~= condition.name;
    return names;
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

private bool contains(const string[] names, string name) pure nothrow @nogc
{
    foreach (candidate; names)
        if (candidate == name)
            return true;
    return false;
}

@("DataSourceAutoConfigurationTests.dataSourceWhenNoConnectionPoolsAreAvailableWithUrlDoesNotCreateDataSource")
unittest
{
    // Hiding the pools hides FlintDataSource, Flint's one pool: the auto-configuration requires it.
    assert(requiredClasses!DataSourceAutoConfiguration().contains(typeNameOf!FlintDataSource));
}

@("DataSourceAutoConfigurationTests.testDefaultDataSourceCanBeOverridden")
unittest
{
    assert(missingBeans!(DataSourceAutoConfiguration.dataSource)().contains(typeNameOf!DataSource));
}

@("DataSourceAutoConfigurationTests.whenThereIsAUserProvidedDataSourceAnUnresolvablePlaceholderDoesNotCauseAProblem")
unittest
{
    // The user's DataSource wins, so the auto-configured bean (and its URL) is never created.
    assert(missingBeans!(DataSourceAutoConfiguration.dataSource)().contains(typeNameOf!DataSource));
    const properties = properties([["spring.datasource.url", "${UNRESOLVABLE_PLACEHOLDER}"]]);
    assert(properties.getUrl() == "${UNRESOLVABLE_PLACEHOLDER}");
}

@("DataSourceAutoConfigurationTests.whenThereIsAnEmptyUserProvidedDataSource")
unittest
{
    // Boot falls back to an embedded database; Flint's embedded database is the pool over in-memory SQLite.
    auto dataSource = new DataSourceAutoConfiguration().dataSource(properties([
            ["spring.datasource.url", ""]
    ]));
    scope (exit)
        dataSource.close();
    assert(isEmbeddedUrl(dataSource.getJdbcUrl()));
}

@("DataSourceAutoConfigurationTests."
        ~ "whenNoInitializationRelatedSpringDataSourcePropertiesAreConfiguredThenInitializationBacksOff")
unittest
{
    import flint.boot.jdbc.init : DataSourceScriptDatabaseInitializer;
    import flint.context.annotation : Bean;
    import std.traits : hasUDA, ReturnType;

    static foreach (member; __traits(derivedMembers, DataSourceAutoConfiguration))
        static foreach (overload; __traits(getOverloads, DataSourceAutoConfiguration, member))
            static if (hasUDA!(overload, Bean))
                static assert(!is(ReturnType!overload : DataSourceScriptDatabaseInitializer));
}

// Flint's DataSourceProperties binds `driver-class-name` but nothing reads it: Flint's one driver is chosen by the URL.
version (FlintDataSourceDriverClassName)
{
    @("DataSourceAutoConfigurationTests.testBadDriverClass")
    unittest
    {
        import flint.beans.factory : BeanCreationException;
        import std.algorithm.searching : canFind;

        bool thrown;
        try
            new DataSourceAutoConfiguration().dataSource(properties([
                    ["spring.datasource.url", "jdbc:sqlite::memory:"],
                    ["spring.datasource.driverClassName", "org.none.jdbcDriver"]
        ]));
        catch (BeanCreationException e)
            thrown = e.msg.canFind("org.none.jdbcDriver");
        assert(thrown);
    }

    @("DataSourceAutoConfigurationTests.testEmbeddedTypeDefaultsUsername")
    unittest
    {
        auto pool = new DataSourceAutoConfiguration().dataSource(properties([
                ["spring.datasource.driverClassName", "flint.engine.jdbc.FlintDriver"],
                ["spring.datasource.url", "jdbc:sqlite::memory:"]
        ]));
        scope (exit)
            pool.close();
        assert(pool.getDriverClassName() == "flint.engine.jdbc.FlintDriver");
        assert(pool.getUsername() == "sa");
    }

    @("DataSourceAutoConfigurationTests.testExplicitDriverClassClearsUsername")
    unittest
    {
        auto dataSource = new DataSourceAutoConfiguration().dataSource(
                properties([
            [
                "spring.datasource.driverClassName",
                "datasource_autoconfiguration_upstream_test.DatabaseTestDriver"
            ], ["spring.datasource.url", "jdbc:foo://localhost"]
        ]));
        scope (exit)
            dataSource.close();
        assert(dataSource.getDriverClassName() == "datasource_autoconfiguration_upstream_test.DatabaseTestDriver");
        assert(dataSource.getUsername() is null);
    }
}

// FlintDataSource has Hikari's core settings only: no connectionTestQuery, maxLifetime or dataSourceProperties.
version (FlintHikariPoolSettings)
{
    @("DataSourceAutoConfigurationTests.hikariValidatesConnectionByDefault")
    unittest
    {
        auto dataSource = new DataSourceAutoConfiguration().dataSource(properties(null));
        scope (exit)
            dataSource.close();
        // Use Connection#isValid()
        assert(dataSource.getConnectionTestQuery() is null);
    }
}

// Flint's DataSourceAutoConfiguration always creates its pool; `flint.datasource.type` is bound but not used.
version (FlintDataSourceType)
{
    private void containsOnlySimpleDriverDataSource(Object dataSource) @system
    {
        import flint.jdbc.datasource : SimpleDriverDataSource;

        assert(typeid(dataSource) is typeid(SimpleDriverDataSource));
    }

    @("DataSourceAutoConfigurationTests.dataSourceWhenNoConnectionPoolsAreAvailableWithUrlAndTypeCreatesDataSource")
    @system unittest  // typeid of a class reference
    {
        auto dataSource = new DataSourceAutoConfiguration().dataSource(
                properties([
                ["spring.datasource.driverClassName", "flint.engine.jdbc.FlintDriver"],
                ["spring.datasource.url", "jdbc:sqlite::memory:"],
                ["spring.datasource.type", "flint.jdbc.datasource.SimpleDriverDataSource"]
        ]));
        containsOnlySimpleDriverDataSource(dataSource);
    }

    @("DataSourceAutoConfigurationTests.explicitTypeSupportedDataSource")
    @system unittest  // typeid of a class reference
    {
        auto dataSource = new DataSourceAutoConfiguration().dataSource(
                properties([
                ["spring.datasource.driverClassName", "flint.engine.jdbc.FlintDriver"],
                ["spring.datasource.url", "jdbc:sqlite::memory:"],
                ["spring.datasource.type", "flint.jdbc.datasource.SimpleDriverDataSource"]
        ]));
        containsOnlySimpleDriverDataSource(dataSource);
    }
}

// Boot's JdbcConnectionDetails (and PropertiesJdbcConnectionDetails) are not ported: the pool reads the properties.
version (FlintJdbcConnectionDetails)
{
    import flint.boot.jdbc.autoconfigure : JdbcConnectionDetails;

    // Boot's TestJdbcConnectionDetails.
    private final class TestJdbcConnectionDetails : JdbcConnectionDetails
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

    @("DataSourceAutoConfigurationTests.definesPropertiesBasedConnectionDetailsByDefault")
    unittest
    {
        import flint.boot.jdbc.autoconfigure : PropertiesJdbcConnectionDetails;

        const details = new DataSourceAutoConfiguration().jdbcConnectionDetails(properties(null));
        assert(cast(PropertiesJdbcConnectionDetails) details !is null);
    }

    @("DataSourceAutoConfigurationTests.genericUsesCustomJdbcConnectionDetailsWhenAvailable")
    unittest
    {
        auto source = new DataSourceAutoConfiguration().dataSource(properties([
                ["spring.datasource.type", "flint.jdbc.datasource.SimpleDriverDataSource"]
        ]), new TestJdbcConnectionDetails);
        assert(source.getUsername() == "user-1");
        assert(source.getPassword() == "password-1");
        assert(source.getUrl() == "jdbc:customdb://customdb.example.com:12345/database-1");
    }
}
