module app;
import flint.arena : Status;
import flint.cli : Command, Option, parse, ParseAction, writeHelp, writeCompletion, Shell;
import flint.config : ConfigurationProperties, Required, ConfigOptions, load;
import flint.log : Logger, LogOptions, Format;
import std.stdio : write, writeln;

@safe:

/// Typed command-line inputs; parsing occurs before service startup.
@Command("hello", "Greet someone using typed configuration")
struct Options
{
    /// Name printed in the greeting.
    @Option("name", 'n', "Name to greet") string name = "world";
}

/// Required application configuration bound at startup.
@ConfigurationProperties("hello")
struct Settings
{
    /// Localized greeting prefix.
    @Required string greeting;
}

int main(string[] args)
{
    auto parsed = parse!Options(args[1 .. $]);
    if (parsed.error.code != Status.ok)
        return 2;
    if (parsed.action == ParseAction.help)
    {
        writeHelp!Options((scope const(char)[] text) @safe { write(text.idup); });
        return 0;
    }
    if (parsed.action == ParseAction.completion)
    {
        writeCompletion!Options(parsed.completionShell, (scope const(char)[] text) @safe {
            write(text.idup);
        });
        return 0;
    }
    if (parsed.action == ParseAction.version_)
    {
        writeln("hello-example 1");
        return 0;
    }
    ConfigOptions config;
    auto settings = load!Settings(config);
    if (!settings.ok())
        return 3;
    LogOptions logOptions;
    logOptions.format = Format.console;
    auto created = Logger.create(logOptions);
    if (!created.ok())
        return 4;
    auto logger = created.value;
    scope (exit)
        logger.close();
    writeln(settings.value.greeting, ", ", parsed.options.name, "!");
    if (logger.info("greeting completed") != Status.ok)
        return 5;
    return logger.flush().code == Status.ok ? 0 : 6;
}
