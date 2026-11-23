// Ported from spring-boot v4.2.0: module/spring-boot-jdbc/src/main/java/org/springframework/boot/jdbc/init/DataSourceScriptDatabaseInitializer.java
// with ../EmbeddedDatabaseConnection.java's isEmbedded
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: an embedded database is recognised by its JDBC URL (SQLite in memory, the embedded
// engine Flint's driver ships), where Boot asks the connection's metadata for H2, Derby and HSQLDB.

/// `org.springframework.boot.jdbc.init`: initializing a JDBC `DataSource` from SQL scripts.
module flint.boot.jdbc.init;

import flint.boot.sql.init : AbstractScriptDatabaseInitializer, DatabaseInitializationSettings;
import flint.javax.sql : DataSource;
import flint.jdbc.datasource.init : DatabasePopulatorUtils, ResourceDatabasePopulator;

@safe:

/// Whether `url` is the URL of an embedded, in-memory database (Boot's `EmbeddedDatabaseConnection.isEmbedded`).
bool isEmbeddedUrl(string url) pure
{
    import std.algorithm.searching : canFind, startsWith;

    return url.startsWith("jdbc:sqlite::memory:") || (url.startsWith("jdbc:sqlite:") && url.canFind("mode=memory"));
}

/// Initializes a `DataSource` from schema and data scripts.
class DataSourceScriptDatabaseInitializer : AbstractScriptDatabaseInitializer
{
    private DataSource dataSource;

    /// Over `dataSource`, with `settings`.
    this(DataSource dataSource, DatabaseInitializationSettings settings)
    {
        super(settings);
        this.dataSource = dataSource;
    }

    /// The data source.
    protected final DataSource getDataSource() pure nothrow @nogc
    {
        return dataSource;
    }

    /// Whether the data source's database is embedded; false when that cannot be determined.
    protected override bool isEmbeddedDatabase()
    {
        try
        {
            auto connection = dataSource.getConnection();
            scope (exit)
                connection.close();
            return isEmbeddedUrl(connection.getMetaData().getURL());
        }
        catch (Exception)
            return false;
    }

    /// Run `scripts` through a `ResourceDatabasePopulator`.
    protected override void runScripts(Scripts scripts)
    {
        auto populator = new ResourceDatabasePopulator;
        populator.setContinueOnError(scripts.isContinueOnError());
        populator.setSeparator(scripts.getSeparator());
        if (scripts.getEncoding().length)
            populator.setSqlScriptEncoding(scripts.getEncoding());
        foreach (resource; scripts.getResources())
            populator.addScript(resource);
        customize(populator);
        DatabasePopulatorUtils.execute(populator, dataSource);
    }

    /// Customise the populator before it runs.
    protected void customize(ResourceDatabasePopulator)
    {
    }
}
