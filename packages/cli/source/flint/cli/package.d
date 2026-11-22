/// Typed command-line parsing, deterministic help, and shell completions.
module flint.cli;

import flint.cli.internal.parser : parseCore;
import flint.cli.internal.metadata : CommandTree;
import flint.cli.emit : renderHelp, renderCompletion;
public import flint.cli.types : Arg, Command, Environment, Option, ParseAction, ParseOptions,
    ParseResult, Required, Shell, Subcommand;

@safe:

/// Parse arguments after the program name. Input strings are not retained.
ParseResult!T parse(T)(scope const(char[])[] arguments, ParseOptions options = ParseOptions.init)
{
    return parseCore!T(arguments, options);
}

/// Write plain-text help for the command schema.
void writeHelp(T)(scope void delegate(scope const(char)[]) @safe sink)
{
    renderHelp(CommandTree!T.nodes, sink);
}

/// Write completion data and a registration function for the selected shell.
void writeCompletion(T)(Shell shell, scope void delegate(scope const(char)[]) @safe sink)
{
    renderCompletion(CommandTree!T.nodes, shell, sink);
}
