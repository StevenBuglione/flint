/// flint:boot-autoconfigure-data: Flint Boot's auto-configuration for flint:engine-data (ADR-029 section 8, ADR-028
/// sections 7 and 8): a SQL pool from `[database]`, the project's migrations (resources/migrations) applied at
/// start-up, and repositories as beans.
///
/// Entities are flint:engine-data structs. Text columns are `Text` handles in the request arena, so a repository call
/// takes `context.arena` and the handler returns the entity in the same request; `toString` and `toText` convert
/// at the edges where business logic needs a `string`.
module flint.boot_autoconfigure_data;

import flint.arena : Error, Result, Status;
import flint.config : ConfigurationProperties;
import flint.engine.di : AutoConfiguration, ConditionalOnConfig, PostConstruct, PreDestroy, Provided, Service;
import flint.engine.migrate : Migration;
import flint.engine.sql : Pool;

public import flint.arena : RequestArena, Text;
public import flint.conc : Context;
public import flint.engine.data : Column, CrudRepository, Id, Nullable, ReadOnly, Table, Version;

@safe:

/// The `[database]` section.
@ConditionalOnConfig("database")
@ConfigurationProperties("database")
struct DatabaseProperties
{
    /// `sqlite` or `postgres`.
    string driver = "sqlite";
    /// A SQLite path or URI (`file:data.db`), or libpq connection settings.
    string url;
    /// Connections leased at once, at most 16.
    uint maxConnections = 4;
    /// Apply the migrations at start-up.
    bool migrate = true;
    /// Directory of `V<version>__<description>.sql` files, relative to the working directory.
    string migrations = "resources/migrations";
}

/// The pool: opened and migrated at start-up, closed at shutdown. Registered only with a `[database]` section.
@ConditionalOnConfig("database")
@Service
final class DataSource
{
    private DatabaseProperties properties;
    private Pool store;
    private bool opened;

    /// Receive the bound settings.
    this(DatabaseProperties properties)
    {
        this.properties = properties;
    }

    /// Open the pool and apply the migrations.
    @PostConstruct
    Error open()
    {
        import flint.engine.sql : Driver, PoolOptions;

        PoolOptions options;
        if (properties.driver == "sqlite")
            options.driver = Driver.sqlite;
        else if (properties.driver != "postgres")
            return Error(Status.invalidArgument, "database.driver must be sqlite or postgres");
        options.connectionString = properties.url;
        options.maxConnections = properties.maxConnections;
        const started = store.open(options);
        if (started.code != Status.ok)
            return started;
        opened = true;
        return properties.migrate ? applyMigrations() : Error.init;
    }

    private Error applyMigrations()
    {
        import flint.engine.migrate : MigrationOptions, migrate;

        auto plan = loadMigrations(properties.migrations);
        if (!plan.ok || plan.value.length == 0)
            return plan.error;
        Context context;
        return migrate(store, plan.value, MigrationOptions.init, context).error;
    }

    /// The pool, for repositories and queries.
    ref Pool pool() return
    {
        return store;
    }

    /// Close the pool.
    @PreDestroy
    void close() nothrow
    {
        if (!opened)
            return;
        Context context;
        cast(void) store.close(context);
        opened = false;
    }
}

/// A repository for entity `E` keyed by `ID`, over the data source. Declare the application's repository as a
/// scanned bean, as with Spring Data:
///
/// ---
/// @Repository final class NoteRepository : JdbcRepository!(Note, ulong)
/// {
///     this(DataSource source) { super(source); }
/// }
/// ---
class JdbcRepository(E, ID) : CrudRepository!(E, ID)
{
    import flint.engine.data : SqlRepository;

    private SqlRepository!(E, ID) inner;

    /// Check the table and columns against the migrated schema.
    this(DataSource source)
    {
        inner = new SqlRepository!(E, ID)(source.pool());
    }

    /// Fetch the row with this identifier into `arena`.
    override Result!E findById(ID id, ref scope RequestArena arena, ref Context context) nothrow @nogc
    {
        return inner.findById(id, arena, context);
    }

    /// Insert (a zero identifier) or update the entity, returning the stored row.
    override Result!E save(scope const ref E entity, ref scope RequestArena arena, ref Context context) nothrow @nogc
    {
        return inner.save(entity, arena, context);
    }

    /// Delete the identifier if present.
    override Error deleteById(ID id, ref Context context) nothrow @nogc
    {
        return inner.deleteById(id, context);
    }

    /// Whether the identifier is present.
    override Result!bool existsById(ID id, ref Context context) nothrow @nogc
    {
        return inner.existsById(id, context);
    }

    /// The underlying flint:engine-data repository, for `queryOne` and projections.
    SqlRepository!(E, ID) sql()
    {
        return inner;
    }
}

/// The data source's auto-configuration.
alias DataSourceAutoConfiguration = AutoConfiguration!(Provided!DatabaseProperties, DataSource);

/// The migrations in `directory`: every `V<version>__<description>.sql`, in version order, read at start-up like
/// config/ (flint package ships resources/). An absent directory has none.
Result!(Migration[]) loadMigrations(string directory)
{
    import std.algorithm.sorting : sort;
    import std.digest.sha : sha256Of;
    import std.file : DirEntry, FileException, dirEntries, exists, isDir, readText, SpanMode;
    import std.path : baseName;

    Migration[] plan;
    if (!exists(directory) || !isDir(directory))
        return Result!(Migration[])(plan);
    try
    {
        foreach (DirEntry entry; dirEntries(directory, "V*.sql", SpanMode.shallow, false))
        {
            Migration migration;
            const file = baseName(entry.name);
            migration.versionNumber = migrationVersion(file);
            migration.description = migrationDescription(file);
            migration.sql = readText(entry.name);
            migration.sha256 = sha256Of(migration.sql);
            if (migration.versionNumber == 0)
                return Result!(Migration[])(null, Error(Status.invalidArgument,
                        "migration file names start with V<version>__, such as V000001__create_notes.sql"));
            plan ~= migration;
        }
    }
    catch (FileException)
        return Result!(Migration[])(null, Error(Status.ioError, "could not read the migrations directory"));
    sort!((a, b) => a.versionNumber < b.versionNumber)(plan);
    return Result!(Migration[])(plan);
}

/// `V000012__add_tags.sql` is version 12.
ulong migrationVersion(string file) pure
{
    ulong version_;
    foreach (ch; file[1 .. $])
    {
        if (ch < '0' || ch > '9')
            break;
        version_ = version_ * 10 + (ch - '0');
    }
    return version_;
}

/// `V000012__add_tags.sql` is "add tags".
string migrationDescription(string file) pure
{
    size_t start;
    while (start + 1 < file.length && !(file[start] == '_' && file[start + 1] == '_'))
        start++;
    string text = start + 2 <= file.length ? file[start + 2 .. $] : file;
    if (text.length > 4 && text[$ - 4 .. $] == ".sql")
        text = text[0 .. $ - 4];
    string result;
    foreach (ch; text)
        result ~= ch == '_' ? ' ' : ch;
    return result;
}

/// The text of a `Text` handle, copied out of the arena.
string toString(ref scope RequestArena arena, Text value)
{
    auto copy = new char[value.bytes.length()];
    const read = arena.read(value.bytes, (scope const(ubyte)[] bytes) @safe nothrow @nogc {
        copy[0 .. bytes.length] = cast(const(char)[]) bytes;
    });
    return read == Status.ok ? copy.idup : null;
}

/// A `Text` handle for `value`, copied into the arena.
Result!Text toText(ref scope RequestArena arena, scope const(char)[] value)
{
    auto copied = arena.copyIn(cast(const(ubyte)[]) value);
    return copied.ok() ? Result!Text(Text(copied.value)) : Result!Text(Text.init, copied.error);
}
