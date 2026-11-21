module flint.cli.internal.metadata;

import flint.cli.internal.convert : IsRepeated, Supported, typeName;
import flint.cli.scan : Binding, Field, isUtf8, missing, safeName;
import flint.cli.types : Arg, Command, Environment, Option, Required, Subcommand;
import flint.validate : Email, Max, Min, NotBlank, Pattern, Size, Valid;
import std.traits : Unqual;

@safe:

package(flint.cli) template Schema(T)
{
    static assert(is(T == struct), "a CLI command DTO must be a struct");
    enum command = describeCommand!T();
    enum compiled = describeFields!T();
    enum conflict = findConflict(compiled[]);
    static assert(conflict.reason is null, CommandDiagnostic!(command.name, compiled, conflict));
    static immutable fields = compiled;
    enum checked = hasValidation!T();
    enum readsEnvironment = hasEnvironment(compiled[]);
}

private template CommandDiagnostic(string command, alias compiled, Conflict conflict)
{
    static if (conflict.reason is null)
        enum CommandDiagnostic = "";
    else
        enum CommandDiagnostic = command ~ "." ~ compiled[conflict.index].member ~ ": " ~ conflict.reason;
}

private Command describeCommand(T)()
{
    Command collected = Command(T.stringof, "");
    static foreach (attribute; __traits(getAttributes, T))
    {
        static if (is(typeof(attribute) == Command))
            collected = attribute;
        else static if (is(attribute == Command))
            static assert(0, T.stringof ~ ": Command requires a name");
    }
    return collected;
}

private Field[T.tupleof.length] describeFields(T)()
{
    enum ident = describeCommand!T();
    static assert(safeName(ident.name) && isUtf8(ident.name), T.stringof ~ ": invalid command name");
    static assert(isUtf8(ident.description) && isUtf8(ident.versionText),
            T.stringof ~ ": command description and version must use UTF-8");
    static assert(commandCount!T == 0 || commandCount!T == 1, T.stringof ~ ": duplicate Command annotation");

    Field[T.tupleof.length] fields;
    static foreach (index; 0 .. T.tupleof.length)
    {
        {
            alias Value = typeof(T.tupleof[index]);
            alias Annotations = __traits(getAttributes, T.tupleof[index]);
            enum member = __traits(identifier, T.tupleof[index]);
            enum path = ident.name ~ "." ~ member;
            fields[index] = describeField!(Value, path, member, Annotations)();
        }
    }
    return fields;
}

private bool hasEnvironment(scope const Field[] fields) pure nothrow @nogc
{
    foreach (ref const field; fields)
    {
        if (field.environment.length != 0)
            return true;
    }
    return false;
}

private bool hasValidation(T)() pure nothrow @nogc
{
    static foreach (index; 0 .. T.tupleof.length)
    {
        static foreach (attribute; __traits(getAttributes, T.tupleof[index]))
        {
            static if (is(attribute == Valid) || is(typeof(attribute) == Valid)
                    || is(attribute == NotBlank) || is(typeof(attribute) == NotBlank)
                    || is(attribute == Email) || is(typeof(attribute) == Email)
                    || is(attribute == Min) || is(typeof(attribute) == Min) || is(attribute == Max)
                    || is(typeof(attribute) == Max) || is(attribute == Size)
                    || is(typeof(attribute) == Size) || is(attribute == Pattern) || is(typeof(attribute) == Pattern))
                return true;
        }
    }
    return false;
}

private enum commandCount(T) = countCommands!T();

private size_t countCommands(T)() pure nothrow @nogc
{
    size_t count;
    static foreach (attribute; __traits(getAttributes, T))
    {
        static if (is(typeof(attribute) == Command))
            ++count;
    }
    return count;
}

private struct Bindings
{
    size_t positionals;
    size_t options;
    size_t commands;
    size_t environment;
    bool validateChild;
}

private Bindings countBindings(Attributes...)() pure nothrow @nogc
{
    Bindings result;
    static foreach (attribute; Attributes)
    {
        static if (is(typeof(attribute) == Arg))
            ++result.positionals;
        else static if (is(typeof(attribute) == Option))
            ++result.options;
        else static if (is(typeof(attribute) == Subcommand))
            ++result.commands;
        else static if (is(typeof(attribute) == Environment))
            ++result.environment;
        else static if (is(attribute == Valid) || is(typeof(attribute) == Valid))
            result.validateChild = true;
    }
    return result;
}

private Field describeField(T, string path, string member, Attributes...)()
{
    enum bindings = countBindings!Attributes();
    static assert(bindings.positionals + bindings.options + bindings.commands <= 1,
            path ~ ": conflicting field bindings");
    static assert(bindings.environment <= 1, path ~ ": duplicate Environment annotation");
    static if (bindings.commands != 0)
    {
        static assert(is(T == struct) && is(T == Unqual!T), path ~ ": Subcommand requires a mutable struct field");
        static assert(!bindings.validateChild,
                path ~ ": Subcommand validation follows the selected command; omit Valid");
    }
    else static if (bindings.positionals != 0 || bindings.options != 0)
    {
        static assert(Supported!T && is(T == Unqual!T), path ~ ": unsupported or immutable CLI field type");
    }

    Field field;
    field.member = member;
    static foreach (attribute; Attributes)
    {
        {
            static if (is(attribute == Option) || is(attribute == Arg) || is(attribute == Subcommand)
                    || is(attribute == Environment))
            {
                static assert(0, path ~ ": field binding requires explicit arguments");
            }
            else static if (is(typeof(attribute) == Option))
            {
                static assert(validLong(attribute.longName), path ~ ": invalid or reserved long option");
                static assert(validShort(attribute.shortName), path ~ ": invalid or reserved short alias");
                static assert(isUtf8(attribute.help), path ~ ": option help must use UTF-8");
                field.binding = Binding.option;
                field.name = attribute.longName;
                field.shortName = attribute.shortName == char.init ? '\0' : attribute.shortName;
                field.help = attribute.help;
            }
            else static if (is(typeof(attribute) == Arg))
            {
                static assert(attribute.index != missing, path ~ ": positional index is out of range");
                static assert(isUtf8(attribute.help), path ~ ": argument help must use UTF-8");
                field.binding = Binding.positional;
                field.position = attribute.index;
                field.help = attribute.help;
            }
            else static if (is(typeof(attribute) == Subcommand))
            {
                static assert(validChild(attribute.name), path ~ ": invalid subcommand name");
                static assert(isUtf8(attribute.description), path ~ ": subcommand description must use UTF-8");
                field.binding = Binding.command;
                field.name = attribute.name;
                field.help = attribute.description;
            }
            else static if (is(typeof(attribute) == Environment))
            {
                static assert(validEnvironment(attribute.name) && isUtf8(attribute.name),
                        path ~ ": invalid environment variable name");
                field.environment = attribute.name;
            }
            else static if (is(attribute == Required) || is(typeof(attribute) == Required))
            {
                field.required = true;
            }
        }
    }

    field.label = field.binding == Binding.option ? "--" ~ field.name : field.member;
    if (field.binding == Binding.option || field.binding == Binding.positional)
    {
        field.boolean = is(T == bool) && field.binding == Binding.option;
        field.repeated = IsRepeated!T;
        field.typeName = typeName!T();
    }
    return field;
}

private bool validLong(string name)
{
    if (!safeName(name) || !isUtf8(name) || name[0] == '-')
        return false;
    if (name == "help" || name == "version" || name == "completion")
        return false;
    foreach (ch; name)
    {
        if (ch == '=')
            return false;
    }
    return true;
}

private bool validChild(string name)
{
    return safeName(name) && isUtf8(name) && name[0] != '-';
}

private bool validShort(char name) pure nothrow @nogc
{
    const unset = name == '\0' || name == char.init;
    return unset || (name > ' ' && name < 0x7F && name != '-' && name != '=' && name != 'h');
}

private bool validEnvironment(string name) pure nothrow @nogc
{
    if (name.length == 0)
        return false;
    foreach (ch; name)
    {
        if (ch == '=' || ch == '\0')
            return false;
    }
    return true;
}

private struct Conflict
{
    size_t index;
    string reason;
}

private Conflict findConflict(scope const Field[] fields) pure nothrow @nogc
{
    foreach (index, ref const field; fields)
    {
        if ((field.binding == Binding.none || field.binding == Binding.command) && (field.required
                || field.environment.length != 0))
            return Conflict(index, "Required and Environment need an option or positional binding");
        foreach (ref const earlier; fields[0 .. index])
        {
            const reason = conflicts(earlier, field);
            if (reason !is null)
                return Conflict(index, reason);
        }
    }
    return Conflict.init;
}

private string conflicts(scope ref const Field left, scope ref const Field right) pure nothrow @nogc
{
    if (left.binding != right.binding)
        return null;
    final switch (left.binding)
    {
    case Binding.none:
        return null;
    case Binding.command:
        return left.name == right.name ? "duplicate subcommand name" : null;
    case Binding.positional:
        return left.position == right.position ? "duplicate positional index" : null;
    case Binding.option:
        return optionConflict(left, right);
    }
}

private string optionConflict(scope ref const Field left, scope ref const Field right) pure nothrow @nogc
{
    if (left.name == right.name)
        return "duplicate long option";
    if (left.shortName != '\0' && left.shortName == right.shortName)
        return "duplicate short alias";
    if ((left.boolean && isNegation(right.name, left.name)) || (right.boolean && isNegation(left.name, right.name)))
        return "long option conflicts with a negated boolean flag";
    return null;
}

private bool isNegation(string candidate, string base) pure nothrow @nogc
{
    return candidate.length > 3 && candidate[0 .. 3] == "no-" && candidate[3 .. $] == base;
}

package(flint.cli) struct CommandNode
{
    string name;
    string description;
    string versionText;
    immutable(Field)[] fields;
    size_t parent;
}

package(flint.cli) template CommandTree(T)
{
    static immutable nodes = collectCommands!T();
}

private CommandNode[] collectCommands(T)()
{
    CommandNode[] nodes;
    appendNode!T(nodes, Schema!T.command.name, Schema!T.command.description, missing);
    return nodes;
}

private void appendNode(T)(ref CommandNode[] nodes, string name, string description, size_t parent)
{
    const index = nodes.length;
    nodes ~= CommandNode(name, description, Schema!T.command.versionText, Schema!T.fields[], parent);
    static foreach (fieldIndex, item; Schema!T.compiled)
    {
        static if (item.binding == Binding.command)
            appendNode!(typeof(T.tupleof[fieldIndex]))(nodes, item.name, item.help, index);
    }
}
