module flint.cli;
import flint.arena : Error;

@safe:
struct Command
{
    string name;
    string description;
    string versionText = "0.1.0";
}

struct Subcommand
{
    string name;
    string description;
}

struct Option
{
    string longName;
    char shortName;
    string help;
}

struct Arg
{
    size_t index;
    string help;
}

struct Required
{
}

struct Environment
{
    string name;
}

enum ParseAction : ubyte
{
    run,
    help,
    version_,
    completion
}

struct ParseOptions
{
    bool allowUnknown = false;
    bool readEnvironment = false;
}

struct ParseResult(T)
{
    T options;
    ParseAction action;
    Error error;
    Shell completionShell = Shell.bash;
    string commandName;
}

ParseResult!T parse(T)(scope const(char[])[] arguments, ParseOptions options = ParseOptions.init);
void writeHelp(T)(scope void delegate(scope const(char)[]) @safe sink);
enum Shell : ubyte
{
    bash,
    zsh,
    powershell
}

void writeCompletion(T)(Shell shell, scope void delegate(scope const(char)[]) @safe sink);
