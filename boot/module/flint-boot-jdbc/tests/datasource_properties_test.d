// Ported from spring-boot v4.2.0: module/spring-boot-jdbc/src/test/java/org/springframework/boot/jdbc/autoconfigure/DataSourcePropertiesTests.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: the embedded database is SQLite (Flint has no H2, Derby or HSQLDB driver); the
// `determine*` methods are module functions called with UFCS; the driver-class and class-loader cases are not ported
// (Flint's one driver is chosen by the URL, and there is no class loader to filter).
module datasource_properties_test;

import flint.boot.jdbc.autoconfigure : DataSourceBeanCreationException, DataSourceProperties,
    determinePassword, determineUrl, determineUsername, EmbeddedDatabaseConnection, getUrl;

@safe:

private bool throwsNoUrl(DataSourceProperties properties)
{
    import std.algorithm.searching : canFind;

    try
        properties.determineUrl();
    catch (DataSourceBeanCreationException e)
        return e.msg.canFind("Failed to determine suitable jdbc url");
    return false;
}

@("determineUrlWithoutGenerateUniqueName") unittest
{
    auto properties = new DataSourceProperties;
    properties.setGenerateUniqueName(false);
    assert(properties.getUrl() is null);
    assert(properties.determineUrl() == EmbeddedDatabaseConnection.SQLITE.getUrl("testdb"));
    assert(properties.determineUrl() == "jdbc:sqlite:file:testdb?mode=memory&cache=shared");
}

@("determineUrlWithNoEmbeddedSupport") unittest
{
    auto properties = new DataSourceProperties;
    properties.setEmbeddedDatabaseConnection(EmbeddedDatabaseConnection.H2);
    assert(throwsNoUrl(properties));
}

@("whenEmbeddedConnectionIsNoneAndNoUrlIsConfiguredThenDetermineUrlThrows") unittest
{
    auto properties = new DataSourceProperties;
    properties.setGenerateUniqueName(false);
    properties.setEmbeddedDatabaseConnection(EmbeddedDatabaseConnection.NONE);
    assert(throwsNoUrl(properties));
}

@("determineUrlWithExplicitConfig") unittest
{
    auto properties = new DataSourceProperties;
    properties.setUrl("jdbc:postgresql://mydb");
    assert(properties.getUrl() == "jdbc:postgresql://mydb");
    assert(properties.determineUrl() == "jdbc:postgresql://mydb");
}

@("determineUrlWithGenerateUniqueName") unittest
{
    auto properties = new DataSourceProperties;
    assert(properties.determineUrl() == properties.determineUrl());
    auto properties2 = new DataSourceProperties;
    assert(properties.determineUrl() != properties2.determineUrl());
}

@("determineUsername") unittest
{
    auto properties = new DataSourceProperties;
    assert(properties.getUsername() is null);
    assert(properties.determineUsername() == "sa");
}

@("determineUsernameWhenEmpty") unittest
{
    auto properties = new DataSourceProperties;
    properties.setUsername("");
    assert(properties.determineUsername() == "sa");
}

@("determineUsernameWithExplicitConfig") unittest
{
    auto properties = new DataSourceProperties;
    properties.setUsername("foo");
    assert(properties.determineUsername() == "foo");
}

@("determineUsernameWithNonEmbeddedUrl") unittest
{
    auto properties = new DataSourceProperties;
    properties.setUrl("jdbc:postgresql://localhost/db");
    assert(properties.determineUsername() is null);
}

@("determinePassword") unittest
{
    auto properties = new DataSourceProperties;
    assert(properties.getPassword() is null);
    assert(properties.determinePassword() !is null && properties.determinePassword().length == 0);
}

@("determinePasswordWithExplicitConfig") unittest
{
    auto properties = new DataSourceProperties;
    properties.setPassword("bar");
    assert(properties.determinePassword() == "bar");
}

@("determinePasswordWithNonEmbeddedUrl") unittest
{
    auto properties = new DataSourceProperties;
    properties.setUrl("jdbc:postgresql://localhost/db");
    assert(properties.determinePassword() is null);
}
