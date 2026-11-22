module flint_tool.diagnostics.catalog_test;

import flint_tool.diagnostics.catalog : ExitCode, catalog, lookup;
import flint_tool.diagnostics.report : Report, Severity, at, diagnostic, positionOf, renderHuman, sourceLine, Palette;
import flint.test : expect;

@safe:

@("codes are unique, well formed, ordered and fully documented")
unittest
{
    import std.regex : matchFirst, regex;

    string previous;
    foreach (ref entry; catalog)
    {
        expect(matchFirst(entry.code, regex(`^FLINT-E[0-9]{4}$`)).empty).toEqual(false);
        expect(entry.code > previous).toEqual(true);
        expect(entry.title.length > 0 && entry.explanation.length > 0 && entry.example.length > 0).toEqual(true);
        previous = entry.code;
    }
}

@("every code flint's sources raise is in the catalogue")
unittest
{
    import std.file : dirEntries, readText, SpanMode;
    import std.regex : matchAll, regex;

    size_t seen;
    foreach (entry; dirEntries("src", "*.d", SpanMode.depth))
    {
        foreach (match; matchAll(readText(entry.name), regex(`"(FLINT-E[0-9]{4})"`)))
        {
            ++seen;
            expect(lookup(match[1]) !is null).toEqual(true);
        }
    }
    expect(seen > 50).toEqual(true);
}

@("lookup accepts any case and the bare number")
unittest
{
    expect(lookup("flint-e0401").code).toEqual("FLINT-E0401");
    expect(lookup("E0401").code).toEqual("FLINT-E0401");
    expect(lookup("E9999") is null).toEqual(true);
}

@("the exit code is the most fundamental error class; warnings never fail")
unittest
{
    Report report;
    report.warning("FLINT-E0804", "unverified");
    expect(report.exitCode() == ExitCode.ok).toEqual(true);
    report.error("FLINT-E0701", "build");
    expect(report.exitCode() == ExitCode.user).toEqual(true);
    report.error("FLINT-E0202", "lock");
    expect(report.exitCode() == ExitCode.dependency).toEqual(true);
    report.error("FLINT-E0802", "toolchain");
    expect(report.exitCode() == ExitCode.environment).toEqual(true);
    report.error("FLINT-E0001", "usage");
    expect(report.exitCode() == ExitCode.usage).toEqual(true);
    expect(report.errors()).toEqual(4);
    expect(report.warnings()).toEqual(1);
}

@("human rendering shows the code, location, snippet, cause and fix")
unittest
{
    const source = "module a;\nimport flint.log;\n";
    const item = at(diagnostic("FLINT-E0507", Severity.error, "imports flint.log", "declare it"),
            "src/a.d", 2, 1, source);
    expect(item.snippet).toEqual("import flint.log;");
    expect(renderHuman([item], Palette(false))).toEqual("error[FLINT-E0507] import of an undeclared dependency\n"
            ~ "  --> src/a.d:2:1\n  2 | import flint.log;\n  cause: imports flint.log\n  fix: declare it\n");
    expect(sourceLine("a\nb", 2)).toEqual("b");
    expect(positionOf("ab\ncd", 4).line).toEqual(2);
    expect(positionOf("ab\ncd", 4).column).toEqual(2);
    expect(positionOf("ab", size_t.max).column).toEqual(3);
}
