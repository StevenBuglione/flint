module flint_tool.check.registration_test;

import flint_tool.check.registration : RegistrationProblem, packageDirectories, registrationProblems;
import flint.test : expect;

@safe:

private string tree(string[string] files)
{
    import std.file : mkdirRecurse, tempDir, write;
    import std.path : buildPath, dirName;
    import std.uuid : randomUUID;

    const root = buildPath(tempDir(), "flint-registration-" ~ randomUUID().toString());
    foreach (path, text; files)
    {
        mkdirRecurse(dirName(buildPath(root, path)));
        write(buildPath(root, path), text);
    }
    return root;
}

private string[] messages(const RegistrationProblem[] problems)
{
    string[] found;
    foreach (ref problem; problems)
        found ~= problem.message ~ " -> " ~ problem.fix;
    return found;
}

@("every DUB package under framework/ and boot/ is registered or on the shrinking allowlist")
unittest
{
    import std.file : rmdirRecurse;

    const root = tree([
        "policy/framework.json": `{"modules":{"core":{"directory":"framework/core"}}}`,
        "policy/boot.json": `{"libraries":{"boot":{"directory":"boot/boot"}},"starters":{}}`,
        "policy/unregistered-packages.json": `{"paths":{"framework/web":{"since":"2026-11-23"},
            "framework/core":{"since":"2026-11-23"},"boot/gone":{"since":"2026-11-23"},
            "boot/later":{"since":"2026-12-01"}}}`,
        "framework/core/dub.sdl": "",
        "framework/core/tests/fixture/dub.sdl": "",
        "framework/web/dub.sdl": "",
        "framework/new/dub.json": "{}",
        "boot/boot/dub.sdl": "",
        "boot/later/dub.sdl": "",
        "boot/.hidden/dub.sdl": "",
        "boot/starter/flint-boot-starter/dub.sdl": ""
    ]);
    scope (exit)
        rmdirRecurse(root);
    expect(packageDirectories(root, "framework")).toEqual([
        "framework/core", "framework/new", "framework/web"
    ]);
    expect(messages(registrationProblems(root))).toEqual(
            [
        "framework/new is a DUB package that no policy lists -> add it to policy/framework.json",
        "boot/starter/flint-boot-starter is a DUB package that no policy lists -> add it to policy/boot.json",
        "boot/gone is no longer a package -> remove it from policy/unregistered-packages.json",
        "boot/later: policy/unregistered-packages.json only shrinks -> register the package in its policy instead",
        "framework/core is registered now -> remove it from policy/unregistered-packages.json"
    ]);
}
