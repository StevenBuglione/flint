module flint.starter_web.starter_web_test;

import flint.config : ConfigurationProperties;
import flint.di : AppContext, ConfiguredSections, Provided, Service;
import flint.starter_web : ConfigurationTypes, Controllers, ServerProperties, WebAutoConfiguration, bindConfiguration;
import flint.web : Get, RestController;

@safe:

@ConfigurationProperties("greeting")
private struct GreetingProperties
{
    string text = "Hello";
}

@Service private final class Greeter
{
    GreetingProperties properties;
    this(GreetingProperties properties)
    {
        this.properties = properties;
    }
}

@RestController("/api/greetings")
private struct GreetingController
{
    Greeter greeter;
    this(Greeter greeter)
    {
        this.greeter = greeter;
    }

    @Get("")
    string list()
    {
        return greeter.properties.text;
    }
}

private alias Context = AppContext!(WebAutoConfiguration, Provided!GreetingProperties, Greeter, GreetingController);

@("the starter collects configuration types and controllers from the resolved registrations")
unittest
{
    alias Types = ConfigurationTypes!(Context.Registered);
    static assert(is(Types[0] == ServerProperties) && is(Types[1] == GreetingProperties) && Types.length == 2);
    static assert(is(Controllers!(Context.Registered).Types[0] == GreetingController));
    static assert(Controllers!(Context.Registered).Types.length == 1);
}

@("configuration binds from config/ with --set overrides, and unknown keys are errors")
unittest
{
    import flint.arena : Status;
    import std.file : chdir, getcwd, mkdirRecurse, rmdirRecurse, tempDir, write;
    import std.path : buildPath;
    import std.uuid : randomUUID;

    const directory = buildPath(tempDir(), "flint-starter-web-" ~ randomUUID().toString());
    mkdirRecurse(buildPath(directory, "config"));
    const previous = getcwd();
    chdir(directory);
    scope (exit)
    {
        chdir(previous);
        rmdirRecurse(directory);
    }
    write(buildPath("config", "application.toml"), "[server]\nport = 9090\n[greeting]\ntext = \"Hi\"\n");
    Context context;
    assert(bindConfiguration(context, ["--set=server.address=0.0.0.0"]).code == Status.ok);
    assert(context.initialize().code == Status.ok);
    assert(context.get!ServerProperties().port == 9090 && context.get!ServerProperties().address == "0.0.0.0");
    assert(context.get!GreetingController().list() == "Hi");
    context.shutdown();

    write(buildPath("config", "application.toml"), "[server]\nprot = 9090\n");
    Context misspelt;
    const failed = bindConfiguration(misspelt, null);
    assert(failed.code == Status.invalidArgument);
    import std.algorithm.searching : canFind;

    assert(failed.message.canFind("server.prot"), failed.message);
}
