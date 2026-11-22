module flint_tool.project.scaffold_test;

import flint_tool.check.rules : SourceScan, expectedModule, scanSource;
import flint_tool.diagnostics.report : Report;
import flint_tool.fixtures : fixtureHome;
import flint_tool.project.manifest : Manifest, parseManifestText;
import flint_tool.project.scaffold : ScaffoldFile, scaffold, scaffoldDependencies;
import flint.test : expect;

@safe:

@("a new executable has the canonical layout, a valid manifest and modules matching their paths")
unittest
{
    const home = fixtureHome();
    const files = scaffold(home, "order-service", "executable", ["cli"]);
    string[] paths;
    foreach (ref file; files)
        paths ~= file.path;
    expect(paths).toEqual([
        "flint.toml", ".gitignore", "config/application.toml", "config/application-dev.toml",
        "config/application-prod.toml", "src/order_service/app.d",
        "src/order_service/greeting.d", "test/order_service/greeting_test.d"
    ]);
    Manifest manifest;
    Report report;
    expect(parseManifestText(files[0].content, home, manifest, report)).toEqual(true);
    expect(manifest.name).toEqual("order-service");
    foreach (ref file; files[5 .. $])
    {
        SourceScan scan;
        assert(scanSource(file.path, file.content, scan, report));
        const below = file.path[file.path[0] == 's' ? 4 : 5 .. $];
        expect(scan.moduleName).toEqual(expectedModule(below));
        expect(scan.defaultAttribute).toEqual("safe");
    }
}

@("starters add their core packages; libraries start without any")
unittest
{
    expect(scaffoldDependencies("executable", null)).toEqual(["arena", "cli", "config", "log"]);
    expect(scaffoldDependencies("library", null).length).toEqual(0);
    expect(scaffoldDependencies("executable", ["data"])).toEqual([
        "arena", "cli", "config", "data", "log", "migrate", "sql"
    ]);
    const home = fixtureHome();
    expect(scaffold(home, "model", "library", null)[5].path).toEqual("src/model/package.d");
    expect(scaffold(home, "x", "executable", null) == scaffold(home, "x", "executable", null)).toEqual(true);
}
