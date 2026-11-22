/// Source safety rules shared by the workspace structural gate and project checks (ADR-021 section 5).
///
/// The rules and their wording follow tools/gates.py, so both tools reach the same verdicts.
module flint_tool.check.rules;

import flint_tool.check.lexer : LexFailure, Token, declaredModule, hasStringMixin, importedModules,
    moduleDefault, tokenize;
import flint_tool.diagnostics.report : Report, Severity, at, diagnostic;
import flint_tool.home.policy : Home, matchesAny, startsWithModule;

@safe:

/// What the lexer learned about one source file.
struct SourceScan
{
    /// Display path used in diagnostics.
    string file;
    /// File text.
    string text;
    /// Policy tokens.
    Token[] tokens;
    /// Declared module.
    string moduleName;
    /// Module-scope default attribute, or null.
    string defaultAttribute;
    /// Contains `mixin(`.
    bool stringMixin;
    /// Imported modules.
    string[] imports;
}

/// Lex one file. A lexing failure is FLINT-E0402.
bool scanSource(string file, string text, out SourceScan scan, ref Report report)
{
    scan.file = file;
    scan.text = text;
    LexFailure failure;
    if (!tokenize(text, scan.tokens, failure) || !declaredModule(scan.tokens, scan.moduleName,
            failure) || !importedModules(scan.tokens, scan.imports, failure))
    {
        report.add(at(diagnostic("FLINT-E0402", Severity.error, failure.message,
                "start the file with `module <root>.<path>;` and avoid token strings"), file, failure.line, 0, text));
        return false;
    }
    scan.defaultAttribute = moduleDefault(scan.tokens);
    scan.stringMixin = hasStringMixin(scan.tokens);
    return true;
}

/// The module a root-relative source path must declare: `a/b/c.d` is `a.b.c`, `a/b/package.d` is `a.b`.
string expectedModule(string relative)
{
    import std.array : join, split;
    import std.path : stripExtension;

    auto parts = stripExtension(relative).split("/");
    if (parts.length && parts[$ - 1] == "package")
        parts = parts[0 .. $ - 1];
    return parts.join(".");
}

/// Module default: `@safe:`, or `@system:` in an allowlisted low-level module (FLINT-E0501).
void checkDefault(const ref SourceScan scan, bool lowLevel, ref Report report)
{
    if (scan.defaultAttribute == "safe" || (lowLevel && scan.defaultAttribute == "system"))
        return;
    report.add(at(diagnostic("FLINT-E0501", Severity.error,
            "require module-scope @safe: before declarations; raw allowlisted FFI may use @system:",
            "add `@safe:` after the module declaration and its imports"), scan.file,
            declarationLine(scan), 0, scan.text));
}

private size_t declarationLine(const ref SourceScan scan)
{
    return scan.tokens.length ? scan.tokens[0].line : 1;
}

/// String mixins only in approved generator modules (FLINT-E0506).
void checkMixin(const ref SourceScan scan, scope const(string)[] generatorPrefixes, ref Report report)
{
    if (!scan.stringMixin || matchesAny(scan.moduleName, generatorPrefixes))
        return;
    foreach (i; 1 .. scan.tokens.length)
    {
        if (scan.tokens[i - 1].value == "mixin" && scan.tokens[i].value == "(")
        {
            report.add(at(diagnostic("FLINT-E0506", Severity.error, "string mixin outside approved generator module",
                    "use the framework's UDA or template API"), scan.file, scan.tokens[i].line, 0, scan.text));
            return;
        }
    }
}

/// @trusted and @system confinement, SAFETY rationale, no scopes or blocks, bounded length.
void checkAnnotations(const ref SourceScan scan, bool lowLevel, long maxTrustedLines, ref Report report)
{
    import std.string : lineSplitter;

    string[] lines;
    foreach (line; scan.text.lineSplitter)
        lines ~= line;
    const tokens = scan.tokens;
    foreach (i, ref token; tokens)
    {
        if (i + 1 >= tokens.length || token.value != "@" || (tokens[i + 1].value != "trusted"
                && tokens[i + 1].value != "system"))
            continue;
        const line = tokens[i].line;
        if (!lowLevel)
        {
            report.add(at(diagnostic("FLINT-E0502", Severity.error,
                    "unsafe annotation outside allowlisted low-level directory",
                    "move the function into a sys/ or ffi/ module and give it a // SAFETY: rationale"),
                    scan.file, line, 0, scan.text));
            continue;
        }
        if (tokens[i + 1].value != "trusted")
            continue;
        if (i + 2 < tokens.length && (tokens[i + 2].value == ":" || tokens[i + 2].value == "{"))
            report.add(at(diagnostic("FLINT-E0504", Severity.error, "no @trusted scopes/blocks",
                    "mark individual functions @trusted"), scan.file, line, 0, scan.text));
        if (!hasRationale(lines, line))
            report.add(at(diagnostic("FLINT-E0503", Severity.error, "@trusted missing adjacent SAFETY rationale",
                    "add a `// SAFETY:` comment on one of the two lines above"), scan.file, line, 0, scan.text));
        checkTrustedBody(scan, i, maxTrustedLines, report);
    }
}

/// Whether one of the two lines above `line`, or the line itself, holds `// SAFETY:`.
private bool hasRationale(scope const(string)[] lines, size_t line)
{
    const first = line >= 3 ? line - 3 : 0;
    const last = line <= lines.length ? line : lines.length;
    foreach (candidate; lines[first < last ? first : last .. last])
    {
        if (contains(candidate, "// SAFETY:"))
            return true;
    }
    return false;
}

/// A @trusted function body (from the `@` at `index`) is balanced and at most `maxTrustedLines` long.
private void checkTrustedBody(const ref SourceScan scan, size_t index, long maxTrustedLines, ref Report report)
{
    import std.conv : to;

    const tokens = scan.tokens;
    const line = tokens[index].line;
    size_t j = index + 2;
    while (j < tokens.length && tokens[j].value != "{" && tokens[j].value != ";")
        ++j;
    if (j >= tokens.length || tokens[j].value != "{")
        return;
    size_t depth = 1;
    size_t k = j + 1;
    while (k < tokens.length && depth)
    {
        depth += tokens[k].value == "{";
        depth -= tokens[k].value == "}";
        ++k;
    }
    if (depth != 0)
    {
        report.add(at(diagnostic("FLINT-E0512", Severity.error, "unbalanced trusted body",
                "check the braces of this function"), scan.file, line, 0, scan.text));
        return;
    }
    const span = cast(long) tokens[k - 1].line - cast(long) tokens[j].line;
    if (span > maxTrustedLines)
        report.add(at(diagnostic("FLINT-E0505", Severity.error,
                "trusted function exceeds " ~ maxTrustedLines.to!string ~ " lines",
                "keep only the unsafe operation in the @trusted function"), scan.file, line, 0, scan.text));
}

private bool contains(scope const(char)[] text, scope const(char)[] part)
{
    import std.algorithm.searching : canFind;

    return text.canFind(part);
}

/// Import rules for a module of core package `packageName` (tools/gates.py check_import).
void checkWorkspaceImport(const ref Home home, string packageName, string imported, string where,
        string file, size_t line, string text, ref Report report)
{
    const meta = home.find(packageName);
    if (imported == "std" || imported == "std.algorithm" || imported == "std.range"
            || imported == "std.all" || startsWithPrefix(imported, "std.regex"))
    {
        if (!(meta.tier > 1 && !meta.betterC))
            report.add(at(diagnostic("FLINT-E0509", Severity.error, where ~ ": forbidden heavy core import " ~ imported,
                    "import the specific core.* or std.* module you need"), file, line, 0, text));
    }
    const dependency = home.owner(imported);
    if (startsWithPrefix(imported, "flint.") && dependency is null)
    {
        report.add(at(diagnostic("FLINT-E0510", Severity.error, where ~ ": unknown Flint module " ~ imported,
                "import a module a core package owns"), file, line, 0, text));
        return;
    }
    if (dependency is null || dependency.name == packageName)
        return;
    bool declared;
    foreach (name; meta.dependencies)
        declared = declared || name == dependency.name;
    if (!declared)
        report.add(at(diagnostic("FLINT-E0507", Severity.error, where ~ ": undeclared import " ~ imported,
                "declare flint:" ~ dependency.name ~ " in policy/packages.json and the package's dub.sdl"),
                file, line, 0, text));
    else if (privateBoundary(dependency.module_, imported))
        report.add(at(diagnostic("FLINT-E0508", Severity.error,
                where ~ ": cross-package private boundary import " ~ imported,
                "import the package's public modules"), file, line, 0, text));
}

/// Whether `imported` names an internal, sys or ffi module of the package rooted at `moduleRoot`.
bool privateBoundary(string moduleRoot, string imported)
{
    foreach (part; ["internal", "sys", "ffi"])
    {
        if (startsWithModule(imported, moduleRoot ~ "." ~ part))
            return true;
    }
    return false;
}

private bool startsWithPrefix(scope const(char)[] text, scope const(char)[] prefix)
{
    return text.length >= prefix.length && text[0 .. prefix.length] == prefix;
}

/// Line of the first `import` token naming `imported`, for locating import diagnostics.
size_t importLine(const ref SourceScan scan, string imported)
{
    foreach (i, ref token; scan.tokens)
    {
        if (token.value != "import")
            continue;
        string joined;
        foreach (ref next; scan.tokens[i + 1 .. $])
        {
            if (next.value == ";")
                break;
            joined ~= next.value;
        }
        if (contains(joined, imported))
            return token.line;
    }
    return 1;
}
