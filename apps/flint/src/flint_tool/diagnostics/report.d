/// Structured diagnostics: collection, exit-code mapping, and human and JSON rendering.
module flint_tool.diagnostics.report;

import flint_tool.diagnostics.catalog : CodeInfo, ExitCode, lookup;

@safe:

/// Severity of one diagnostic.
enum Severity : ubyte
{
    error,
    warning,
    note
}

/// One diagnostic in its stable JSON shape (diagnostic schema 1).
struct Diagnostic
{
    /// `FLINT-Ennnn`.
    string code;
    /// "error", "warning" or "note".
    string severity;
    /// The catalogue title for the code.
    string title;
    /// The cause in this instance.
    string message;
    /// File, relative to the project root when inside it; empty for non-file problems.
    string file;
    /// One-based line, or zero.
    long line;
    /// One-based column, or zero.
    long column;
    /// The source line at the location, when known.
    string snippet;
    /// What to do about it.
    string fix;
}

/// Build a diagnostic for a catalogued code. Unknown codes are a programming error.
Diagnostic diagnostic(string code, Severity severity, string message, string fix = null)
{
    const info = lookup(code);
    assert(info !is null, "uncatalogued diagnostic code " ~ code);
    Diagnostic result;
    result.code = info.code;
    result.severity = severity == Severity.error ? "error" : severity == Severity.warning ? "warning" : "note";
    result.title = info.title;
    result.message = message;
    result.fix = fix;
    return result;
}

/// Attach a file location, filling the snippet from `source` when given.
Diagnostic at(Diagnostic value, string file, long line, long column = 0, string source = null)
{
    value.file = file;
    value.line = line;
    value.column = column;
    if (source !is null && line > 0)
        value.snippet = sourceLine(source, line);
    return value;
}

/// The one-based `line` of `source`, without its newline.
string sourceLine(string source, long line)
{
    long current = 1;
    size_t start;
    foreach (index, ch; source)
    {
        if (current == line && ch == '\n')
            return source[start .. index];
        if (ch == '\n')
        {
            ++current;
            start = index + 1;
        }
    }
    return current == line ? source[start .. $] : null;
}

/// A one-based source position.
struct Position
{
    /// Line.
    long line = 1;
    /// Column in bytes.
    long column = 1;
}

/// The position of a byte offset; offsets past the end, or size_t.max, give the end.
Position positionOf(string source, size_t offset)
{
    Position position;
    foreach (index, ch; source)
    {
        if (index >= offset)
            break;
        if (ch == '\n')
        {
            ++position.line;
            position.column = 1;
        }
        else
            ++position.column;
    }
    return position;
}

/// Diagnostics collected by one command.
struct Report
{
    /// Every diagnostic in the order raised.
    Diagnostic[] items;

    /// Add one diagnostic.
    void add(Diagnostic value)
    {
        items ~= value;
    }

    /// Add an error.
    void error(string code, string message, string fix = null)
    {
        add(diagnostic(code, Severity.error, message, fix));
    }

    /// Add a warning.
    void warning(string code, string message, string fix = null)
    {
        add(diagnostic(code, Severity.warning, message, fix));
    }

    /// Append another report's diagnostics.
    void merge(const ref Report other)
    {
        items ~= other.items.dup;
    }

    /// Number of errors.
    size_t errors() const
    {
        size_t count;
        foreach (ref item; items)
            count += item.severity == "error";
        return count;
    }

    /// Number of warnings.
    size_t warnings() const
    {
        size_t count;
        foreach (ref item; items)
            count += item.severity == "warning";
        return count;
    }

    /// No errors were raised.
    bool ok() const
    {
        return errors() == 0;
    }

    /// The process exit code: the most fundamental class among the errors.
    ExitCode exitCode() const
    {
        static immutable ExitCode[] precedence = [
            ExitCode.usage, ExitCode.environment, ExitCode.dependency, ExitCode.user
        ];
        foreach (wanted; precedence)
        {
            foreach (ref item; items)
            {
                if (item.severity != "error")
                    continue;
                const info = lookup(item.code);
                if (info !is null && info.exit == wanted)
                    return wanted;
            }
        }
        return ExitCode.ok;
    }
}

/// Whether to color human output.
struct Palette
{
    /// Emit ANSI styling.
    bool enabled;
}

/// Render diagnostics for people, as in compiler output.
string renderHuman(scope const Diagnostic[] items, Palette palette)
{
    import std.conv : to;

    string text;
    foreach (ref item; items)
    {
        text ~= paint(item.severity, palette, item.severity == "error" ? Tone.error
                : item.severity == "warning" ? Tone.warning : Tone.note) ~ paint("[" ~ item.code ~ "]",
                palette, Tone.code) ~ " " ~ paint(item.title, palette, Tone.strong) ~ "\n";
        if (item.file.length)
        {
            string where = item.file;
            if (item.line > 0)
                where ~= ":" ~ item.line.to!string;
            if (item.column > 0)
                where ~= ":" ~ item.column.to!string;
            text ~= "  --> " ~ where ~ "\n";
            if (item.snippet.length)
            {
                const number = item.line.to!string;
                text ~= "  " ~ paint(number ~ " |", palette, Tone.code) ~ " " ~ item.snippet ~ "\n";
            }
        }
        if (item.message.length)
            text ~= indent("cause: ", item.message);
        if (item.fix.length)
            text ~= indent(paint("fix:", palette, Tone.fix) ~ " ", item.fix);
    }
    return text;
}

private string indent(string label, string body)
{
    import std.string : lineSplitter;

    string text;
    bool first = true;
    foreach (line; body.lineSplitter)
    {
        text ~= (first ? "  " ~ label : "       ") ~ line ~ "\n";
        first = false;
    }
    return text;
}

/// Semantic colors of human output.
enum Tone : ubyte
{
    error,
    warning,
    note,
    code,
    strong,
    fix,
    success
}

/// SGR styling of `text` when color is enabled. flint does not link flint.style: its width tables need
/// the utf8proc provider, and flint must bootstrap without native providers (ADR-022).
string paint(string text, Palette palette, Tone tone)
{
    if (!palette.enabled || text.length == 0)
        return text;
    static immutable string[] codes = [
        "\x1b[1;31m", "\x1b[1;33m", "\x1b[1;36m", "\x1b[2m", "\x1b[1m", "\x1b[1;32m", "\x1b[32m"
    ];
    return codes[tone] ~ text ~ "\x1b[0m";
}
