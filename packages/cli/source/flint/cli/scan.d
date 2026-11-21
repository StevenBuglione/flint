module flint.cli.scan;

import flint.arena : Error, Status;
import flint.cli.types : ParseAction, Shell;
import flint.validate : Size, validate;

@safe:

package(flint.cli) enum missing = size_t.max;

package(flint.cli) enum Binding : ubyte
{
    none,
    option,
    positional,
    command
}

package(flint.cli) struct Field
{
    Binding binding;
    string member;
    string name;
    string label;
    char shortName = '\0';
    string help;
    size_t position = missing;
    string environment;
    string typeName;
    bool required;
    bool boolean;
    bool repeated;
}

package(flint.cli) struct ScanResult
{
    Error error;
    ParseAction action;
    Shell shell;
    size_t child = missing;
    size_t remainder;
}

private alias Consume = Error delegate(size_t, scope const(char)[], size_t) @safe;

private struct Utf8Argument
{
    @Size(0, size_t.max) const(char)[] text;
}

package(flint.cli) bool isUtf8(scope const(char)[] text) nothrow @nogc
{
    scope item = Utf8Argument(text);
    return validate(item, []).valid;
}

package(flint.cli) Error invalid(scope const(char)[] label, scope const(char)[] reason, size_t index = missing)
{
    return Error(Status.invalidArgument, (label ~ ": " ~ reason).idup, index);
}

package(flint.cli) ScanResult scan(scope const Field[] fields, scope const(char[])[] args, size_t index,
        bool allowUnknown, scope Consume accept)
{
    size_t position;
    bool flags = true;
    for (; index < args.length; ++index)
    {
        scope const(char)[] token = args[index];
        if (flags && token == "--")
        {
            flags = false;
            continue;
        }
        const isOption = flags && token.length > 1 && token[0] == '-';
        if (isOption)
        {
            auto receipt = scanOption(fields, args, index, accept, allowUnknown);
            if (receipt.error.code != Status.ok || receipt.action != ParseAction.run)
                return receipt;
            if (receipt.remainder != missing)
                continue;
            // A negative numeric token with no known short alias is positional.
        }

        auto receipt = scanPosition(fields, token, index, position, flags && !isOption, accept);
        if (receipt.error.code != Status.ok || receipt.child != missing)
            return receipt;
    }
    return ScanResult.init;
}

private ScanResult scanPosition(scope const Field[] fields, scope const(char)[] token, size_t index,
        ref size_t position, bool maySelectCommand, scope Consume accept)
{
    if (maySelectCommand && position == 0)
    {
        const child = locate(fields, token, Binding.command);
        if (child != missing)
            return ScanResult(Error.init, ParseAction.run, Shell.bash, child, index + 1);
    }

    const field = positional(fields, position++);
    if (field == missing)
    {
        const reason = isUtf8(token) ? "unexpected positional argument" : "invalid UTF-8";
        return ScanResult(invalid("argument <redacted>", reason, index));
    }
    return ScanResult(accept(field, token, index));
}

private ScanResult scanOption(scope const Field[] fields, scope const(char[])[] args, ref size_t index,
        scope Consume accept, bool allowUnknown)
{
    scope const(char)[] token = args[index];
    if (token[1] == '-')
        return longOption(fields, args, index, accept, allowUnknown);
    if (isNegative(token) && shortField(fields, token[1]) == missing)
        return ScanResult(Error.init, ParseAction.run, Shell.bash, missing, missing);
    return shortOptions(fields, args, index, accept, allowUnknown);
}

private bool isNegative(scope const(char)[] token) pure nothrow @nogc
{
    const second = token[1];
    return isDigit(second) || (second == '.' && token.length > 2 && isDigit(token[2]));
}

private bool isDigit(char value) pure nothrow @nogc
{
    return value >= '0' && value <= '9';
}

private struct LongOption
{
    size_t length;
    bool inlineValue;
}

private LongOption splitLong(scope const(char)[] token) pure nothrow @nogc
{
    foreach (index, ch; token)
    {
        if (ch == '=')
            return LongOption(index, true);
    }
    return LongOption(token.length, false);
}

private ScanResult longOption(scope const Field[] fields, scope const(char[])[] args, ref size_t index,
        scope Consume accept, bool allowUnknown)
{
    scope const(char)[] token = args[index][2 .. $];
    const split = splitLong(token);
    scope const(char)[] name = token[0 .. split.length];
    if (!isUtf8(name))
        return ScanResult(invalid("option <redacted>", "invalid UTF-8 in option name", index));

    if (name == "help" || name == "version" || name == "completion")
        return builtIn(name, token, split, args, index);

    const option = locateLong(fields, name);
    if (option.field == missing)
        return unknownOption(name, "--", token, index, allowUnknown);

    const field = option.field;
    const negated = option.negated;
    const flag = fields[field].label;
    if (negated && split.inlineValue)
        return ScanResult(invalid(flag, "a negated flag takes no value", index));
    if (split.inlineValue)
        return ScanResult(accept(field, token[split.length + 1 .. $], index));
    if (fields[field].boolean)
        return ScanResult(accept(field, negated ? "false" : "true", index));
    return nextValue(flag, field, args, index, accept);
}

private struct MatchedOption
{
    size_t field = missing;
    bool negated;
}

private MatchedOption locateLong(scope const Field[] fields, scope const(char)[] name) pure nothrow @nogc
{
    const matching = locate(fields, name, Binding.option);
    if (matching != missing)
        return MatchedOption(matching);
    if (name.length <= 3 || name[0 .. 3] != "no-")
        return MatchedOption.init;
    const base = locate(fields, name[3 .. $], Binding.option);
    if (base == missing || !fields[base].boolean)
        return MatchedOption.init;
    return MatchedOption(base, true);
}

private ScanResult builtIn(scope const(char)[] name, scope const(char)[] token, LongOption split,
        scope const(char[])[] args, ref size_t index)
{
    if (name == "completion")
        return completionAction(token, split, args, index);
    const isHelp = name == "help";
    if (split.inlineValue)
        return ScanResult(invalid(isHelp ? "--help" : "--version", "takes no value", index));
    return ScanResult(Error.init, isHelp ? ParseAction.help : ParseAction.version_);
}

private ScanResult completionAction(scope const(char)[] token, LongOption split,
        scope const(char[])[] args, ref size_t index)
{
    if (!split.inlineValue && index + 1 >= args.length)
        return ScanResult(invalid("--completion", "expected bash, zsh, or powershell", index));

    scope const(char)[] text = split.inlineValue ? token[split.length + 1 .. $] : args[++index];
    switch (text)
    {
    case "bash":
        return ScanResult(Error.init, ParseAction.completion, Shell.bash);
    case "zsh":
        return ScanResult(Error.init, ParseAction.completion, Shell.zsh);
    case "powershell":
        return ScanResult(Error.init, ParseAction.completion, Shell.powershell);
    default:
        return ScanResult(invalid("--completion", "expected bash, zsh, or powershell; got <redacted>", index));
    }
}

private ScanResult shortOptions(scope const Field[] fields, scope const(char[])[] args, ref size_t index,
        scope Consume accept, bool allowUnknown)
{
    scope const(char)[] cluster = args[index][1 .. $];
    // Resolve the whole cluster before applying any flags. An unknown flag
    // makes the token atomic under allowUnknown, without guessing its arity.
    foreach (offset, aliasName; cluster)
    {
        if (aliasName == 'h')
            continue;
        const field = shortField(fields, aliasName);
        if (field == missing)
            return unknownOption(cluster[offset .. offset + 1], "-", cluster, index, allowUnknown);
        if (!fields[field].boolean)
            break;
    }

    foreach (offset, aliasName; cluster)
    {
        if (aliasName == 'h')
            return ScanResult(Error.init, ParseAction.help);
        const field = shortField(fields, aliasName);
        if (!fields[field].boolean)
            return shortValue(fields[field], field, args, index, offset + 2, accept);
        const error = accept(field, "true", index);
        if (error.code != Status.ok)
            return ScanResult(error);
    }
    return ScanResult.init;
}

private ScanResult shortValue(scope ref const Field item, size_t field, scope const(char[])[] args,
        ref size_t index, size_t start, scope Consume accept)
{
    scope const(char)[] text = args[index];
    if (start == text.length)
        return nextValue(item.label, field, args, index, accept);
    if (text[start] == '=')
        ++start;
    return ScanResult(accept(field, text[start .. $], index));
}

private ScanResult nextValue(scope const(char)[] name, size_t field, scope const(char[])[] args,
        ref size_t index, scope Consume accept)
{
    if (index + 1 >= args.length)
        return ScanResult(invalid(name, "missing value", index));
    ++index;
    return ScanResult(accept(field, args[index], index));
}

private ScanResult unknownOption(scope const(char)[] name, string prefix, scope const(char)[] token,
        size_t index, bool allowUnknown)
{
    if (!isUtf8(token))
        return ScanResult(invalid(prefix ~ "<redacted>", "invalid UTF-8 in unknown option", index));
    return allowUnknown ? ScanResult.init : ScanResult(unknown(name, prefix, index));
}

private Error unknown(scope const(char)[] name, string prefix, size_t index)
{
    if (name.length > 128 || !isUtf8(name) || !safeName(name))
        return invalid(prefix ~ "<redacted>", "unknown option", index);
    return invalid(prefix ~ name.idup, "unknown option", index);
}

package(flint.cli) bool safeName(scope const(char)[] name) pure nothrow @nogc
{
    if (name.length == 0)
        return false;
    foreach (ch; name)
    {
        if (ch < 0x20 || ch == 0x7F)
            return false;
    }
    return true;
}

private size_t locate(scope const Field[] fields, scope const(char)[] name, Binding kind) pure nothrow @nogc
{
    foreach (index, ref const field; fields)
    {
        if (field.binding == kind && field.name == name)
            return index;
    }
    return missing;
}

private size_t shortField(scope const Field[] fields, char aliasName) pure nothrow @nogc
{
    foreach (index, ref const field; fields)
    {
        if (field.binding == Binding.option && field.shortName != '\0' && field.shortName == aliasName)
            return index;
    }
    return missing;
}

private size_t positional(scope const Field[] fields, size_t position) pure nothrow @nogc
{
    size_t tail = missing;
    foreach (index, ref const field; fields)
    {
        if (field.binding != Binding.positional)
            continue;
        if (field.position == position)
            return index;
        if (tail == missing || field.position > fields[tail].position)
            tail = index;
    }
    return tail != missing && position > fields[tail].position && fields[tail].repeated ? tail : missing;
}
