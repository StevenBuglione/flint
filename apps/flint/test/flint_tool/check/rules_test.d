module flint_tool.check.rules_test;

import flint_tool.check.rules : SourceScan, checkAnnotations, checkDefault, checkMixin,
    checkWorkspaceImport, expectedModule, scanSource;
import flint_tool.diagnostics.report : Report;
import flint_tool.fixtures : codes, fixtureHome;
import flint.test : expect;

@safe:

private string[] annotationCodes(string source, bool lowLevel, long maxLines = 60)
{
    Report report;
    SourceScan scan;
    assert(scanSource("x.d", source, scan, report));
    checkAnnotations(scan, lowLevel, maxLines, report);
    return codes(report);
}

@("a @trusted function needs a SAFETY rationale on one of the two lines above")
unittest
{
    const good = "module m.sys.a;\n@safe:\n// SAFETY: bounds checked above.\n\nvoid f() @trusted nothrow { }\n";
    expect(annotationCodes(good, true).length).toEqual(0);
    const far = "module m.sys.a;\n@safe:\n// SAFETY: too far away.\n\n\nvoid f() @trusted nothrow { }\n";
    expect(annotationCodes(far, true)).toEqual(["FLINT-E0503"]);
}

@("unsafe annotations outside low-level modules, scopes and blocks are rejected")
unittest
{
    expect(annotationCodes("module m.a;\n@safe:\n// SAFETY: x\nvoid f() @trusted nothrow { }\n", false)).toEqual(
            ["FLINT-E0502"]);
    expect(annotationCodes("module m.a;\n@safe:\nvoid f() @system { }\n", false)).toEqual([
        "FLINT-E0502"
    ]);
    expect(annotationCodes("module m.sys.a;\n// SAFETY: x\n@trusted:\nvoid f() {}\n", true)).toEqual([
        "FLINT-E0504"
    ]);
    expect(annotationCodes("module m.sys.a;\n@safe:\n// SAFETY: x\nvoid f() @trusted\n{\n}\n", true)).toEqual(
            ["FLINT-E0504"]);
}

@("a @trusted body longer than the policy limit is rejected")
unittest
{
    string body;
    foreach (_; 0 .. 5)
        body ~= "    int x;\n";
    const source = "module m.sys.a;\n@safe:\n// SAFETY: x\nvoid f() @trusted nothrow\n{\n" ~ body ~ "}\n";
    expect(annotationCodes(source, true, 6).length).toEqual(0);
    expect(annotationCodes(source, true, 5)).toEqual(["FLINT-E0505"]);
}

@("module defaults: @safe everywhere, @system only in low-level modules")
unittest
{
    foreach (index, source; [
        "module m.a;\nimport std.stdio;\n@safe:\n", "module m.a;\n@system:\n",
        "module m.a;\nvoid f();\n@safe:\n"
    ])
    {
        Report report;
        SourceScan scan;
        assert(scanSource("x.d", source, scan, report));
        checkDefault(scan, false, report);
        expect(report.ok).toEqual(index == 0);
    }
    Report report;
    SourceScan scan;
    assert(scanSource("x.d", "module m.sys.a;\n@system:\n", scan, report));
    checkDefault(scan, true, report);
    expect(report.ok).toEqual(true);
}

@("string mixins need an approved generator prefix")
unittest
{
    Report report;
    SourceScan scan;
    assert(scanSource("x.d", "module flint.cli.internal.gen;\n@safe:\nmixin(\"int x;\");\n", scan, report));
    checkMixin(scan, ["flint.cli.internal"], report);
    expect(report.ok).toEqual(true);
    checkMixin(scan, [], report);
    expect(codes(report)).toEqual(["FLINT-E0506"]);
}

@("workspace imports: declared, public, known and light in core tiers")
unittest
{
    const home = fixtureHome();
    string[] codesFor(string packageName, string imported)
    {
        Report report;
        checkWorkspaceImport(home, packageName, imported, "x.d", "x.d", 1, null, report);
        return codes(report);
    }

    expect(codesFor("log", "flint.conc").length).toEqual(0);
    expect(codesFor("log", "flint.cli")).toEqual(["FLINT-E0507"]);
    expect(codesFor("log", "flint.arena.sys.pool")).toEqual(["FLINT-E0508"]);
    expect(codesFor("log", "flint.nothing")).toEqual(["FLINT-E0510"]);
    expect(codesFor("log", "std.algorithm")).toEqual(["FLINT-E0509"]);
    expect(codesFor("cli", "std.algorithm").length).toEqual(0);
    expect(codesFor("arena", "std.regex.internal")).toEqual(["FLINT-E0509"]);
}

@("expected module names follow file paths, with package.d naming its directory")
unittest
{
    expect(expectedModule("shop/order/service.d")).toEqual("shop.order.service");
    expect(expectedModule("shop/order/package.d")).toEqual("shop.order");
}
