module flint.config.config_behavior_test;

import flint.arena : Status;
import flint.config : ConfigOptions, ConfigurationProperties, Default, Env, Required, Secret, load, validateConfig;
import flint.validate : Min, Valid;
import std.algorithm.searching : canFind;
import std.file : mkdir, remove, rmdirRecurse, tempDir, write;
import std.path : buildPath;
import std.process : environment;
import std.uuid : randomUUID;

@safe:

private string scratch()
{
    const path = buildPath(tempDir(), "flint-config-" ~ randomUUID().toString());
    mkdir(path);
    return path;
}

private ConfigOptions configFor(string directory)
{
    ConfigOptions options;
    options.directory = directory;
    options.envPrefix = "FLINT_CONFIG_FIXTURE_";
    return options;
}

private struct Credentials
{
    @Secret @Min(5) uint token = 10;
}

@ConfigurationProperties("server")
private struct Settings
{
    @Default("13") ushort port = 12;
    @Required bool tls;
    @Env("FLINT_CONFIG_FIXTURE_GREETING") string greeting = "initial";
    string[] labels;
    double rate = 1;
    @Valid Credentials credentials;
}

@("D initializer, default, file, profile, dotenv, process and CLI in precedence order")
unittest
{
    const directory = scratch();
    scope (exit)
        rmdirRecurse(directory);
    auto options = configFor(directory);
    const previous = environment.toAA();
    scope (exit)
    {
        foreach (key; ["FLINT_PROFILE", "FLINT_CONFIG_FIXTURE_SERVER__PORT"])
        {
            if (auto value = key in previous)
                environment[key] = *value;
            else
                environment.remove(key);
        }
    }
    environment.remove("FLINT_PROFILE");
    environment.remove("FLINT_CONFIG_FIXTURE_SERVER__PORT");

    options.arguments = ["--set=server.tls=false"];
    auto resolved = load!Settings(options);
    assert(resolved.ok && resolved.value.port == 13 && resolved.value.greeting == "initial");
    assert(!resolved.value.tls);

    const base = buildPath(directory, "application.toml");
    write(base, "\xEF\xBB\xBF[server]\nport=0\ntls=false\nlabels=[\"first\", \"second\"]\n");
    options.arguments = null;
    resolved = load!Settings(options);
    assert(resolved.ok && resolved.value.port == 0 && resolved.value.labels == ["first", "second"]);

    write(buildPath(directory, "application-dev.toml"), "[server]\nport=2\n");
    write(buildPath(directory, "application-stage.toml"), "[server]\nport=3\n");
    resolved = load!Settings(options);
    assert(resolved.ok && resolved.value.port == 2 && !resolved.value.tls);
    environment["FLINT_PROFILE"] = "stage";
    resolved = load!Settings(options);
    assert(resolved.ok && resolved.value.port == 3);

    write(buildPath(directory, ".env"),
            "FLINT_CONFIG_FIXTURE_SERVER__PORT=004\n" ~ "FLINT_CONFIG_FIXTURE_GREETING=\"a\\tb\"\n");
    resolved = load!Settings(options);
    assert(resolved.ok && resolved.value.port == 4 && resolved.value.greeting == "a\tb");
    environment["FLINT_CONFIG_FIXTURE_SERVER__PORT"] = "5";
    resolved = load!Settings(options);
    assert(resolved.ok && resolved.value.port == 5);

    options.arguments = [
        "--flint.profile=dev", "--set=server.port=6", "--set=server.greeting=hello=there",
        "--set=server.labels=a\\,b,c\\\\d"
    ];
    resolved = load!Settings(options);
    assert(resolved.ok && resolved.value.port == 6 && resolved.value.greeting == "hello=there");
    assert(resolved.value.labels == ["a,b", "c\\d"]);
}

@("malformed, duplicate and unknown inputs produce deterministic source locations")
unittest
{
    const directory = scratch();
    scope (exit)
        rmdirRecurse(directory);
    auto options = configFor(directory);
    options.arguments = ["--flint.profile=../../etc"];
    auto resolved = load!Settings(options);
    assert(resolved.error.code == Status.invalidArgument);
    assert(resolved.error.message.canFind("invalid profile"));

    options.arguments = ["--flint.profile=dev"];
    const json = buildPath(directory, "application.json");
    const toml = buildPath(directory, "application.toml");
    write(json, `{"server":{"tls":false}}`);
    write(toml, "[server]\ntls=false\n");
    assert(load!Settings(options).error.code == Status.conflict);
    remove(toml);

    write(json, "{\n\"server\":{\"tls\":false,\"port\":1,\"port\":2}}\n");
    resolved = load!Settings(options);
    assert(resolved.error.code == Status.conflict);
    assert(resolved.error.message.canFind("server.port in application.json at 2:"));

    write(json, `{"server":{"tls":false,"zeta":1,"alpha":2}}`);
    resolved = load!Settings(options);
    assert(resolved.error.message.canFind("server.alpha"));
    options.rejectUnknownKeys = false;
    assert(load!Settings(options).ok);

    options.arguments ~= ["--set=server.port=1", "--set=server.port=2"];
    assert(load!Settings(options).error.code == Status.conflict);
    options.arguments = ["--flint.profile=dev"];
    write(buildPath(directory, ".env"), "FLINT_CONFIG_FIXTURE_GREETING=x\nFLINT_CONFIG_FIXTURE_GREETING=y\n");
    assert(load!Settings(options).error.code == Status.conflict);
}

@("failures redact all values, including nested secrets, and reject incorrect scalar types")
unittest
{
    const directory = scratch();
    scope (exit)
        rmdirRecurse(directory);
    auto options = configFor(directory);
    options.arguments = [
        "--flint.profile=dev", "--set=server.tls=false", "--set=server.credentials.token=redact-me"
    ];
    auto resolved = load!Settings(options);
    assert(!resolved.ok && resolved.error.message.canFind("server.credentials.token"));
    assert(!resolved.error.message.canFind("redact-me"));
    assert(resolved.error.message.canFind("command line"));

    options.arguments = [
        "--flint.profile=dev", "--set=server.tls=false", "--set=server.credentials.token=3"
    ];
    resolved = load!Settings(options);
    assert(resolved.error.message.canFind("server.credentials.token in command line"));

    options.arguments = ["--flint.profile=dev", "--set=server.tls=false", "--set=server.port=-1"];
    assert(load!Settings(options).error.code == Status.invalidArgument);
    options.arguments[$ - 1] = "--set=server.port=65536";
    assert(load!Settings(options).error.code == Status.invalidArgument);
    options.arguments[1] = "--set=server.tls=0";
    options.arguments.length = 2;
    assert(load!Settings(options).error.code == Status.invalidArgument);
    options.arguments = ["--flint.profile=dev", "--set=server.tls=false", "--set=server.rate=NaN"];
    assert(load!Settings(options).error.code == Status.invalidArgument);
    options.arguments[$ - 1] = "--set=server.rate=Infinity";
    assert(load!Settings(options).error.code == Status.invalidArgument);
    options.arguments[$ - 1] = "--set=server.rate=1.25e-1";
    resolved = load!Settings(options);
    assert(resolved.ok && resolved.value.rate == 0.125);
    options.arguments = ["--flint.profile=dev"];
    assert(load!Settings(options).error.code == Status.notFound);

    Settings typed;
    assert(validateConfig(typed).code == Status.ok);
    typed.credentials.token = 0;
    assert(validateConfig(typed).code == Status.invalidArgument);
}

private struct Nested(size_t levels)
{
    static if (levels > 0)
        Nested!(levels - 1) child;
    else
        int leaf;
}

@("the configuration descriptor rejects excessive depth")
unittest
{
    const directory = scratch();
    scope (exit)
        rmdirRecurse(directory);
    auto options = configFor(directory);
    options.arguments = ["--flint.profile=dev"];
    assert(load!(Nested!7)(options).ok);
    assert(load!(Nested!17)(options).error.code == Status.resourceExhausted);
}
