// Declaration-only public contract; runtime implementation belongs in scaffold/packages.
module flint.migrate;
import flint.arena : Error, Result;
import flint.conc : Context;
import flint.sql : Pool;

@safe:
struct Migration
{
    ulong versionNumber;
    string description;
    string sql;
    ubyte[32] sha256;
    bool transactional = true;
}

struct MigrationOptions
{
    string historyTable = "flint_schema_history";
    long lockTimeoutNanos = 30_000_000_000L;
    bool validateOnly = false;
}

struct MigrationReport
{
    uint discovered;
    uint applied;
    ulong currentVersion;
}

Migration embeddedMigration(string fileName, ulong versionNumber, string description, bool transactional = true)();
Result!MigrationReport migrate(ref Pool pool, scope const(Migration)[] migrations,
        MigrationOptions options, ref Context context);
Error validateHistory(ref Pool pool, scope const(Migration)[] migrations, ref Context context);
