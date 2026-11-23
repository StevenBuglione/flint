module flint.boot.boot_test;

import flint.arena : Status;
import flint.config : ConfigurationProperties;
import flint.di : AppContext, AutoConfiguration, Launcher, Provided, Service;
import flint.boot : ConfigurationTypes, bindConfiguration, runApplication;

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

private struct Recorded
{
    static string[] events;
}

private struct EchoLauncher
{
    static bool command(Context)(string[] args, out int code)
    {
        if (args.length > 1 && args[1] == "--version")
        {
            Recorded.events ~= "version";
            code = 7;
            return true;
        }
        return false;
    }

    static int launch(Context)(ref Context context, string[] args)
    {
        Recorded.events ~= "launch " ~ context.get!Greeter().properties.text;
        return 0;
    }
}

private alias Defaults = AutoConfiguration!(Provided!GreetingProperties, Launcher!EchoLauncher);

@("the runner answers a launcher's command, binds configuration, starts the context and launches")
unittest
{
    import std.file : chdir, getcwd, mkdirRecurse, rmdirRecurse, tempDir, write;
    import std.path : buildPath;
    import std.uuid : randomUUID;

    static assert(is(ConfigurationTypes!(AppContext!(Defaults, Greeter).Registered)[0] == GreetingProperties));
    const directory = buildPath(tempDir(), "flint-boot-" ~ randomUUID().toString());
    mkdirRecurse(buildPath(directory, "config"));
    const previous = getcwd();
    chdir(directory);
    scope (exit)
    {
        chdir(previous);
        rmdirRecurse(directory);
    }
    write(buildPath("config", "application.toml"), "[greeting]\ntext = \"Hi\"\n");
    Recorded.events = null;
    assert(runApplication!(Defaults, Greeter)(["app", "--version"]) == 7);
    assert(runApplication!(Defaults, Greeter)(["app"]) == 0);
    assert(runApplication!(Defaults, Greeter)(["app", "--set=greeting.text=Hey"]) == 0);
    assert(Recorded.events == ["version", "launch Hi", "launch Hey"], Recorded.events[0]);
    write(buildPath("config", "application.toml"), "[greeting]\ntxet = \"Hi\"\n");
    assert(runApplication!(Defaults, Greeter)(["app"]) == 3);
}
