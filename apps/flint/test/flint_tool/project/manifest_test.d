module flint_tool.project.manifest_test;

import flint_tool.diagnostics.report : Report;
import flint_tool.fixtures : codes, fixtureHome;
import flint_tool.project.manifest : DependencyKind, Manifest, closest, moduleRootOf,
    parseManifestText, platformVersion, reservedRoot, semanticVersion, validName;
import flint.test : expect;

@safe:

private enum header = "[project]\nname = \"shop\"\nversion = \"0.1.0\"\nflint = \"1.0\"\n";

private Report parse(string text, out Manifest manifest)
{
    const home = fixtureHome();
    Report report;
    manifest.root = "/projects/shop";
    parseManifestText(text, home, manifest, report);
    return report;
}

@("a complete manifest parses every section")
unittest
{
    Manifest manifest;
    const report = parse(header ~ "type = \"executable\"\ndescription = \"Shop\"\n[build]\nexecutable = \"shopd\"\n"
            ~ "[starters]\nweb = {}\n[dependencies]\n\"flint:log\" = {}\nmodel = { path = \"../model\" }\n"
            ~ "[test-dependencies]\n\"flint:test\" = {}\n[profile.release]\ndflags = [\"-mcpu=native\"]\n"
            ~ "[targets]\ndefault = [\"linux-x86_64-glibc\"]\n"
            ~ "[[waivers]]\nrule = \"FLINT-E0502\"\nfile = \"src/shop/raw.d\"\nreason = \"vendored\"\n", manifest);
    expect(report.items.length).toEqual(0);
    expect(manifest.name).toEqual("shop");
    expect(manifest.artifactName()).toEqual("shopd");
    expect(manifest.starters).toEqual(["web"]);
    expect(manifest.dependencies.length).toEqual(2);
    expect(manifest.dependencies[0].kind == DependencyKind.core).toEqual(true);
    expect(manifest.dependencies[1].path).toEqual("../model");
    expect(manifest.testDependencies[0].name).toEqual("flint:test");
    expect(manifest.overrideFor("release").dflags).toEqual(["-mcpu=native"]);
    expect(manifest.overrideFor("dev").dflags.length).toEqual(0);
    expect(manifest.waivers[0].rule).toEqual("FLINT-E0502");
}

@("empty section tables are valid and declare nothing")
unittest
{
    Manifest manifest;
    const report = parse(header ~ "[dependencies]\n\n[test-dependencies]\n[build]\n", manifest);
    expect(report.items.length).toEqual(0);
    expect(manifest.dependencies.length).toEqual(0);
}

@("repository-path dependencies take a release version")
unittest
{
    Manifest manifest;
    auto report = parse(header ~ "[dependencies]\n\"github.com/acme/money\" = \"v1.2.0\"\n", manifest);
    expect(report.items.length).toEqual(0);
    expect(manifest.dependencies[0].version_).toEqual("1.2.0");
    expect(codes(parse(header ~ "[dependencies]\n\"github.com/acme/money\" = \"1.2\"\n", manifest))).toEqual(
            ["FLINT-E0105"]);
    expect(codes(parse(header ~ "[dependencies]\n\"github.com/acme/money\" = \"2.0.0-rc.1\"\n", manifest))).toEqual(
            ["FLINT-E0105"]);
    expect(codes(parse(header ~ "[dependencies]\nmoney = \"1.2.0\"\n", manifest))).toEqual([
        "FLINT-E0303"
    ]);
}

@("unknown keys fail with a did-you-mean suggestion and a location")
unittest
{
    Manifest manifest;
    const report = parse("[project]\nname = \"shop\"\nverison = \"0.1.0\"\nflint = \"1.0\"\n", manifest);
    expect(codes(report)).toEqual(["FLINT-E0103", "FLINT-E0104"]);
    expect(report.items[0].fix).toEqual("did you mean `version`?");
    expect(report.items[0].line).toEqual(3);
    expect(report.items[0].snippet).toEqual("verison = \"0.1.0\"");
}

@("invalid TOML, names, versions and the platform are each diagnosed")
unittest
{
    Manifest manifest;
    expect(codes(parse("[project\n", manifest))).toEqual(["FLINT-E0102"]);
    expect(codes(parse("[project]\nname = \"Shop\"\nversion = \"0.1.0\"\nflint = \"1.0\"\n", manifest))).toEqual(
            ["FLINT-E0106", "FLINT-E0104"]);
    expect(codes(parse("[project]\nname = \"flint\"\nversion = \"1\"\nflint = \"1.0\"\n", manifest))).toEqual(
            ["FLINT-E0405", "FLINT-E0105", "FLINT-E0104", "FLINT-E0104"]);
    expect(codes(parse("[project]\nname = \"shop\"\nversion = \"0.1.0\"\nflint = \"2.0\"\n", manifest))).toEqual(
            ["FLINT-E0107"]);
}

@("dependency forms: core takes {}, versions wait for Milestone 8, paths need a path")
unittest
{
    Manifest manifest;
    expect(codes(parse(header ~ "[dependencies]\n\"flint:log\" = \"1.0\"\n", manifest))).toEqual([
        "FLINT-E0305"
    ]);
    expect(codes(parse(header ~ "[dependencies]\nstripe = \"1.4.2\"\n", manifest))).toEqual([
        "FLINT-E0303"
    ]);
    expect(codes(parse(header ~ "[dependencies]\nmodel = {}\n", manifest))).toEqual(["FLINT-E0302"]);
    expect(codes(parse(header ~ "[dependencies]\nmodel = { url = \"x\" }\n", manifest))).toEqual([
        "FLINT-E0103"
    ]);
    expect(codes(parse(header ~ "[dependencies]\n\"flint:log\" = { path = \"x\" }\n", manifest))).toEqual(
            ["FLINT-E0305"]);
}

@("profiles, targets and waivers are validated")
unittest
{
    Manifest manifest;
    const profile = parse(header ~ "[profile.relase]\ndflags = [\"-O\"]\n", manifest);
    expect(codes(profile)).toEqual(["FLINT-E0108"]);
    expect(profile.items[0].fix).toEqual("did you mean `release`?");
    expect(codes(parse(header ~ "[profile.dev]\ndflags = \"-O\"\n", manifest))).toEqual([
        "FLINT-E0105"
    ]);
    expect(codes(parse(header ~ "[targets]\ndefault = [\"macos-arm64\"]\n", manifest))).toEqual([
        "FLINT-E0110"
    ]);
    expect(codes(parse(header ~ "[[waivers]]\nrule = \"FLINT-E0502\"\nfile = \"a.d\"\n", manifest))).toEqual(
            ["FLINT-E0109"]);
    expect(codes(parse(header ~ "[[waivers]]\nrule = \"FLINT-E9999\"\nfile = \"a.d\"\nreason = \"r\"\n", manifest)))
        .toEqual(["FLINT-E0109"]);
}

@("names, roots and versions")
unittest
{
    expect(validName("order-service")).toEqual(true);
    expect(validName("order--service") || validName("-x") || validName("x-") || validName("9x")).toEqual(false);
    expect(moduleRootOf("order-service")).toEqual("order_service");
    expect(reservedRoot("flint") && reservedRoot("module") && !reservedRoot("shop")).toEqual(true);
    expect(semanticVersion("1.2.3-rc.1+build.5") && !semanticVersion("01.2.3")).toEqual(true);
    expect(platformVersion("1.0") && !platformVersion("1.0.0")).toEqual(true);
    expect(closest("dependecies", ["dependencies", "project"])).toEqual("dependencies");
    expect(closest("zzz", ["dependencies"]) is null).toEqual(true);
}
