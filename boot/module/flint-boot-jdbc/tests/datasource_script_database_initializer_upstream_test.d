// Ported from spring-boot v4.2.0: module/spring-boot-jdbc/src/test/java/org/springframework/boot/jdbc/init/DataSourceScriptDatabaseInitializerTests.java
// with module/spring-boot-sql/src/testFixtures/java/org/springframework/boot/sql/init/AbstractScriptDatabaseInitializerTests.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: the cases sql_init_test.d does not hold. The scripts are files under a temporary
// directory (`file:` locations, where Boot's @WithResource adds class path resources); the embedded database is
// in-memory SQLite and the standalone one an SQLite file (Boot: H2 in memory and on disk); whether the database was
// accessed is whether a connection was asked for (Boot: whether the Hikari pool started). The cases that touch a
// database need FlintNativeSqlite, as engine-jdbc's driver tests do.
module datasource_script_database_initializer_upstream_test;

import flint.boot.jdbc.init : DataSourceScriptDatabaseInitializer;
import flint.boot.sql.init : DatabaseInitializationMode, DatabaseInitializationSettings;
import flint.engine.jdbc : FlintDataSource;
import flint.java.lang : IllegalStateException;
import flint.java.sql : Connection;
import flint.javax.sql : DataSource;
import flint.jdbc.datasource : DelegatingDataSource;

@safe:

// A data source that records whether a connection was asked for.
private final class RecordingDataSource : DelegatingDataSource
{
    size_t connections;

    this(DataSource target)
    {
        super(target);
    }

    override Connection getConnection()
    {
        connections++;
        return super.getConnection();
    }

    void close()
    {
        if (auto pool = cast(FlintDataSource) getTargetDataSource())
            pool.close();
    }
}

// Boot's @WithSchemaSqlResource and @WithDataSqlResource, written under a fresh temporary directory.
private struct Scripts
{
    string directory;

    static Scripts create() @trusted
    {
        // SAFETY: test-only; writes two small files under the system temp directory.
        import std.file : mkdirRecurse, tempDir, write;
        import std.path : buildPath;
        import std.uuid : randomUUID;

        const directory = buildPath(tempDir(), "flint-ds-init-" ~ randomUUID().toString());
        mkdirRecurse(directory);
        write(buildPath(directory, "schema.sql"),
                "CREATE TABLE EXAMPLE (\n\tid INTEGER PRIMARY KEY,\n\tname VARCHAR(30)\n);\n");
        write(buildPath(directory, "data.sql"), "INSERT INTO EXAMPLE VALUES (1, 'Andy');");
        return Scripts(directory);
    }

    string location(string name) const
    {
        return "file:" ~ directory ~ "/" ~ name;
    }

    void remove() const @trusted
    {
        // SAFETY: test-only; removes the directory create() made.
        import std.file : exists, rmdirRecurse;

        if (exists(directory))
            rmdirRecurse(directory);
    }
}

// Boot's embeddedDataSource and standaloneDataSource.
private struct Databases
{
    RecordingDataSource embedded;
    RecordingDataSource standalone;
    string standalonePath;

    static Databases create()
    {
        import std.file : tempDir;
        import std.path : buildPath;
        import std.uuid : randomUUID;

        const path = buildPath(tempDir(), "flint-ds-init-" ~ randomUUID().toString() ~ ".db");
        return Databases(new RecordingDataSource(new FlintDataSource("jdbc:sqlite:file:" ~ randomUUID()
                .toString() ~ "?mode=memory&cache=shared")),
                new RecordingDataSource(new FlintDataSource("jdbc:sqlite:" ~ path)), path);
    }

    void close() @trusted
    {
        // SAFETY: test-only; removes the standalone database file.
        import std.file : exists, remove;

        embedded.close();
        standalone.close();
        if (exists(standalonePath))
            remove(standalonePath);
    }
}

// Boot's DataSourceScriptDatabaseInitializerTests' access to the protected isEmbeddedDatabase.
private class ExposedInitializer : DataSourceScriptDatabaseInitializer
{
    this(DataSource dataSource, DatabaseInitializationSettings settings)
    {
        super(dataSource, settings);
    }

    bool embedded()
    {
        return isEmbeddedDatabase();
    }
}

private string failure(DataSourceScriptDatabaseInitializer initializer)
{
    try
        initializer.initializeDatabase();
    catch (IllegalStateException e)
        return e.msg;
    return null;
}

@("DataSourceScriptDatabaseInitializerTests.whenDatabaseIsInitializedWithDirectoryLocationsThenFailureIsHelpful")
unittest
{
    auto scripts = Scripts.create();
    scope (exit)
        scripts.remove();
    auto databases = Databases.create();
    scope (exit)
        databases.close();
    auto settings = new DatabaseInitializationSettings;
    settings.setSchemaLocations(["file:" ~ scripts.directory]);
    settings.setDataLocations(["file:" ~ scripts.directory]);
    auto initializer = new DataSourceScriptDatabaseInitializer(databases.embedded, settings);
    assert(failure(initializer) == "No schema scripts found at location 'file:" ~ scripts.directory ~ "'");
}

@("DataSourceScriptDatabaseInitializerTests.whenNoScriptsExistAtADataLocationThenInitializationFails")
unittest
{
    auto databases = Databases.create();
    scope (exit)
        databases.close();
    auto settings = new DatabaseInitializationSettings;
    settings.setDataLocations(["does-not-exist.sql"]);
    auto initializer = new DataSourceScriptDatabaseInitializer(databases.embedded, settings);
    assert(failure(initializer) == "No data scripts found at location 'does-not-exist.sql'");
    assert(databases.embedded.connections == 0);
}

@("DataSourceScriptDatabaseInitializerTests.whenNoScriptsExistAtAnOptionalDataLocationThenDatabaseIsNotAccessed")
unittest
{
    auto databases = Databases.create();
    scope (exit)
        databases.close();
    auto settings = new DatabaseInitializationSettings;
    settings.setDataLocations(["optional:does-not-exist.sql"]);
    auto initializer = new DataSourceScriptDatabaseInitializer(databases.embedded, settings);
    assert(!initializer.initializeDatabase());
    assert(databases.embedded.connections == 0);
}

private DatabaseInitializationSettings schemaAndData(Scripts scripts, DatabaseInitializationMode mode)
{
    auto settings = new DatabaseInitializationSettings;
    settings.setSchemaLocations([scripts.location("schema.sql")]);
    settings.setDataLocations([scripts.location("data.sql")]);
    settings.setMode(mode);
    return settings;
}

@("DataSourceScriptDatabaseInitializerTests.whenModeIsNeverThenEmbeddedDatabaseIsNotInitialized")
unittest
{
    auto scripts = Scripts.create();
    scope (exit)
        scripts.remove();
    auto databases = Databases.create();
    scope (exit)
        databases.close();
    auto initializer = new DataSourceScriptDatabaseInitializer(databases.embedded,
            schemaAndData(scripts, DatabaseInitializationMode.NEVER));
    assert(!initializer.initializeDatabase());
    assert(databases.embedded.connections == 0);
}

@("DataSourceScriptDatabaseInitializerTests.whenModeIsNeverThenStandaloneDatabaseIsNotInitialized")
unittest
{
    auto scripts = Scripts.create();
    scope (exit)
        scripts.remove();
    auto databases = Databases.create();
    scope (exit)
        databases.close();
    auto initializer = new DataSourceScriptDatabaseInitializer(databases.standalone,
            schemaAndData(scripts, DatabaseInitializationMode.NEVER));
    assert(!initializer.initializeDatabase());
    assert(databases.standalone.connections == 0);
}

@("DataSourceScriptDatabaseInitializerTests.whenDatabaseIsInaccessibleThenItIsAssumedNotToBeEmbedded")
unittest
{
    auto initializer = new ExposedInitializer(new FlintDataSource, new DatabaseInitializationSettings);
    assert(!initializer.embedded());
}

version (FlintNativeSqlite)
{
    private long numberOfRows(DataSource dataSource, string sql)
    {
        import flint.jdbc.core : JdbcTemplate;

        return new JdbcTemplate(dataSource).queryForObject!long(sql);
    }

    @("DataSourceScriptDatabaseInitializerTests.whenModeIsEmbeddedThenEmbeddedDatabaseIsInitialized")
    unittest
    {
        auto scripts = Scripts.create();
        scope (exit)
            scripts.remove();
        auto databases = Databases.create();
        scope (exit)
            databases.close();
        auto initializer = new DataSourceScriptDatabaseInitializer(databases.embedded,
                schemaAndData(scripts, DatabaseInitializationMode.EMBEDDED));
        assert(initializer.initializeDatabase());
        assert(numberOfRows(databases.embedded, "SELECT COUNT(*) FROM EXAMPLE") == 1);
    }

    @("DataSourceScriptDatabaseInitializerTests.whenModeIsEmbeddedThenStandaloneDatabaseIsNotInitialized")
    unittest
    {
        auto scripts = Scripts.create();
        scope (exit)
            scripts.remove();
        auto databases = Databases.create();
        scope (exit)
            databases.close();
        auto initializer = new DataSourceScriptDatabaseInitializer(databases.standalone,
                schemaAndData(scripts, DatabaseInitializationMode.EMBEDDED));
        assert(!initializer.initializeDatabase());
        assert(databases.standalone.connections > 0);
    }

    @("DataSourceScriptDatabaseInitializerTests.whenModeIsAlwaysThenEmbeddedDatabaseIsInitialized")
    unittest
    {
        auto scripts = Scripts.create();
        scope (exit)
            scripts.remove();
        auto databases = Databases.create();
        scope (exit)
            databases.close();
        auto initializer = new DataSourceScriptDatabaseInitializer(databases.embedded,
                schemaAndData(scripts, DatabaseInitializationMode.ALWAYS));
        assert(initializer.initializeDatabase());
        assert(numberOfRows(databases.embedded, "SELECT COUNT(*) FROM EXAMPLE") == 1);
    }

    @("DataSourceScriptDatabaseInitializerTests.whenModeIsAlwaysThenStandaloneDatabaseIsInitialized")
    unittest
    {
        auto scripts = Scripts.create();
        scope (exit)
            scripts.remove();
        auto databases = Databases.create();
        scope (exit)
            databases.close();
        auto initializer = new DataSourceScriptDatabaseInitializer(databases.standalone,
                schemaAndData(scripts, DatabaseInitializationMode.ALWAYS));
        assert(initializer.initializeDatabase());
        assert(numberOfRows(databases.standalone, "SELECT COUNT(*) FROM EXAMPLE") == 1);
    }

    @("DataSourceScriptDatabaseInitializerTests.whenCustomizeIsOverriddenThenDatabasePopulatorIsConfiguredAccordingly")
    unittest
    {
        import flint.jdbc.datasource.init : ResourceDatabasePopulator, ScriptStatementFailedException;

        static bool continueOnError(ResourceDatabasePopulator populator)
        {
            // Boot reads the field reflectively (hasFieldOrPropertyWithValue).
            foreach (i, value; populator.tupleof)
                static if (__traits(identifier, populator.tupleof[i]) == "continueOnError")
                    return value;
            assert(false, "no continueOnError field");
        }

        static final class CustomizingInitializer : DataSourceScriptDatabaseInitializer
        {
            this(DataSource dataSource, DatabaseInitializationSettings settings)
            {
                super(dataSource, settings);
            }

            protected override void customize(ResourceDatabasePopulator populator)
            {
                assert(continueOnError(populator));
                populator.setContinueOnError(false);
            }
        }

        auto scripts = Scripts.create();
        scope (exit)
            scripts.remove();
        auto databases = Databases.create();
        scope (exit)
            databases.close();
        auto settings = new DatabaseInitializationSettings;
        settings.setContinueOnError(true);
        settings.setDataLocations([scripts.location("data.sql")]);
        auto initializer = new CustomizingInitializer(databases.embedded, settings);
        bool thrown;
        try
            initializer.initializeDatabase();
        catch (ScriptStatementFailedException)
            thrown = true;
        assert(thrown);
    }
}
