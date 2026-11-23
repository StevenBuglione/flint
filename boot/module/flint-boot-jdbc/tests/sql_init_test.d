// Ported from spring-boot v4.2.0: module/spring-boot-sql/src/test/java/org/springframework/boot/sql/init/AbstractScriptDatabaseInitializerTests.java
// with ../../jdbc/init/DataSourceScriptDatabaseInitializerTests.java and the settings cases of
// ../autoconfigure/init/SettingsCreatorTests.java
// Copyright 2012-present the original author or authors.
// Licensed under the Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0).
// Modified by the Flint authors: scripts are files under a temporary directory (`file:` locations); the cases that
// touch a database run on in-memory SQLite and need FlintNativeSqlite, as engine-jdbc's driver tests do.
module sql_init_test;

import flint.boot.jdbc.autoconfigure : ApplicationDataSourceScriptDatabaseInitializer;
import flint.boot.sql.autoconfigure.init : ApplicationScriptDatabaseInitializer, SqlInitializationProperties;
import flint.boot.sql.init : DatabaseInitializationMode, DatabaseInitializationSettings;
import flint.engine.jdbc : FlintDataSource;
import flint.java.lang : IllegalStateException;

@safe:

private string scriptDirectory(string name) @trusted
{
    // SAFETY: test-only; writes two small files under the system temp directory.
    import std.file : mkdirRecurse, tempDir, write;
    import std.path : buildPath;
    import std.process : thisProcessID;
    import std.conv : to;

    const directory = buildPath(tempDir(), "flint-sql-init-" ~ thisProcessID.to!string ~ "-" ~ name);
    mkdirRecurse(directory);
    write(buildPath(directory, "schema.sql"), "CREATE TABLE example (id INTEGER PRIMARY KEY, name VARCHAR(50));\n");
    write(buildPath(directory, "data.sql"),
            "INSERT INTO example VALUES (1, 'Andy');\n" ~ "-- a comment\nINSERT INTO example VALUES (2, 'Andy');\n");
    return directory;
}

private DatabaseInitializationSettings settings(string directory, DatabaseInitializationMode mode)
{
    auto settings = new DatabaseInitializationSettings;
    settings.setSchemaLocations(["file:" ~ directory ~ "/schema.sql"]);
    settings.setDataLocations(["file:" ~ directory ~ "/data.sql"]);
    settings.setMode(mode);
    return settings;
}

@("whenDatabaseIsInitializedWithNeverModeThenNothingIsApplied") unittest
{
    auto initializer = new ApplicationDataSourceScriptDatabaseInitializer(new FlintDataSource,
            settings(scriptDirectory("never"), DatabaseInitializationMode.NEVER));
    assert(!initializer.initializeDatabase());
}

@("whenNoScriptsExistAtASchemaLocationThenInitializationFails") unittest
{
    auto settings = new DatabaseInitializationSettings;
    settings.setSchemaLocations(["file:/does/not/exist/schema.sql"]);
    auto initializer = new ApplicationDataSourceScriptDatabaseInitializer(new FlintDataSource, settings);
    bool thrown;
    try
        initializer.initializeDatabase();
    catch (IllegalStateException e)
        thrown = e.msg == "No schema scripts found at location 'file:/does/not/exist/schema.sql'";
    assert(thrown);
}

@("whenNoScriptsExistAtAnOptionalSchemaLocationThenInitializationSucceeds") unittest
{
    auto settings = new DatabaseInitializationSettings;
    settings.setSchemaLocations(["optional:file:/does/not/exist/schema.sql"]);
    settings.setMode(DatabaseInitializationMode.ALWAYS);
    assert(!new ApplicationDataSourceScriptDatabaseInitializer(new FlintDataSource, settings).initializeDatabase());
}

@("SettingsCreator: default locations are optional schema-<platform>.sql and schema.sql") unittest
{
    auto properties = new SqlInitializationProperties;
    properties.setPlatform("postgres");
    auto settings = ApplicationScriptDatabaseInitializer.getSettings(properties);
    assert(settings.getSchemaLocations() == [
        "optional:classpath*:schema-postgres.sql", "optional:classpath*:schema.sql"
    ]);
    assert(settings.getDataLocations() == [
        "optional:classpath*:data-postgres.sql", "optional:classpath*:data.sql"
    ]);
    assert(settings.getMode() == DatabaseInitializationMode.EMBEDDED);
    properties.setSchemaLocations(["classpath*:db/postgres/schema.sql"]);
    assert(ApplicationScriptDatabaseInitializer.getSettings(properties)
            .getSchemaLocations() == ["classpath*:db/postgres/schema.sql"]);
}

version (FlintNativeSqlite)
{
    private FlintDataSource embedded(string name)
    {
        return new FlintDataSource("jdbc:sqlite:file:" ~ name ~ "?mode=memory&cache=shared");
    }

    private long count(FlintDataSource dataSource)
    {
        import flint.jdbc.core : JdbcTemplate;

        return new JdbcTemplate(dataSource).queryForObject!long("SELECT COUNT(*) FROM example");
    }

    @("whenDatabaseIsInitializedThenSchemaAndDataScriptsAreApplied: EMBEDDED on an in-memory database") unittest
    {
        auto dataSource = embedded("sql-init-embedded");
        scope (exit)
            dataSource.close();
        auto initializer = new ApplicationDataSourceScriptDatabaseInitializer(dataSource,
                settings(scriptDirectory("embedded"), DatabaseInitializationMode.EMBEDDED));
        initializer.afterPropertiesSet();
        assert(count(dataSource) == 2);
    }

    @("whenContinueOnErrorIsFalseThenInitializationFailsOnError") unittest
    {
        auto dataSource = embedded("sql-init-error");
        scope (exit)
            dataSource.close();
        auto settings = settings(scriptDirectory("error"), DatabaseInitializationMode.ALWAYS);
        settings.setSchemaLocations(settings.getSchemaLocations() ~ settings.getSchemaLocations());
        bool thrown;
        try
            new ApplicationDataSourceScriptDatabaseInitializer(dataSource, settings).initializeDatabase();
        catch (Exception)
            thrown = true;
        assert(thrown);
    }

    @("whenContinueOnErrorIsTrueThenInitializationDoesNotFailOnError") unittest
    {
        auto dataSource = embedded("sql-init-continue");
        scope (exit)
            dataSource.close();
        auto settings = settings(scriptDirectory("continue"), DatabaseInitializationMode.ALWAYS);
        settings.setSchemaLocations(settings.getSchemaLocations() ~ settings.getSchemaLocations());
        settings.setContinueOnError(true);
        assert(new ApplicationDataSourceScriptDatabaseInitializer(dataSource, settings).initializeDatabase());
        assert(count(dataSource) == 2);
    }
}
