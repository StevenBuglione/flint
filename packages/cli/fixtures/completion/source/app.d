module app;

import flint.cli : Command, Option, Shell, Subcommand, writeCompletion, writeHelp;
import std.stdio : write;

@safe:

private struct Leaf
{
    @Option("leaf", 'l', "Leaf option")
    bool leaf;
}

@Command("completion fixture", "Exercise literal shell completion candidates")
private struct Fixture
{
    @Option("text", 't', "Option taking a value")
    string text;
    @Option("quoted ' `touch FLINT_CLI_BACKTICK` $(touch FLINT_CLI_SUBSHELL) ’", 'q', "Quoted option")
    bool quoted;
    @Subcommand("child ' space", "Typed child command")
    Leaf child;
}

void main(string[] args)
{
    if (args.length != 2)
        throw new Exception("select help, bash, zsh, or powershell");
    auto sink = delegate(scope const(char)[] text) @safe { write(text.idup); };
    switch (args[1])
    {
    case "help":
        writeHelp!Fixture(sink);
        break;
    case "bash":
        writeCompletion!Fixture(Shell.bash, sink);
        break;
    case "zsh":
        writeCompletion!Fixture(Shell.zsh, sink);
        break;
    case "powershell":
        writeCompletion!Fixture(Shell.powershell, sink);
        break;
    default:
        throw new Exception("unknown completion fixture");
    }
}
