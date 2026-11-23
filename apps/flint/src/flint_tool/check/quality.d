/// Formatting and lint, ported from tools/quality.py: dfmt byte comparison and D-Scanner reports.
module flint_tool.check.quality;

import flint_tool.diagnostics.report : Report, Severity, at, diagnostic;

@safe:

/// What the quality checks covered.
struct QualitySummary
{
    /// Files checked.
    long files;
    /// Files whose formatting differs.
    long unformatted;
    /// D-Scanner warnings and errors.
    long issues;
    /// The formatter identity, as tools/quality.py reports it.
    string formatter = "dfmt0.15.2+flint.stack-udas stdout byte comparison";
}

/// One D-Scanner issue.
struct ScannerIssue
{
    /// File the issue is in.
    string fileName;
    /// One-based line.
    long line;
    /// One-based column.
    long column;
    /// Message.
    string message;
    /// "warn" or "error" fail the check.
    string type;
    /// Check name.
    string key;
}

private struct ScannerReport
{
    ScannerIssue[] issues;
}

/// D sources below `trees` (absolute), sorted and unique. With `buildOutputs`, `build` and `artifacts`
/// directories are skipped as tools/quality.py skips them; cache directories always are.
string[] qualityFiles(scope const(string)[] trees, bool buildOutputs = false)
{
    import std.algorithm.iteration : uniq;
    import std.algorithm.sorting : sort;
    import std.array : array;
    import std.path : buildPath;
    import flint_tool.support.files : dSources;

    string[] files;
    foreach (tree; trees)
    {
        foreach (relative; dSources(tree, buildOutputs))
            files ~= buildPath(tree, relative);
    }
    sort(files);
    return files.uniq.array;
}

/// FLINT-E0601 for a file dfmt would change. Flint sources are LF (.editorconfig, `flint new`'s .gitattributes), so
/// a CRLF file is named as such rather than pointed at line 1.
private auto formatterDifference(scope const(char)[] source)
{
    import std.algorithm.searching : canFind;

    if (source.canFind("\r\n"))
        return diagnostic("FLINT-E0601", Severity.error,
                "formatter difference: CRLF line endings (Flint sources are LF)",
                "flint fmt; add `* text=auto eol=lf` to .gitattributes");
    return diagnostic("FLINT-E0601", Severity.error, "formatter difference", "flint fmt");
}

/// Compare every file with dfmt's output (configured by `configRoot`/.editorconfig), then run D-Scanner.
/// `displayRoot` shortens paths in diagnostics.
QualitySummary checkQuality(scope const(string)[] files, string dfmt, string dscanner,
        string configRoot, string displayRoot, ref Report report)
{
    import std.file : exists, read;
    import std.path : buildPath;
    import flint_tool.support.files : relativeTo;
    import flint_tool.support.process : capture;

    QualitySummary summary;
    summary.files = cast(long) files.length;
    if (!qualityToolsReady(dfmt, dscanner, report))
        return summary;
    foreach (file; files)
    {
        const source = cast(const(char)[]) read(file);
        const formatted = capture([dfmt, "--config", configRoot, file]);
        const display = relativeTo(file, displayRoot);
        if (!formatted.ok)
        {
            report.add(at(diagnostic("FLINT-E0601", Severity.error,
                    "dfmt failed: " ~ formatted.failure ~ formatted.errors, "fix the syntax error dfmt reports"),
                    display, 0));
            ++summary.unformatted;
            continue;
        }
        if (formatted.output != source)
        {
            ++summary.unformatted;
            report.add(at(formatterDifference(source), display, firstDifferentLine(source,
                    formatted.output), 0, cast(string) source.idup));
        }
    }
    const config = buildPath(configRoot, "dscanner.ini");
    for (size_t start = 0; start < files.length; start += 100)
    {
        const batch = files[start .. start + 100 < files.length ? start + 100 : files.length];
        string[] command = [dscanner, "--report", "--config", config];
        command ~= batch;
        const outcome = capture(command);
        if (!outcome.started)
        {
            report.error("FLINT-E0807", "D-Scanner could not run: " ~ outcome.failure,
                    "python3 tools/install_quality_tools.py");
            return summary;
        }
        import flint.serde : DecodeOptions, UnknownFields;
        import flint.serde.owned : deserialize;

        DecodeOptions options;
        options.unknownFields = UnknownFields.ignore;
        options.maxBytes = 1 << 20;
        options.maxMembers = 1024;
        auto parsed = deserialize!ScannerReport(outcome.output, options);
        if (!parsed.ok)
        {
            report.error("FLINT-E0807", "unknown D-Scanner report shape: " ~ parsed.error.message,
                    "python3 tools/install_quality_tools.py");
            return summary;
        }
        foreach (issue; parsed.value.issues)
        {
            if (issue.type != "warn" && issue.type != "error")
                continue;
            ++summary.issues;
            const display = relativeTo(issue.fileName, displayRoot);
            report.add(at(diagnostic("FLINT-E0602", Severity.error,
                    issue.message ~ (issue.key.length ? " [" ~ issue.key ~ "]" : ""), "fix the reported code"),
                    display, issue.line, issue.column, exists(issue.fileName)
                    ? cast(string)(cast(const(char)[]) read(issue.fileName)).idup : null));
        }
    }
    return summary;
}

/// Both tools exist and dfmt is Flint's patched build; every missing piece is reported.
private bool qualityToolsReady(string dfmt, string dscanner, ref Report report)
{
    const present = toolPresent(dfmt, "dfmt", report) & toolPresent(dscanner, "dscanner", report);
    return present && dfmtPatched(dfmt, report);
}

private bool toolPresent(string path, string name, ref Report report)
{
    import std.file : exists;

    if (path.length && exists(path))
        return true;
    report.error("FLINT-E0807", name ~ " is not installed at " ~ path, "python3 tools/install_quality_tools.py");
    return false;
}

/// The `--version` suffix of Flint's patched dfmt (toolchain/dfmt-0.15.2-stack-udas.patch). An upstream dfmt
/// joins stacked user-defined attributes back onto their declaration's line, so `flint fmt` refuses it.
enum dfmtFlintSuffix = "+flint.stack-udas";

private bool dfmtPatched(string dfmt, ref Report report)
{
    import std.algorithm.searching : canFind;
    import flint_tool.support.process : capture;

    const version_ = capture([dfmt, "--version"]);
    if (version_.ok && version_.output.canFind(dfmtFlintSuffix))
        return true;
    report.error("FLINT-E0807", dfmt ~ " is not Flint's patched dfmt (its --version lacks " ~ dfmtFlintSuffix ~ ")",
            "python3 tools/install_quality_tools.py");
    return false;
}

/// One-based first line where two texts differ.
long firstDifferentLine(scope const(char)[] left, scope const(char)[] right)
{
    long line = 1;
    foreach (index; 0 .. left.length < right.length ? left.length : right.length)
    {
        if (left[index] != right[index])
            return line;
        line += left[index] == '\n';
    }
    return line;
}

/// Rewrite files in place with dfmt; returns the files that changed.
string[] formatFiles(scope const(string)[] files, string dfmt, string configRoot, ref Report report)
{
    import std.file : read, write;
    import flint_tool.support.process : capture;

    string[] changed;
    if (!toolPresent(dfmt, "dfmt", report) || !dfmtPatched(dfmt, report))
        return null;
    foreach (file; files)
    {
        const source = cast(const(char)[]) read(file);
        const formatted = capture([dfmt, "--config", configRoot, file]);
        if (!formatted.ok)
        {
            report.add(at(diagnostic("FLINT-E0601", Severity.error,
                    "dfmt failed: " ~ formatted.errors, "fix the syntax error dfmt reports"), file, 0));
            continue;
        }
        if (formatted.output != source)
        {
            write(file, formatted.output);
            changed ~= file;
        }
    }
    return changed;
}
