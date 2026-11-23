module flint.boot_autoconfigure_data.autoconfigure_data_test;

import flint.arena : RequestArena, Status;
import flint.engine.di : AppContext, ConfiguredSections;
import flint.boot_autoconfigure_data : Context, DataSourceAutoConfiguration, DataSource, DatabaseProperties,
    Id, JdbcRepository, Table, Text, migrationDescription, migrationVersion, toString, toText;

@safe:

@("migration file names give the version and the description")
unittest
{
    assert(migrationVersion("V000012__add_tags.sql") == 12);
    assert(migrationDescription("V000012__add_tags.sql") == "add tags");
    assert(migrationVersion("V1__init.sql") == 1 && migrationDescription("V1__init.sql") == "init");
}

@Table("notes")
private struct Note
{
    @Id ulong id;
    Text title;
}

@("the data source opens the configured pool and a repository saves and finds rows")
unittest
{
    import std.file : remove, tempDir;
    import std.path : buildPath;
    import std.uuid : randomUUID;

    const path = buildPath(tempDir(), "flint-starter-data-" ~ randomUUID().toString() ~ ".db");
    scope (exit)
        remove(path);
    AppContext!(DataSourceAutoConfiguration, ConfiguredSections!("database"), JdbcRepository!(Note, ulong)) context;
    DatabaseProperties properties;
    properties.url = "file:" ~ path;
    assert(context.provide(properties).code == Status.ok);
    // The repository checks its table at construction, so the schema exists before the context starts.
    {
        import flint.engine.sql : Driver, Pool, PoolOptions;

        import flint.engine.migrate : Migration, MigrationOptions, migrate;
        import std.digest.sha : sha256Of;

        Pool setup;
        PoolOptions options;
        options.driver = Driver.sqlite;
        options.connectionString = properties.url;
        assert(setup.open(options).code == Status.ok);
        Context cancellation;
        Migration[1] plan;
        plan[0].versionNumber = 1;
        plan[0].description = "create notes";
        plan[0].sql = "create table notes (id integer primary key, title text not null);";
        plan[0].sha256 = sha256Of(plan[0].sql);
        const migrated = migrate(setup, plan[], MigrationOptions.init, cancellation);
        assert(migrated.ok && migrated.value.applied == 1);
        assert(setup.close(cancellation).code == Status.ok);
    }
    assert(context.initialize().code == Status.ok);
    scope (exit)
        context.shutdown();
    ubyte[4096] storage;
    auto arena = RequestArena(storage[]);
    Context cancellation;
    auto repository = context.get!(JdbcRepository!(Note, ulong))();
    Note note;
    note.title = toText(arena, "First").value;
    const saved = repository.save(note, arena, cancellation);
    assert(saved.ok && saved.value.id != 0);
    const found = repository.findById(saved.value.id, arena, cancellation);
    assert(found.ok && toString(arena, found.value.title) == "First");
    assert(repository.existsById(saved.value.id, cancellation).value);
    assert(repository.deleteById(saved.value.id, cancellation).code == Status.ok);
    assert(!repository.existsById(saved.value.id, cancellation).value);
}
