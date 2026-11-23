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

// FlintDataSource takes no driver class (it finds its driver by URL), so these cases check the class Boot determines
// and the data source's creation; `DatabaseTestDriver` is registered with the DriverManager for the case that names it,
// and accepts only `jdbc:foo:` URLs so that it does not hide the other cases' missing drivers.

/// `DatabaseTestDriver`: a driver the test registers (see testExplicitDriverClassClearsUsername).
final class DatabaseTestDriver : imported!"flint.java.sql".Driver
{
    import flint.java.sql : Connection;
    import flint.java.util : Properties;

    override Connection connect(string url, Properties info)
    {
        return null;
    }

    override bool acceptsURL(string url)
    {
        import std.algorithm.searching : startsWith;

        return url.startsWith("jdbc:foo:");
    }

    override int getMajorVersion()
    {
        return 1;
    }

    override int getMinorVersion()
    {
        return 0;
    }

    override bool jdbcCompliant()
    {
        return false;
    }
}

private imported!"flint.java.sql".Driver supplyTestDriver()
{
    return new DatabaseTestDriver;
}

@("DataSourceAutoConfigurationTests.testBadDriverClass")
unittest
{
    import flint.java.lang : IllegalStateException;
    import std.algorithm.searching : canFind;

    // Boot's Assert.state throws IllegalStateException, which the context reports inside a BeanCreationException.
    bool thrown;
    try
        new DataSourceAutoConfiguration().dataSource(properties([
                ["spring.datasource.url", "jdbc:sqlite::memory:"],
                ["spring.datasource.driverClassName", "org.none.jdbcDriver"]
    ]));
    catch (IllegalStateException e)
        thrown = e.msg.canFind("org.none.jdbcDriver");
    assert(thrown);
}

@("DataSourceAutoConfigurationTests.testEmbeddedTypeDefaultsUsername")
unittest
{
    import flint.boot.jdbc.autoconfigure : determineDriverClassName;
    import flint.java.sql : DriverManager;

    DriverManager.registerDriver(&supplyTestDriver);
    scope (exit)
        DriverManager.deregisterDriver(&supplyTestDriver);
    auto settings = properties([
        ["spring.datasource.driverClassName", typeNameOf!DatabaseTestDriver],
        ["spring.datasource.url", "jdbc:sqlite::memory:"]
    ]);
    auto pool = new DataSourceAutoConfiguration().dataSource(settings);
    scope (exit)
        pool.close();
    assert(settings.determineDriverClassName() == typeNameOf!DatabaseTestDriver);
    assert(pool.getUsername() == "sa");
}

@("DataSourceAutoConfigurationTests.testExplicitDriverClassClearsUsername")
unittest
{
    import flint.boot.jdbc.autoconfigure : determineDriverClassName;
    import flint.java.sql : DriverManager;

    DriverManager.registerDriver(&supplyTestDriver);
    scope (exit)
        DriverManager.deregisterDriver(&supplyTestDriver);
    auto settings = properties([
        ["spring.datasource.driverClassName", typeNameOf!DatabaseTestDriver],
        ["spring.datasource.url", "jdbc:foo://localhost"]
    ]);
    auto dataSource = new DataSourceAutoConfiguration().dataSource(settings);
    scope (exit)
        dataSource.close();
    assert(settings.determineDriverClassName() == "datasource_autoconfiguration_upstream_test.DatabaseTestDriver");
    assert(dataSource.getUsername() is null);
}

// Flint: a URL no registered driver accepts fails when the data source is created, at startup, naming the driver
// class Boot determines; for a database Flint has a driver for, the message names the package to add.
@("FlintDataSourceWithoutItsDriverFailsAtStartup") unittest
{
    import flint.beans.factory : BeanCreationException;
    import flint.java.sql : DriverManager, SQLException;

    string failure(string url)
    {
        try
            new DataSourceAutoConfiguration().dataSource(properties([["spring.datasource.url", url]])).close();
        catch (BeanCreationException e)
            return e.msg.idup;
        return null;
    }

    assert(failure("jdbc:mysql://localhost/db") == "Cannot load driver class: com.mysql.cj.jdbc.Driver");
    // While a registered driver accepts postgresql URLs, the data source is created.
    bool accepted = true;
    try
        DriverManager.getDriver("jdbc:postgresql://localhost/db");
    catch (SQLException)
        accepted = false;
    if (accepted)
        assert(failure("jdbc:postgresql://localhost/db") is null);
    else
        assert(failure("jdbc:postgresql://localhost/db")
                == "Cannot load driver class: flint.postgresql.Driver (add the flint:postgresql dependency)");
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
