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
    @Secret
    @Min(5)
    uint token = 10;
}

@ConfigurationProperties("server")
private struct Settings
{
    @Default("13")
    ushort port = 12;
    @Required
    bool tls;
    @Env("FLINT_CONFIG_FIXTURE_GREETING")
    string greeting = "initial";
    string[] labels;
    double rate = 1;
    @Valid
    Credentials credentials;
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

@("text overrides round decimal floats exactly like configuration files")
unittest
{
    const directory = scratch();
    scope (exit)
        rmdirRecurse(directory);
    auto options = configFor(directory);
    // Just above the midpoint between 1 and its successor: correct rounding selects the successor.
    enum spelling = "1.0000000000000001110223024625156540423631668090820312500001";
    write(buildPath(directory, "application.toml"), "[server]\ntls=false\nrate=" ~ spelling ~ "\n");
    options.arguments = ["--flint.profile=dev"];
    const fromFile = load!Settings(options);
    assert(fromFile.ok && fromFile.value.rate == 1.0 + double.epsilon);
    options.arguments = ["--flint.profile=dev", "--set=server.rate=+" ~ spelling];
    const fromText = load!Settings(options);
    assert(fromText.ok && fromText.value.rate == fromFile.value.rate);
    options.arguments = ["--flint.profile=dev", "--set=server.rate=0001e-400"];
    const underflow = load!Settings(options);
    assert(underflow.ok && underflow.value.rate == 0);
    options.arguments = ["--flint.profile=dev", "--set=server.rate=1e400"];
    assert(load!Settings(options).error.code == Status.invalidArgument);
}

@ConfigurationProperties("server")
private struct ServerProperties
{
    ushort port;
    string host = "localhost";
}

@ConfigurationProperties("database")
private struct DatabaseProperties
{
    string url;
    @Secret
    string password;
    uint pool = 4;
}

@ConfigurationProperties("server")
private struct ServerTlsProperties
{
    bool tls;
}

@("several configuration types bind from one TOML file and one .env")
unittest
{
    const directory = scratch();
    scope (exit)
        rmdirRecurse(directory);
    auto options = configFor(directory);
    options.arguments = ["--flint.profile=dev", "--set=database.password=hunter2"];
    write(buildPath(directory, "application.toml"),
            "[server]\nport=8080\ntls=true\n[database]\nurl=\"postgres://db/app\"\n");
    write(buildPath(directory, ".env"),
            "FLINT_CONFIG_FIXTURE_DATABASE__POOL=9\nFLINT_CONFIG_FIXTURE_SERVER__HOST=edge\n");

    // A single-type load binds only its own prefix, so the other types' keys stay unknown to it.
    const alone = load!ServerProperties(options).error.message;
    assert(alone == "configuration key FLINT_CONFIG_FIXTURE_DATABASE__POOL in .env at 1:1 is unknown");

    ServerProperties server;
    DatabaseProperties database;
    ServerTlsProperties tls;
    const failure = load(options, server, database, tls);
    assert(failure.code == Status.ok, failure.message);
    assert(server.port == 8080 && server.host == "edge");
    assert(database.url == "postgres://db/app" && database.password == "hunter2" && database.pool == 9);
    assert(tls.tls);
}

@("keys that no bound type claims keep their exact unknown-key diagnostics")
unittest
{
    const directory = scratch();
    scope (exit)
        rmdirRecurse(directory);
    auto options = configFor(directory);
    options.arguments = ["--flint.profile=dev"];
    const toml = buildPath(directory, "application.toml");
    const dotenv = buildPath(directory, ".env");
    ServerProperties server;
    DatabaseProperties database;

    // A misspelt key inside a bound prefix: same text and offset as a single-type load.
    write(toml, "[server]\nport=8080\nprot=1\n");
    const single = load!ServerProperties(options).error;
    assert(single.message == "configuration key server.prot in application.toml at 3:1 is unknown");
    write(toml, "[server]\nport=8080\nprot=1\n[database]\nurl=\"postgres://db/app\"\n");
    auto failure = load(options, server, database);
    assert(failure.code == single.code && failure.message == single.message && failure.offset == single.offset);
    assert(server == ServerProperties.init && database == DatabaseProperties.init);

    // A misspelt prefix that no bound type claims, in a file, .env and --set.
    write(toml, "[server]\nport=8080\n[databse]\nurl=\"postgres://db/app\"\n");
    failure = load(options, server, database);
    assert(failure.code == Status.invalidArgument);
    assert(failure.message == "configuration key databse.url in application.toml at 4:1 is unknown");
    remove(toml);

    write(dotenv, "FLINT_CONFIG_FIXTURE_DATABASE__POOL=9\nFLINT_CONFIG_FIXTURE_DATABSE__URL=x\n");
    failure = load(options, server, database);
    write(dotenv, "FLINT_CONFIG_FIXTURE_DATABSE__URL=x\n");
    const singleDotenv = load!ServerProperties(options).error;
    assert(singleDotenv.message == "configuration key FLINT_CONFIG_FIXTURE_DATABSE__URL in .env at 1:1 is unknown");
    assert(failure.message == "configuration key FLINT_CONFIG_FIXTURE_DATABSE__URL in .env at 2:1 is unknown");
    remove(dotenv);

    options.arguments = ["--flint.profile=dev", "--set=database.url=x", "--set=databse.pool=1"];
    failure = load(options, server, database);
    assert(failure.message == "configuration key databse.pool in command line is unknown");
    assert(failure.message == load!DatabaseProperties(options).error.message);

    options.arguments = ["--flint.profile=dev", "--set=database.ulr=x"];
    assert(load(options, server, database).message == "configuration key database.ulr in command line is unknown");

    options.rejectUnknownKeys = false;
    assert(load(options, server, database).code == Status.ok);
}

@("process environment variables are unknown only outside every bound type")
unittest
{
    const directory = scratch();
    scope (exit)
        rmdirRecurse(directory);
    auto options = configFor(directory);
    options.arguments = ["--flint.profile=dev"];
    enum claimed = "FLINT_CONFIG_FIXTURE_DATABASE__URL";
    enum misspelt = "FLINT_CONFIG_FIXTURE_SERVER__PROT";
    scope (exit)
    {
        environment.remove(claimed);
        environment.remove(misspelt);
    }
    environment[claimed] = "postgres://db/app";
    ServerProperties server;
    DatabaseProperties database;
    assert(load(options, server, database).code == Status.ok);
    assert(database.url == "postgres://db/app");
    environment[misspelt] = "1";
    const failure = load(options, server, database);
    assert(failure.message == "configuration key " ~ misspelt ~ " in process environment is unknown");
}

@ConfigurationProperties("policy")
private struct PolicyFixture
{
    @Required
    string compiler;
    string[] flags;
}

@("a named file stem with the environment off reads only the files and explicit arguments")
unittest
{
    const directory = scratch();
    scope (exit)
        rmdirRecurse(directory);
    const previous = environment.toAA();
    scope (exit)
    {
        foreach (key; ["FLINT_PROFILE", "FLINT_CONFIG_FIXTURE_POLICY__COMPILER"])
        {
            if (auto value = key in previous)
                environment[key] = *value;
            else
                environment.remove(key);
        }
    }
    write(buildPath(directory, "profiles.toml"), "[policy]\ncompiler = \"dmd\"\nflags = [\"-g\"]\n");
    write(buildPath(directory, "profiles-ci.toml"), "[policy]\nflags = [\"-O\"]\n");
    write(buildPath(directory, "application.toml"), "[policy]\ncompiler = \"ignored\"\n");
    write(buildPath(directory, ".env"), "FLINT_CONFIG_FIXTURE_POLICY__COMPILER=dotenv\n");
    environment["FLINT_CONFIG_FIXTURE_POLICY__COMPILER"] = "process";
    environment["FLINT_PROFILE"] = "ci";

    auto options = configFor(directory);
    options.baseName = "profiles";
    options.readEnvironment = false;
    auto resolved = load!PolicyFixture(options);
    assert(resolved.ok && resolved.value.compiler == "dmd" && resolved.value.flags == ["-g"]);

    options.profile = "ci";
    resolved = load!PolicyFixture(options);
    assert(resolved.ok && resolved.value.flags == ["-O"]);
    options.arguments = ["--set=policy.compiler=ldc2"];
    resolved = load!PolicyFixture(options);
    assert(resolved.ok && resolved.value.compiler == "ldc2");

    options = configFor(directory);
    options.baseName = "profiles";
    resolved = load!PolicyFixture(options);
    assert(resolved.ok && resolved.value.compiler == "process" && resolved.value.flags == ["-O"]);

    options.baseName = "../profiles";
    assert(load!PolicyFixture(options).error.code == Status.invalidArgument);
    options.baseName = "";
    assert(load!PolicyFixture(options).error.code == Status.invalidArgument);
}

@ConfigurationProperties("todo")
private struct RelaxedFixture
{
    string dataFile;
    string defaultPriority = "normal";
    uint maxItems;
}

@("relaxed binding: kebab-case, snake_case and camelCase keys name the same field, and two spellings conflict")
unittest
{
    const directory = scratch();
    scope (exit)
        rmdirRecurse(directory);
    auto options = configFor(directory);
    options.readEnvironment = false;
    write(buildPath(directory, "application.toml"),
            "[todo]\ndata_file = \"/tmp/list.json\"\ndefault-priority = \"high\"\nmaxItems = 3\n");
    auto resolved = load!RelaxedFixture(options);
    assert(resolved.ok && resolved.value.dataFile == "/tmp/list.json");
    assert(resolved.value.defaultPriority == "high" && resolved.value.maxItems == 3);

    options.arguments = ["--set=todo.MAX_ITEMS=7"];
    resolved = load!RelaxedFixture(options);
    assert(resolved.ok && resolved.value.maxItems == 7);

    options.arguments = null;
    write(buildPath(directory, "application.toml"), "[todo]\ndata_file = \"a\"\ndata-file = \"b\"\n");
    resolved = load!RelaxedFixture(options);
    assert(resolved.error.code == Status.conflict && resolved.error.message.canFind("todo.dataFile"));

    write(buildPath(directory, "application.toml"), "[todo]\ncolour = \"red\"\n");
    resolved = load!RelaxedFixture(options);
    assert(resolved.error.code == Status.invalidArgument && resolved.error.message.canFind("todo.colour"));
}
