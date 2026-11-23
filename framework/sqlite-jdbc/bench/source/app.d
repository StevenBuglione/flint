/// SQLite's JDBC driver class: constructing it enables the engine driver, which is what declaring the dependency costs.
module app;

import flint.sqlite : JDBC;
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
    auto driver = new JDBC;
    const accepted = driver.acceptsURL(args.length > 1 ? "jdbc:postgresql://db/app" : "jdbc:sqlite:x");
    emit(accepted ? "accepted" : "rejected");
    return 0;
}
