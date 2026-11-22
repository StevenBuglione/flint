/// `flint new`: the canonical project layout (ADR-021 section 2), deterministic for the same inputs.
module flint_tool.project.scaffold;

import flint_tool.home.policy : Home;
import flint_tool.project.manifest : moduleRootOf, starterPackages;

@safe:

/// One file to create, relative to the project directory.
struct ScaffoldFile
{
    /// Relative path.
    string path;
    /// Exact content.
    string content;
}

/// Core packages a new project depends on: the application's own set plus each starter's.
string[] scaffoldDependencies(string type, scope const(string)[] starters)
{
    import std.algorithm.sorting : sort;

    bool[string] chosen;
    if (type != "library")
    {
        foreach (name; ["arena", "cli", "config", "log"])
            chosen[name] = true;
    }
    foreach (starter; starters)
    {
        foreach (name; starterPackages[starter])
            chosen[name] = true;
    }
    auto names = chosen.keys;
    sort(names);
    return names;
}

/// The files of a new project.
ScaffoldFile[] scaffold(const ref Home home, string name, string type, scope const(string)[] starters)
{
    const root = moduleRootOf(name);
    const dependencies = scaffoldDependencies(type, starters);
    ScaffoldFile[] files;
    files ~= ScaffoldFile("flint.toml", manifest(home, name, type, starters, dependencies));
    files ~= ScaffoldFile(".gitignore", ".flint/\n");
    files ~= ScaffoldFile("config/application.toml",
            "# Base configuration, bound to @ConfigurationProperties(\"app\").\n"
            ~ "# Profile files override it: config/application-<profile>.toml, selected by FLINT_PROFILE.\n"
            ~ "[app]\ngreeting = \"Hello\"\n");
    files ~= ScaffoldFile("config/application-dev.toml",
            "# Overrides for the dev profile (the default).\n[app]\n" ~ "greeting = \"Hello\"\n");
    files ~= ScaffoldFile("config/application-prod.toml",
            "# Overrides for FLINT_PROFILE=prod.\n[app]\n" ~ "greeting = \"Good day\"\n");
    if (type == "library")
    {
        files ~= ScaffoldFile("src/" ~ root ~ "/package.d", libraryModule(name, root));
        files ~= ScaffoldFile("test/" ~ root ~ "/package_test.d", libraryTest(root));
    }
    else
    {
        files ~= ScaffoldFile("src/" ~ root ~ "/app.d", applicationModule(name, root));
        files ~= ScaffoldFile("src/" ~ root ~ "/greeting.d", greetingModule(root));
        files ~= ScaffoldFile("test/" ~ root ~ "/greeting_test.d", greetingTest(root));
    }
    return files;
}

private string manifest(const ref Home home, string name, string type, scope const(string)[] starters,
        scope const(string)[] dependencies)
{
    import std.array : join;

    string text = "[project]\nname = \"" ~ name ~ "\"\nversion = \"0.1.0\"\nflint = \""
        ~ home.platform.flint ~ "\"\ntype = \"" ~ type ~ "\"\n";
    if (starters.length)
        text ~= "\n# Starters arrive in Milestone 10. Until then `--starter " ~ starters.join(
                ",") ~ "` scaffolds their core packages below.\n";
    text ~= "\n[dependencies]\n";
    foreach (dependency; dependencies)
        text ~= "\"flint:" ~ dependency ~ "\" = {}\n";
    text ~= "\n[test-dependencies]\n\"flint:test\" = {}\n";
    return text;
}

private string fill(string text, string name, string root)
{
    import std.array : replace;

    return text.replace("$NAME$", name).replace("$ROOT$", root);
}

private string applicationModule(string name, string root)
{
    return fill(`/// $NAME$: the application root.
module $ROOT$.app;

import $ROOT$.greeting : greet;
import flint.arena : Status;
import flint.cli : Command, Option, ParseAction, parse, writeHelp;
import flint.config : ConfigOptions, ConfigurationProperties, Required, load;
import flint.log : Format, LogOptions, Logger;
import std.stdio : write, writeln;

@safe:

/// Command-line options, parsed before anything starts.
@Command("$NAME$", "Greet someone with the configured greeting")
struct Options
{
    /// Who to greet.
    @Option("name", 'n', "Name to greet") string name = "world";
}

/// Typed configuration bound from config/application*.toml.
@ConfigurationProperties("app")
struct AppSettings
{
    /// Greeting prefix.
    @Required string greeting;
}

int main(string[] args)
{
    const parsed = parse!Options(args[1 .. $]);
    if (parsed.error.code != Status.ok)
    {
        writeln("error: ", parsed.error.message);
        return 2;
    }
    if (parsed.action == ParseAction.help)
    {
        writeHelp!Options((scope const(char)[] text) @safe { write(text.idup); });
        return 0;
    }
    ConfigOptions config;
    config.directory = "config";
    const settings = load!AppSettings(config);
    if (!settings.ok())
    {
        writeln("configuration error: ", settings.error.message);
        return 3;
    }
    LogOptions logging;
    logging.format = Format.console;
    auto created = Logger.create(logging);
    if (!created.ok())
        return 4;
    auto logger = created.value;
    scope (exit)
        logger.close();
    writeln(greet(settings.value.greeting, parsed.options.name));
    if (logger.info("greeting delivered") != Status.ok)
        return 5;
    return logger.flush().code == Status.ok ? 0 : 6;
}
`, name, root);
}

private string greetingModule(string root)
{
    return fill(`/// Greeting rules: one business capability per module.
module $ROOT$.greeting;

@safe:

/// The greeting for ` ~ "`name`" ~ `, as "<greeting>, <name>!".
string greet(string greeting, string name) pure
{
    return greeting ~ ", " ~ (name.length ? name : "world") ~ "!";
}
`, null, root);
}

private string greetingTest(string root)
{
    return fill(`module $ROOT$.greeting_test;

import $ROOT$.greeting : greet;
import flint.test : expect;

@safe:

@("greet joins the greeting and the name")
unittest
{
    expect(greet("Hello", "Ada")).toEqual("Hello, Ada!");
}

@("greet falls back to world for an empty name")
unittest
{
    expect(greet("Hi", "")).toEqual("Hi, world!");
}
`, null, root);
}

private string libraryModule(string name, string root)
{
    return fill(`/// $NAME$: the library's public API.
module $ROOT$;

@safe:

/// The greeting for ` ~ "`name`" ~ `, as "Hello, <name>!".
string greet(string name) pure
{
    return "Hello, " ~ name ~ "!";
}
`, name, root);
}

private string libraryTest(string root)
{
    return fill(`module $ROOT$.package_test;

import $ROOT$ : greet;
import flint.test : expect;

@safe:

@("greet names the caller")
unittest
{
    expect(greet("Ada")).toEqual("Hello, Ada!");
}
`, null, root);
}
