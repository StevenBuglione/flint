/// PostgreSQL's JDBC driver class: constructing it enables the engine driver, which is what declaring the dependency costs.
module app;

import flint.postgresql : Driver;
import core.stdc.stdio : fputc, stdout;

@safe:

/// Writes one line without Phobos, so the probe adds no std.format template instances to the module's count.
private void emit(scope const(char)[] text) nothrow @nogc
{
    foreach (c; text)
        fputc(c, stdout);
    fputc('\n', stdout);
}

int main(string[] args)
{
    auto driver = new Driver;
    const accepted = driver.acceptsURL(args.length > 1 ? "jdbc:sqlite::memory:" : "jdbc:postgresql:x");
    emit(accepted ? "accepted" : "rejected");
    return 0;
}
