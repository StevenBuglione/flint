/++
`org.postgresql` (PgJDBC, `org.postgresql:postgresql`): the JDBC driver class an application declares to use PostgreSQL.

Java finds a driver through the jar on the class path. Flint links only the drivers an application declares, so
this package is that declaration: Boot's DataSource auto-configuration enables the engine's PostgreSQL driver
when `flint.postgresql.Driver` is present, and constructing the class enables it too (performance playbook S-1).
An application without this dependency links none of the driver's native code (libpq and OpenSSL).
+/
module flint.postgresql;

import flint.engine.jdbc : FlintDriver, enablePostgres;
import flint.java.sql : Connection, Driver_ = Driver, DriverManager;
import flint.java.util : Properties;

@safe:

/// PgJDBC's `org.postgresql.Driver`: the JDBC driver for `jdbc:postgresql:` URLs, over Flint's engine driver.
final class Driver : Driver_
{
    private FlintDriver engine;

    /// Enables the engine driver; throws `SQLException` (08001) when this build has no native library for it.
    this()
    {
        enablePostgres();
        engine = new FlintDriver;
    }

    /// A connection for `url`, or null when it is not a `jdbc:postgresql:` URL.
    override Connection connect(string url, Properties info)
    {
        return acceptsURL(url) ? engine.connect(url, info) : null;
    }

    /// Whether `url` starts with `jdbc:postgresql:`.
    override bool acceptsURL(string url)
    {
        return url.length >= "jdbc:postgresql:".length && url[0 .. "jdbc:postgresql:".length] == "jdbc:postgresql:";
    }

    /// The engine driver's major version.
    override int getMajorVersion()
    {
        return engine.getMajorVersion();
    }

    /// The engine driver's minor version.
    override int getMinorVersion()
    {
        return engine.getMinorVersion();
    }

    /// The engine driver does not claim JDBC compliance.
    override bool jdbcCompliant()
    {
        return false;
    }
}

private Driver_ supply()
{
    return new Driver;
}

/// Registers the driver with the `DriverManager`, as the driver jar's `META-INF/services/java.sql.Driver` does; the
/// first lookup constructs it, which enables the engine driver.
shared static this()
{
    DriverManager.registerDriver(&supply);
}
