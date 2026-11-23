module flint_tool.home.layout_test;

import flint_tool.fixtures : fixtureHome;
import flint.test : expect;

@safe:

private enum string[2][] rules = [
    ["packages/engine-", "engine/"], ["framework/", "flint-"], ["boot/core", "core"],
    ["boot/boot", "legacy/flint-boot"], ["boot/actuator", "legacy/flint-boot-actuator"],
    ["boot/", "module/flint-boot-"], ["starters/starter", "legacy/flint-boot-starter"],
    ["starters/", "legacy/flint-boot-starter-"]
];

@("an extracted repo places engines under engine/, modules as flint-<module> and Boot in spring-boot's layout")
unittest
{
    auto home = fixtureHome();
    home.layout = rules.dup;
    expect(home.repoLayout("framework", "packages/engine-web")).toEqual("engine/web");
    expect(home.repoLayout("framework", "packages/engine-web/source")).toEqual("engine/web/source");
    expect(home.repoLayout("framework", "framework/core")).toEqual("flint-core");
    expect(home.repoLayout("boot", "boot/core/flint-boot")).toEqual("core/flint-boot");
    expect(home.repoLayout("boot", "boot/boot")).toEqual("legacy/flint-boot");
    expect(home.repoLayout("boot", "boot/autoconfigure-web")).toEqual("module/flint-boot-autoconfigure-web");
    expect(home.repoLayout("boot", "starters/starter")).toEqual("legacy/flint-boot-starter");
    expect(home.repoLayout("boot", "starters/web")).toEqual("legacy/flint-boot-starter-web");
    expect(home.repoLayout("ai", "apps/flint-mcp")).toEqual("apps/flint-mcp");
    expect(home.repoLayout("flint", "packages/arena")).toEqual("packages/arena");
    expect(home.repoLayout("framework", "examples/framework/golden-tui")).toEqual("examples/golden-tui");
    expect(home.repoLayout("framework", "native/framework")).toEqual("native");
    expect(home.repoLayout("boot", "examples/framework/golden-tui")).toEqual("examples/framework/golden-tui");
}

@("a path built with the host's separator finds its layout rule, as buildPath gives `packages\\engine-web` on Windows")
unittest
{
    import std.path : buildPath;

    auto home = fixtureHome();
    home.layout = rules.dup;
    expect(home.repoLayout("framework", buildPath("packages", "engine-web"))).toEqual("engine/web");
    expect(home.repoLayout("boot", buildPath("boot", "core", "flint-boot"))).toEqual("core/flint-boot");
}

@("a package resolves to the monorepo path when the checkout has it, else to its extracted place")
unittest
{
    import std.file : mkdirRecurse, rmdirRecurse, tempDir;
    import std.path : buildPath;
    import std.process : thisProcessID;
    import std.conv : to;

    const root = buildPath(tempDir, "flint-layout-" ~ thisProcessID.to!string);
    scope (exit)
        rmdirRecurse(root);
    auto home = fixtureHome();
    home.layout = rules.dup;
    home.workspaceCheckouts["framework"] = buildPath(root, "framework");
    home.workspaceCheckouts["boot"] = buildPath(root, "boot");
    mkdirRecurse(buildPath(root, "framework", "engine", "web"));
    mkdirRecurse(buildPath(root, "boot", "boot", "boot"));
    expect(home.packagePath("boot", "boot/actuator")).toEqual(buildPath(root, "boot", "legacy", "flint-boot-actuator"));
    expect(home.packagePath("framework", "packages/engine-web")).toEqual(buildPath(root, "framework", "engine", "web"));
    expect(home.packagePath("boot", "boot/boot")).toEqual(buildPath(root, "boot", "boot", "boot"));
}

@("a Spring-layer module of policy/framework.json owns its module roots and resolves by name")
unittest
{
    import flint_tool.home.policy : CorePackage;

    auto home = fixtureHome();
    CorePackage tx;
    tx.name = "tx";
    tx.module_ = "flint.dao";
    tx.also = ["flint.transaction"];
    tx.directory = "framework/tx";
    tx.repo = "framework";
    tx.framework = true;
    home.frameworkModules ~= tx;
    expect(home.findFramework("tx") !is null).toEqual(true);
    expect(home.owner("flint.transaction.annotation").name).toEqual("tx");
    expect(home.owner("flint.dao").name).toEqual("tx");
    expect(home.owner("flint.daos") is null).toEqual(true);
    expect(home.owner("flint.arena").name).toEqual("arena");
    CorePackage web, webmvc;
    web.name = "web";
    web.module_ = "flint.web";
    webmvc.name = "webmvc";
    webmvc.module_ = "flint.web.servlet";
    home.frameworkModules ~= [web, webmvc];
    expect(home.owner("flint.web.servlet.mvc").name).toEqual("webmvc");
    expect(home.owner("flint.web.bind").name).toEqual("web");
}
