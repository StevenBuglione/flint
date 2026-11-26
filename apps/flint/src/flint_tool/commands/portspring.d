/// CLI output for the opt-in mechanical Spring translator.
module flint_tool.commands.portspring;

import flint_tool.api.portspring : SpringPort, SpringPortRequest, portSpring;
import flint_tool.diagnostics.report : Diagnostic, Report;
import flint_tool.engine.session : Session;

@safe:

/// Translate a pinned Java declaration into a reviewable D source and mapping fragment.
int commandPortSpring(ref Session session, const ref SpringPortRequest request, string output)
{
    import flint_tool.commands.output : finish;
    import std.file : FileException;

    Report report;
    SpringPortReport payload;
    string error;
    if (!session.json && !output.length)
        report.error("FLINT-E0002", "port-spring needs --output DIR or --json", "flint port-spring --help");
    else if (!portSpring(session.home.root, request, payload.port, error))
        report.error("FLINT-E1009", error, "see flint port-spring --help");
    else if (output.length)
    {
        try
        {
            writeCandidate(output, request.module_, payload.port);
            session.progress("Wrote", output);
        }
        catch (FileException failure)
        {
            report.error("FLINT-E1010", failure.msg, "choose a new --output directory with a writable parent");
        }
    }
    if (report.ok && payload.port.inherited)
        session.progress("Review", request.type ~ " declares Java @Inherited");
    return finish(session, report, payload);
}

private struct SpringPortReport
{
    import flint.serde : JsonFlatten;

    string schema = "flint.port-spring/1";
    bool ok;
    int exit_code;
    Diagnostic[] diagnostics;
    @JsonFlatten
    SpringPort port;
}

private void writeCandidate(string directory, string module_, const ref SpringPort port)
{
    import std.file : exists, mkdir, remove, rmdir, write;
    import std.path : buildPath;
    import std.string : lastIndexOf;

    const sourcePath = buildPath(directory, module_[module_.lastIndexOf('.') + 1 .. $] ~ ".d");
    const mappingPath = buildPath(directory, "mapping.json");
    mkdir(directory);
    scope (failure)
    {
        foreach (path; [sourcePath, mappingPath])
            if (exists(path))
                remove(path);
        rmdir(directory);
    }
    write(sourcePath, port.source);
    write(mappingPath, port.mapping);
}
