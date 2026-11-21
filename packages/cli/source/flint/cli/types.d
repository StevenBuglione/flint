module flint.cli.types;
import flint.arena : Error;

@safe:
/// Metadata for a command DTO and its top-level help.
struct Command
{
    /// Command or environment name.
    string name;
    /// Summary used in help.
    string description;
    /// Version text advertised in help.
    string versionText = "0.1.0";
}

/// Bind a positional command name to a typed child field.
struct Subcommand
{
    /// Command or environment name.
    string name;
    /// Summary used in help.
    string description;
}

/// Bind a field to a long option and an optional short alias.
struct Option
{
    /// Option name without the leading double dash.
    string longName;
    /// Optional one-byte alias. Zero or char.init omits it.
    char shortName;
    /// Human-readable description.
    string help;
}

/// Bind a field to a zero-based positional argument.
struct Arg
{
    /// Zero-based position in this command.
    size_t index;
    /// Human-readable description.
    string help;
}

/// Require a value from the command line or opted-in environment.
struct Required
{
}

/// Read a fallback value from this environment variable when enabled.
struct Environment
{
    /// Command or environment name.
    string name;
}

/// Operation to perform after parsing.
enum ParseAction : ubyte
{
    run,
    help,
    version_,
    completion
}

/// Explicit parsing policies for unknown options and environment values.
struct ParseOptions
{
    /// Skip a whole unknown option token without consuming a following value.
    bool allowUnknown = false;
    /// Enable environment-bound fallback values.
    bool readEnvironment = false;
}

/// Owned typed values and the selected action.
struct ParseResult(T)
{
    /// Command DTO with owned input values.
    T options;
    /// Action chosen by built-in options, or normal execution.
    ParseAction action;
    /// Failure with the original zero-based argument offset, if available.
    Error error;
    /// Target shell for a completion action.
    Shell completionShell = Shell.bash;
    /// Selected command path, including the root command name.
    string commandName;
}

/// Target shell for completion output.
enum Shell : ubyte
{
    bash,
    zsh,
    powershell
}
