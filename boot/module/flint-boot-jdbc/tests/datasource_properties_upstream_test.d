// Ported from spring-boot v4.2.0: module/spring-boot-jdbc/src/test/java/org/springframework/boot/jdbc/autoconfigure/DataSourcePropertiesTests.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: the cases datasource_properties_test.d does not hold. The embedded database is
// SQLite (Flint has no H2, Derby or HSQLDB driver); the `determine*` methods are module functions called with UFCS;
// Flint's DataSourceProperties is not an InitializingBean, so `afterPropertiesSet` has no counterpart.
module datasource_properties_upstream_test;

import flint.boot.jdbc.autoconfigure : DataSourceProperties, determineUrl, determineUsername,
    EmbeddedDatabaseConnection, getUrl;

@safe:

@("DataSourcePropertiesTests.determineUrlWithSpecificEmbeddedConnection")
unittest
{
    auto properties = new DataSourceProperties;
    properties.setGenerateUniqueName(false);
    properties.setEmbeddedDatabaseConnection(EmbeddedDatabaseConnection.SQLITE);
    assert(properties.determineUrl() == EmbeddedDatabaseConnection.SQLITE.getUrl("testdb"));
}

@("DataSourcePropertiesTests.determineUsernameWhenNull")
unittest
{
    auto properties = new DataSourceProperties;
    properties.setUsername(null);
    assert(properties.getUsername() is null);
    assert(properties.determineUsername() == "sa");
}

@("DataSourcePropertiesTests.determineDriver")
unittest
{
    import flint.boot.jdbc.autoconfigure : determineDriverClassName;

    auto properties = new DataSourceProperties;
    properties.setUrl("jdbc:mysql://mydb");
    assert(properties.getDriverClassName() is null);
    assert(properties.determineDriverClassName() == "com.mysql.cj.jdbc.Driver");
}

// The explicit class must load: upstream names HSQLDB's driver, on its test class path; here it is the driver Flint's
// JDBC engine registers.
@("DataSourcePropertiesTests.determineDriverWithExplicitConfig")
unittest
{
    import flint.boot.jdbc.autoconfigure : determineDriverClassName;
    import flint.java.sql : DriverManager;

    const registered = typeid(cast(Object) DriverManager.getDriver("jdbc:sqlite::memory:")).name;
    auto properties = new DataSourceProperties;
    properties.setUrl("jdbc:mysql://mydb");
    properties.setDriverClassName(registered);
    assert(properties.getDriverClassName() == registered);
    assert(properties.determineDriverClassName() == registered);
}

// Flint: with no URL, the embedded database's driver (Boot's EmbeddedDatabaseConnection.getDriverClassName); with
// neither, Boot's failure.
@("FlintDetermineDriverClassNameEmbeddedAndNone")
unittest
{
    import flint.boot.jdbc.autoconfigure : DataSourceBeanCreationException, determineDriverClassName,
        getDriverClassName;

    auto properties = new DataSourceProperties;
    assert(properties.determineDriverClassName() == "flint.sqlite.JDBC");
    assert(EmbeddedDatabaseConnection.H2.getDriverClassName() == "org.h2.Driver");
    properties.setEmbeddedDatabaseConnection(EmbeddedDatabaseConnection.NONE);
    bool thrown;
    try
        properties.determineDriverClassName();
    catch (DataSourceBeanCreationException e)
        thrown = e.msg == "Failed to determine a suitable driver class";
    assert(thrown);
}
