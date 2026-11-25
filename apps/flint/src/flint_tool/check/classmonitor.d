/// The class-monitor gate (FLINT-E0536) in `flint check`: class metadata never owns a GC-allocated monitor (owner
/// rule of 2026-11-25, docs/spring/phase1/decisions.md). tools/check_class_monitor.py type-checks the argument of
/// every `new Mutex(obj)` and `setSameMutex(ownee, owner)` with the pinned compiler, as `tools/gates.py --gate
/// structural` does; this module reports its verdict. `flint build` never runs it.
module flint_tool.check.classmonitor;

import flint_tool.diagnostics.report : Report, Severity, at, diagnostic;

@safe:

/// The diagnostic code of the gate.
enum classMonitorCode = "FLINT-E0536";

/// One finding or failure, as tools/check_class_monitor.py --json prints it.
private struct MonitorEntry
{
    string file;
    long line;
    string message;
    string fix;
}

/// One honoured suppression.
private struct MonitorSuppression
{
    string file;
    long line;
    string reason;
}

/// The gate's verdict.
private struct MonitorVerdict
{
    bool ok;
    MonitorEntry[] findings;
    MonitorEntry[] errors;
    MonitorSuppression[] suppressions;
    long modules;
    long compiles;
    string compiler;
}

/// Run the gate over the checkout at `root` with `dmd` (empty: the script's own choice) and report every finding.
/// Returns the summary line for the progress output.
string checkClassMonitor(string root, string dmd, ref Report report)
{
    import std.conv : to;
    import std.path : buildPath;
    import flint.serde : DecodeOptions, UnknownFields;
    import flint.serde.owned : deserialize;
    import flint_tool.support.process : capture;

    string[] argv = [
        "python3", buildPath(root, "tools", "check_class_monitor.py"), "--json", "--root", root
    ];
    if (dmd.length)
        argv ~= ["--compiler", dmd];
    const result = capture(argv);
    DecodeOptions lenient;
    lenient.unknownFields = UnknownFields.ignore;
    const decoded = deserialize!MonitorVerdict(result.output, lenient);
    if (!result.started || !decoded.ok)
    {
        report.error(classMonitorCode, "the class-monitor gate gave no verdict", result.combined());
        return null;
    }
    foreach (ref entry; decoded.value.findings ~ decoded.value.errors)
        report.add(at(diagnostic(classMonitorCode, Severity.error, entry.message, entry.fix), entry.file, entry.line));
    if (!decoded.value.ok && decoded.value.findings.length + decoded.value.errors.length == 0)
        report.error(classMonitorCode, "the class-monitor gate failed without a finding", result.combined());
    return decoded.value.modules.to!string ~ " module(s) type-checked, "
        ~ decoded.value.suppressions.length.to!string ~ " suppression(s) honoured";
}
