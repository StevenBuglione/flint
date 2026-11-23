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

// Flint's DataSourceProperties has no determineDriverClassName: Flint's one driver is chosen by the URL.
version (FlintDataSourceDriverClassName)
{
    import flint.boot.jdbc.autoconfigure : determineDriverClassName;

    @("DataSourcePropertiesTests.determineDriver")
    unittest
    {
        auto properties = new DataSourceProperties;
        properties.setUrl("jdbc:mysql://mydb");
        assert(properties.getDriverClassName() is null);
        assert(properties.determineDriverClassName() == "com.mysql.cj.jdbc.Driver");
    }

    @("DataSourcePropertiesTests.determineDriverWithExplicitConfig")
    unittest
    {
        auto properties = new DataSourceProperties;
        properties.setUrl("jdbc:mysql://mydb");
        properties.setDriverClassName("org.hsqldb.jdbcDriver");
        assert(properties.getDriverClassName() == "org.hsqldb.jdbcDriver");
        assert(properties.determineDriverClassName() == "org.hsqldb.jdbcDriver");
    }
}
