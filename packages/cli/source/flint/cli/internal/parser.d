module flint.cli.internal.parser;

import flint.arena : Error, Status;
import flint.cli.internal.convert : apply, ownDefault;
import flint.cli.internal.metadata : Schema;
import flint.cli.scan : Binding, Field, invalid, isUtf8, missing, scan;
import flint.cli.types : ParseAction, ParseOptions, ParseResult, Shell;

@safe:

private struct Seen
{
    size_t argument = missing;
    bool present;
}

private struct Flow
{
    string name;
    Error error;
    ParseAction action;
    Shell shell;
}

package(flint.cli) ParseResult!T parseCore(T)(scope const(char[])[] args, ParseOptions policy)
{
    ParseResult!T report;
    ownDefaults(report.options);
    const flow = parseNode(report.options, args, 0, policy, Schema!T.command.name);
    report.action = flow.action;
    report.completionShell = flow.shell;
    report.commandName = flow.name;
    report.error = flow.error;
    return report;
}

private void ownDefaults(T)(ref T values)
{
    static foreach (index, field; Schema!T.compiled)
    {
        static if (field.binding == Binding.option || field.binding == Binding.positional)
            ownDefault(values.tupleof[index]);
        else static if (field.binding == Binding.command)
            ownDefaults(values.tupleof[index]);
    }
}

private Flow parseNode(T)(ref T values, scope const(char[])[] args, size_t start, ParseOptions policy, string path)
{
    alias Local = Schema!T;
    Seen[Local.compiled.length] seen;
    const scanned = scan(Local.fields[], args, start, policy.allowUnknown, (size_t index,
            scope const(char)[] text, size_t argument) @safe {
        return store(values, seen[index], index, text, argument);
    });
    Flow flow = Flow(path, scanned.error, scanned.action, scanned.shell);
    if (flow.error.code != Status.ok || flow.action != ParseAction.run)
        return flow;
    if (scanned.child != missing)
        flow = childNode(values, args, scanned.remainder, policy, path, scanned.child);
    if (flow.error.code == Status.ok && flow.action == ParseAction.run)
        flow.error = completeNode(values, seen[], policy);
    return flow;
}

private Flow childNode(T)(ref T dto, scope const(char[])[] args, size_t remainder, ParseOptions policy,
        string path, size_t child)
{
    switch (child)
    {
        static foreach (index, field; Schema!T.compiled)
        {
            static if (field.binding == Binding.command)
            {
    case index:
                return parseNode(dto.tupleof[index], args, remainder, policy, path ~ " " ~ field.name);
            }
        }
    default:
        assert(0, "CLI scanner selected an unregistered command");
    }
}

private Error store(T)(ref T dto, ref Seen seen, size_t index, scope const(char)[] text, size_t argument)
{
    const field = Schema!T.fields[index];
    if (seen.present && !field.repeated)
        return invalid(field.label, "duplicate scalar value", argument);
    if (!isUtf8(text))
        return invalid(field.label, "invalid UTF-8 in <redacted>", argument);
    const problem = assign(dto, index, text, !seen.present);
    if (problem !is null)
        return invalid(field.label, problem ~ "; got <redacted>", argument);

    seen = Seen(argument, true);
    return Error.init;
}

private string assign(T)(ref T dto, size_t field, scope const(char)[] text, bool first)
{
    switch (field)
    {
        static foreach (index, item; Schema!T.compiled)
        {
            static if (item.binding == Binding.option || item.binding == Binding.positional)
            {
    case index:
                return apply(dto.tupleof[index], text, first);
            }
        }
    default:
        assert(0, "CLI scanner selected an unbound value");
    }
}

private Error completeNode(T)(ref T dto, scope Seen[] seen, ParseOptions policy)
{
    foreach (index, ref const field; Schema!T.fields)
    {
        static if (Schema!T.readsEnvironment)
        {
            import std.process : environment;

            if (!seen[index].present && policy.readEnvironment && field.environment.length != 0)
            {
                const value = environment.get(field.environment);
                if (value !is null)
                {
                    const failure = store(dto, seen[index], index, value, missing);
                    if (failure.code != Status.ok)
                        return failure;
                }
            }
        }
        if (!seen[index].present && field.required)
            return invalid(field.label, "required value was not supplied");
    }

    static if (Schema!T.checked)
    {
        import flint.validate : Violation, validate;

        Violation[1] failures;
        if (!validate(dto, failures[]).valid)
            return constraintError(Schema!T.fields[], seen, failures[0].field, failures[0].message);
    }
    return Error.init;
}

private Error constraintError(scope const Field[] fields, scope const Seen[] seen, string member, string message)
{
    foreach (index, ref const field; fields)
    {
        if (member == field.member)
            return invalid(field.label, message ~ "; got <redacted>", seen[index].argument);
    }
    return invalid(member, message ~ "; got <redacted>");
}
