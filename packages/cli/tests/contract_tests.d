module cli_contract_tests;

import flint.arena : Status;
import flint.cli : Arg, Command, Environment, Option, ParseAction, ParseOptions, Required, Shell,
    Subcommand, parse, writeCompletion, writeHelp;
import flint.validate : Min, NotBlank;
import std.process : environment;
import std.string : indexOf, splitLines;

@safe:

private enum Mode
{
    normal,
    fast
}

@Command("probe", "Parse a typed command", "2.0")
private struct Options
{
    @Option("count", 'n', "Item count")
    int count = 1;
    @Option("max", '\0', "Maximum")
    ulong latest;
    @Option("rate", 'r', "Rate")
    double rate;
    @Option("mode", 'm', "Mode")
    Mode mode;
    @Option("name", 's', "Name")
    string name = "default";
    @Option("values", 'v', "Value")
    string[] values;
    @Option("along", 'a', "A")
    bool a;
    @Option("below", 'b', "B")
    bool b;
    @Option("clear", 'c', "C")
    bool c;
    @Arg(0, "Files")
    string[] files;
}

@("CLI-01 checked integer and float conversions, enum names and scalar duplication")
unittest
{
    const pairs = parse!Options([
        "--count", "2", "--max=18446744073709551615", "-r.25", "--mode=fast"
    ]);
    assert(pairs.error.code == Status.ok);
    assert(pairs.options.count == 2 && pairs.options.latest == ulong.max);
    assert(pairs.options.rate == 0.25 && pairs.options.mode == Mode.fast);
    assert(parse!Options(["--count=2"]).options.count == 2);
    assert(parse!Options(["--count", "-2147483648"]).options.count == int.min);
    assert(parse!Options(["--count"]).error.offset == 0);

    static immutable bad = [
        "--count=2147483648", "--count=-2147483649", "--count=2x", "--count=1,234", "--count= ",
        "--count=", "--max=-1", "--max=18446744073709551616", "--rate=NaN", "--rate=1e5000",
        "--rate=1.2.3", "--mode=Fast"
    ];
    foreach (argument; bad)
    {
        const result = parse!Options([argument]);
        assert(result.error.code == Status.invalidArgument && result.error.offset == 0, argument);
        assert(indexOf(result.error.message, "<redacted>") >= 0);
    }
    const duplicate = parse!Options(["--count", "4", "-n5"]);
    assert(duplicate.error.code == Status.invalidArgument && duplicate.error.offset == 2);
    assert(indexOf(duplicate.error.message, "--count") == 0);
}

@("CLI-02 clustered booleans and one consuming alias, negation, unknown token atomicity")
unittest
{
    const cluster = parse!Options(["-abc", "-sSteve", "--values=a", "-vb", "--values", "c"]);
    assert(cluster.error.code == Status.ok);
    assert(cluster.options.a && cluster.options.b && cluster.options.c);
    assert(cluster.options.name == "Steve" && cluster.options.values == ["a", "b", "c"]);
    const attached = parse!Options(["-absSteve", "--no-clear"]);
    assert(attached.error.code == Status.ok && attached.options.a && attached.options.b && !attached.options.c);
    assert(attached.options.name == "Steve");
    assert(parse!Options(["--along=false"]).error.code == Status.ok);
    assert(!parse!Options(["--along=false"]).options.a);
    assert(parse!Options(["--no-along=true"]).error.code == Status.invalidArgument);
    assert(parse!Options(["--along", "--no-along"]).error.offset == 1);

    const ignored = parse!Options(["-az", "--undefined=do-not-echo", "input"], ParseOptions(true));
    assert(ignored.error.code == Status.ok && !ignored.options.a);
    assert(ignored.options.files == ["input"]);
    const unknown = parse!Options(["--undefined=do-not-echo"]);
    assert(unknown.error.code == Status.invalidArgument);
    assert(indexOf(unknown.error.message, "--undefined") == 0 && indexOf(unknown.error.message, "do-not-echo") < 0);
}

private struct Offset
{
    @Arg(0, "Signed offset")
    int amount;
}

@("CLI-04 option terminator preserves dash-prefixed text and negative positionals")
unittest
{
    const literal = parse!Options(["--", "--name", "-x", ""]);
    assert(literal.error.code == Status.ok && literal.options.files == ["--name", "-x", ""]);
    assert(parse!Offset(["--", "-7"]).options.amount == -7);
    assert(parse!Offset(["-7"]).options.amount == -7);
    assert(parse!Options(["-"]).options.files == ["-"]);
    assert(parse!Options(["-s", "--help"]).options.name == "--help");
}

@("CLI-05 returned text owns UTF-8 and preserves empty argument values")
unittest
{
    auto input = "語り🦊".dup;
    const(char[])[] arguments = ["--name", input, "--values=", ""];
    const result = parse!Options(arguments);
    assert(result.error.code == Status.ok);
    input[] = '?';
    assert(result.options.name == "語り🦊");
    assert(result.options.values == [""] && result.options.files == [""]);
    const bad = parse!Options(["--name=\xED\xA0\x80"]);
    assert(bad.error.code == Status.invalidArgument && indexOf(bad.error.message, "--name") == 0);
    assert(parse!Options(["--name", "\xF4\x90\x80\x80"]).error.offset == 1);
    assert(parse!Options(["--", "\xFF"]).error.code == Status.invalidArgument);
}

private struct RequiredEnvironment
{
    @Option("value", 'v', "Value")
    @Required
    @Environment("FLINT_CLI_TEST_VALUE_C95D")
    @Min(2)
    int value = 91;
    @Option("text", 's', "Text")
    @Environment("FLINT_CLI_TEST_TEXT_C95D")
    string text = "default";
}

private void withEnvironment(string variable, string text, scope void delegate() @safe run)
{
    const present = variable in environment;
    const old = environment.get(variable);
    scope (exit)
    {
        if (present)
            environment[variable] = old;
        else
            environment.remove(variable);
    }
    environment[variable] = text;
    run();
}

@("CLI-06 precedence, explicit environment opt-in, and actions without required values")
unittest
{
    enum variable = "FLINT_CLI_TEST_VALUE_C95D";
    withEnvironment(variable, "7", () @safe {
        assert(parse!RequiredEnvironment([]).error.code == Status.invalidArgument);
        const fromEnvironment = parse!RequiredEnvironment([], ParseOptions(false, true));
        assert(fromEnvironment.error.code == Status.ok && fromEnvironment.options.value == 7);
        withEnvironment("FLINT_CLI_TEST_TEXT_C95D", "", () @safe {
            const empty = parse!RequiredEnvironment([], ParseOptions(false, true));
            assert(empty.options.text == "" && empty.error.code == Status.ok);
        });
    });
    withEnvironment(variable, "SECRET", () @safe {
        const root = parse!RequiredEnvironment(["--value=8"], ParseOptions(false, true));
        assert(root.options.value == 8 && root.error.code == Status.ok);
        const invalid = parse!RequiredEnvironment([], ParseOptions(false, true));
        assert(invalid.error.code == Status.invalidArgument && invalid.error.offset == size_t.max);
        assert(indexOf(invalid.error.message, "SECRET") < 0);
        assert(parse!RequiredEnvironment(["--help"], ParseOptions(false, true)).action == ParseAction.help);
    });

    const options = parse!RequiredEnvironment(["--value=1"]);
    assert(options.error.code == Status.invalidArgument && options.error.offset == 0);
    assert(indexOf(options.error.message, "<redacted>") >= 0);
    assert(parse!RequiredEnvironment(["-h"]).error.code == Status.ok);
    assert(parse!RequiredEnvironment(["--version"]).action == ParseAction.version_);
    assert(parse!RequiredEnvironment(["--completion", "bash"]).completionShell == Shell.bash);
    assert(parse!RequiredEnvironment(["--completion=zsh"]).completionShell == Shell.zsh);
    const ps = parse!RequiredEnvironment(["--completion", "powershell"]);
    assert(ps.action == ParseAction.completion && ps.completionShell == Shell.powershell);
    assert(parse!RequiredEnvironment(["--completion", "others"]).error.offset == 1);
}

private struct Defaults
{
    @Option("names", 'n', "Names")
    string[] names = ["base"];
}

@("defaults are owned and explicit repeated options replace the default source")
unittest
{
    auto first = parse!Defaults([]);
    const second = parse!Defaults([]);
    first.options.names[0] = "edited";
    assert(second.options.names == ["base"]);
    assert(parse!Defaults(["--names=first", "-nsecond"]).options.names == ["first", "second"]);
}

private struct Leaf
{
    @Option("target", 't', "Deploy target")
    @Required
    @NotBlank
    string target;
}

private struct Service
{
    @Subcommand("deploy", "Deploy service")
    Leaf deploy;
    @Option("server", 's', "Server")
    string server = "local";
}

@Command("cloud", "Manage services")
private struct Root
{
    @Option("config", 'c', "Config path")
    string config = "application.toml";
    @Subcommand("service", "Service operations")
    Service service;
    @Subcommand("inactive", "This leaf is never selected")
    Leaf inactive;
}

@("nested command paths select explicit child DTOs and validate the active path only")
unittest
{
    const selected = parse!Root(["-cspecial.toml", "service", "--server=work", "deploy", "-tprod"]);
    assert(selected.error.code == Status.ok && selected.commandName == "cloud service deploy");
    assert(selected.options.config == "special.toml" && selected.options.service.server == "work");
    assert(selected.options.service.deploy.target == "prod");
    assert(parse!Root([]).commandName == "cloud");
    assert(parse!Root(["service", "deploy"]).error.code == Status.invalidArgument);
    const help = parse!Root(["service", "deploy", "--help"]);
    assert(help.action == ParseAction.help && help.error.code == Status.ok);
    assert(help.commandName == "cloud service deploy");
    const invalid = parse!Root(["service", "deploy", "--target", " "]);
    assert(invalid.error.code == Status.invalidArgument && invalid.error.offset == 3);
}

@("help for a selected subcommand shows its path, options and arguments")
unittest
{
    const parsed = parse!Root(["service", "deploy", "--help"]);
    string text;
    writeHelp!Root(parsed.commandName, (scope const(char)[] chunk) @safe { text ~= chunk; });
    assert(indexOf(text, "Usage cloud service deploy [options]\n") >= 0);
    assert(indexOf(text, "-t, --target <text>") >= 0 && indexOf(text, "--config") < 0);
    assert(indexOf(text, "--version") < 0);
    string service;
    writeHelp!Root("cloud service", (scope const(char)[] chunk) @safe { service ~= chunk; });
    assert(indexOf(service, "Usage cloud service [options] [command]") >= 0 && indexOf(service, "deploy") >= 0);
    string fallback;
    writeHelp!Root("cloud nowhere", (scope const(char)[] chunk) @safe { fallback ~= chunk; });
    assert(indexOf(fallback, "Usage cloud [options] [command]") >= 0);
}

@Command("help-snapshot",
        "One two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen")
private struct HelpDto
{
    @Option("beta", 'b', "Beta flag")
    bool beta;
    @Option("alpha", 'a', "Alpha text")
    @Required
    string alpha;
    @Arg(0, "Name")
    string name;
}

@("help uses schema order, stable built-ins, and an 80-byte line limit")
unittest
{
    string text;
    writeHelp!HelpDto((scope const(char)[] chunk) @safe { text ~= chunk; });
    assert(indexOf(text, "Usage help-snapshot [options] [name]\n") >= 0);
    assert(indexOf(text, "-b, --beta, --no-beta") < indexOf(text, "-a, --alpha <text>"));
    assert(indexOf(text, "Alpha text (required)") >= 0);
    assert(indexOf(text, "-h, --help") >= 0);
    foreach (line; splitLines(text))
        assert(line.length <= 80);

    string bash;
    string zsh;
    string ps;
    writeCompletion!Root(Shell.bash, (scope const(char)[] chunk) @safe { bash ~= chunk; });
    writeCompletion!Root(Shell.zsh, (scope const(char)[] chunk) @safe { zsh ~= chunk; });
    writeCompletion!Root(Shell.powershell, (scope const(char)[] chunk) @safe { ps ~= chunk; });
    assert(indexOf(bash, "complete -F _flint_cli_") >= 0);
    assert(indexOf(zsh, "_arguments") >= 0 && indexOf(zsh, "compadd --") >= 0);
    assert(indexOf(ps, "Register-ArgumentCompleter -Native") >= 0);
}

private enum CanParse(T) = __traits(compiles, () @safe { parse!T([]); });

private struct DuplicateLong
{
    @Option("name", 'a', "")
    int first;
    @Option("name", 'b', "")
    int second;
}

private struct DuplicateShort
{
    @Option("first", 'a', "")
    int first;
    @Option("second", 'a', "")
    int second;
}

private struct DuplicatePosition
{
    @Arg(0, "")
    int first;
    @Arg(0, "")
    int second;
}

private struct DuplicateChild
{
    @Subcommand("common", "")
    Leaf first;
    @Subcommand("common", "")
    Leaf second;
}

private struct InverseCollision
{
    @Option("first", 'a', "")
    bool first;
    @Option("no-first", 'b', "")
    bool second;
}

private struct UnboundRequired
{
    @Required
    string value;
}

private struct Reserved
{
    @Option("help", '\0', "")
    string value;
}

static assert(CanParse!Options);
static assert(!CanParse!DuplicateLong);
static assert(!CanParse!DuplicateShort);
static assert(!CanParse!DuplicatePosition);
static assert(!CanParse!DuplicateChild);
static assert(!CanParse!InverseCollision);
static assert(!CanParse!UnboundRequired);
static assert(!CanParse!Reserved);

@("CLI-01 bare value option, overflow and trailing data fail with the argument index")
unittest
{
    const bare = parse!Options(["--count"]);
    assert(bare.error.code == Status.invalidArgument && bare.error.offset == 0);
    assert(indexOf(bare.error.message, "--count") == 0);
    const shortBare = parse!Options(["-n"]);
    assert(shortBare.error.code == Status.invalidArgument && shortBare.error.offset == 0);
    foreach (argument; ["2147483648", "2x"])
    {
        const separate = parse!Options(["--count", argument]);
        assert(separate.error.code == Status.invalidArgument && separate.error.offset == 1, argument);
        assert(indexOf(separate.error.message, argument) < 0);
    }
    assert(parse!Options(["--count", "2"]).options.count == 2);
    assert(parse!Options(["-n2"]).options.count == 2 && parse!Options(["-n=2"]).options.count == 2);
}

@("CLI-02 a value alias consumes the rest of its cluster even when it spells other aliases")
unittest
{
    const consumed = parse!Options(["-sabc"]);
    assert(consumed.error.code == Status.ok && consumed.options.name == "abc");
    assert(!consumed.options.a && !consumed.options.b && !consumed.options.c);
    const counted = parse!Options(["-an5"]);
    assert(counted.error.code == Status.ok && counted.options.a && counted.options.count == 5);
    const next = parse!Options(["-abs", "-c"]);
    assert(next.error.code == Status.ok && next.options.name == "-c" && !next.options.c);
    const missingValue = parse!Options(["-abs"]);
    assert(missingValue.error.code == Status.invalidArgument && missingValue.error.offset == 0);
}

private struct Hostile
{
    @Option("quoted ' `touch FLINT_CLI_TICK` $(touch FLINT_CLI_SUB) \"dq\" \\ end", 'q', "Quoted")
    bool quoted;
    @Subcommand("child ' $(touch FLINT_CLI_CHILD)", "Child")
    Leaf child;
}

/// Return true when every marker occurrence is inside a POSIX single-quoted word.
private bool singleQuotedOnly(string script, string marker)
{
    bool quoted;
    size_t found;
    for (size_t index = 0; index < script.length; ++index)
    {
        if (!quoted && script[index] == '\\')
        {
            ++index;
            continue;
        }
        if (script[index] == '\'')
        {
            quoted = !quoted;
            continue;
        }
        if (script[index .. $].length >= marker.length && script[index .. index + marker.length] == marker)
        {
            if (!quoted)
                return false;
            ++found;
        }
    }
    return found != 0 && !quoted;
}

@("CLI-07 completion metadata is emitted only as quoted or encoded data")
unittest
{
    string bash;
    string zsh;
    string ps;
    writeCompletion!Hostile(Shell.bash, (scope const(char)[] chunk) @safe { bash ~= chunk; });
    writeCompletion!Hostile(Shell.zsh, (scope const(char)[] chunk) @safe { zsh ~= chunk; });
    writeCompletion!Hostile(Shell.powershell, (scope const(char)[] chunk) @safe { ps ~= chunk; });
    static immutable markers = [
        "touch FLINT_CLI_TICK", "touch FLINT_CLI_SUB", "touch FLINT_CLI_CHILD", "\"dq\""
    ];
    foreach (marker; markers)
    {
        assert(singleQuotedOnly(bash, marker), marker);
        assert(singleQuotedOnly(zsh, marker), marker);
        assert(indexOf(ps, marker) < 0, marker);
    }
    assert(indexOf(bash, "printf -v escaped '%q'") >= 0);
    assert(indexOf(ps, "FromBase64String(") >= 0 && indexOf(ps, "Replace(\"'\", \"''\")") >= 0);
}
