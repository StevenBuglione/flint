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

@("[profile.dev] debug = false opts out of debug information, and only there")
unittest
{
    Manifest manifest;
    expect(parse(header ~ "[profile.dev]\ndebug = false\n", manifest).items.length).toEqual(0);
    expect(manifest.overrideFor("dev").noDebug).toEqual(true);
    expect(manifest.overrideFor("test").noDebug).toEqual(false);
    expect(parse(header ~ "[profile.dev]\ndebug = true\n", manifest).items.length).toEqual(0);
    expect(manifest.overrideFor("dev").noDebug).toEqual(false);
    expect(codes(parse(header ~ "[profile.release]\ndebug = false\n", manifest))).toEqual([
        "FLINT-E0105"
    ]);
    expect(codes(parse(header ~ "[profile.dev]\ndebug = \"no\"\n", manifest))).toEqual([
        "FLINT-E0105"
    ]);
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

@("[native.c] configures embedded C and [native] declares native packages")
unittest
{
    Manifest manifest;
    const report = parse(header ~ "[native.c]\nsources = [\"native/**/*.c\"]\ninclude_dirs = [\"native/include\"]\n"
            ~ "standard = \"c11\"\ndefines = [\"SHOP_FAST=1\"]\n[native]\nzlib = \"1.3.1\"\n"
            ~ "openssl = { version = \"3.5.4\", linkage = \"bundled\" }\n"
            ~ "libpq = { version = \"17.6\", system = true, options = { ssl = true } }\n", manifest);
    expect(report.items.length).toEqual(0);
    expect(manifest.nativeC.sources).toEqual(["native/**/*.c"]);
    expect(manifest.nativeC.includeDirs).toEqual(["native/include"]);
    expect(manifest.nativeC.standard).toEqual("c11");
    expect(manifest.nativeC.defines).toEqual(["SHOP_FAST=1"]);
    expect(manifest.natives.length).toEqual(3);
    expect(manifest.natives[0].name).toEqual("zlib");
    expect(manifest.natives[0].version_).toEqual("1.3.1");
    expect(manifest.natives[0].linkage).toEqual("static");
    expect(manifest.natives[1].linkage).toEqual("bundled");
    expect(manifest.natives[2].system).toEqual(true);
    expect(manifest.natives[2].options).toEqual(["ssl=true"]);
}

@("[native] rejects unknown keys and linkages")
unittest
{
    Manifest manifest;
    expect(codes(parse(header ~ "[native]\nzlib = { version = \"1.3.1\", linkage = \"shared\" }\n", manifest))).toEqual(
            ["FLINT-E0105"]);
    expect(codes(parse(header ~ "[native.c]\nflags = [\"-O0\"]\n", manifest)).length).toEqual(1);
}

@("DUB packages are written dub:<name> with an exact version")
unittest
{
    Manifest manifest;
    const report = parse(header ~ "[dependencies]\n\"dub:dyaml\" = \"0.10.0\"\n[unchecked]\n\"dub:dyaml\" = \"YAML\"\n",
            manifest);
    expect(report.items.length).toEqual(0);
    expect(manifest.dependencies[0].kind == DependencyKind.dub).toEqual(true);
    expect(manifest.dependencies[0].version_).toEqual("0.10.0");
    expect(manifest.unchecked[0].name).toEqual("dub:dyaml");
    expect(codes(parse(header ~ "[dependencies]\n\"dub:dyaml\" = { path = \"../x\" }\n", manifest))).toEqual(
            ["FLINT-E0105"]);
}

@("a base package moves the module root to Spring's package, below src/ as a path")
unittest
{
    Manifest manifest;
    const report = parse(header ~ "base-package = \"com.example.restservice\"\n", manifest);
    expect(report.ok).toEqual(true);
    expect(manifest.moduleRoot()).toEqual("com.example.restservice");
    expect(manifest.rootDirectory()).toEqual("com/example/restservice");
    Manifest plain;
    expect(parse(header, plain).ok).toEqual(true);
    expect(plain.moduleRoot()).toEqual("shop");
    expect(plain.rootDirectory()).toEqual("shop");
    foreach (bad; [
        "Com.example", "com..example", "flint.shop", "com.example.class", ".com", "com-example"
    ])
    {
        Manifest rejected;
        expect(codes(parse(header ~ "base-package = \"" ~ bad ~ "\"\n", rejected))).toEqual([
            "FLINT-E0106"
        ]);
    }
}
