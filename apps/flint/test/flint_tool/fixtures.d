/// Shared fixtures for flint's unit tests.
module flint_tool.fixtures;

import flint_tool.home.policy : CorePackage, Home;

@safe:

/// A small in-memory Flint installation: arena, conc, log and cli, platform 1.0.
Home fixtureHome()
{
    Home home;
    home.root = "/flint";
    home.packages = [
        CorePackage("arena", 0, "flint.arena", null, true),
        CorePackage("conc", 0, "flint.conc", ["arena"], false),
        CorePackage("log", 1, "flint.log", ["arena", "conc"], false),
        CorePackage("cli", 4, "flint.cli", ["arena"], false),
        CorePackage("test", 1, "flint.test", null, false)
    ];
    home.safety.unsafePrefixes["arena"] = ["flint.arena.sys"];
    home.safety.generatorPrefixes = ["flint.cli.internal"];
    home.safety.maxTrustedLines = 60;
    home.versions = [
        "dmd": "2.114.0",
        "ldc": "1.43.0",
        "dub": "1.43.0",
        "dfmt": "0.15.2",
        "dscanner": "0.15.2"
    ];
    home.platform.flint = "1.0";
    home.platform.release = "0.7.0";
    home.profiles.dev.compiler = "dmd";
    home.profiles.dev.compilers = ["dmd"];
    home.profiles.test.compiler = "dmd";
    home.profiles.test.compilers = ["dmd", "ldc2"];
    home.digests = [
        "policy/toolchains.json": "t",
        "policy/profiles.toml": "p",
        "policy/safety-policy.json": "s"
    ];
    return home;
}

/// Codes of the diagnostics in a report, in order.
string[] codes(T)(auto ref const T report)
{
    string[] found;
    foreach (ref item; report.items)
        found ~= item.code;
    return found;
}
