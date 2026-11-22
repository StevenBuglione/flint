/// Output of every command: one JSON document on stdout with --json, or human text and diagnostics.
module flint_tool.commands.output;

import flint_tool.engine.session : Session;
import flint_tool.diagnostics.report : Report, renderHuman;

@safe:

/// Finish a command: fill the envelope fields, print, and return the exit code.
///
/// Every command's JSON document carries `schema`, `ok`, `exit_code` and `diagnostics` (diagnostic schema 1).
int finish(T)(ref Session session, ref Report report, ref T payload)
{
    import flint.serde.owned : serialize;
    import flint_tool.sys.posix : writeError, writeOutput;

    payload.ok = report.ok;
    payload.exit_code = cast(int) report.exitCode;
    payload.diagnostics = report.items.dup;
    if (session.json)
    {
        auto text = serialize(payload);
        if (!text.ok)
        {
            writeError(
                    "flint: internal error: cannot encode the " ~ payload.schema ~ " report: "
                    ~ text.error.message ~ "\n");
            return 1;
        }
        writeOutput(text.value ~ "\n");
    }
    else if (report.items.length)
        writeError(renderHuman(report.items, session.errorPalette));
    return payload.exit_code;
}

/// Emit diagnostics raised before a command's own report exists (usage and installation errors).
int finishBare(ref Session session, ref Report report, string schema)
{
    import flint_tool.diagnostics.report : Diagnostic;

    static struct Bare
    {
        string schema;
        bool ok;
        int exit_code;
        Diagnostic[] diagnostics;
    }

    Bare payload;
    payload.schema = schema;
    return finish(session, report, payload);
}
