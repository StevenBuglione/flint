module flint.config.internal.bind;

import flint.arena : Error, Status;
import flint.config.internal.layers : Layers;
import flint.config.internal.sources : InputValue, Inputs, Origin, keyComponent, maxConfigDepth;
import flint.config.internal.values : coerce;
import flint.config.types : ConfigurationProperties, Default, Env, Required;
import flint.validate : Violation, validate;
import std.algorithm.searching : startsWith;
import std.array : split;
import std.traits : FieldNameTuple;

@safe:

package(flint.config) template configPrefix(T)
{
    static assert(is(T == struct), "configuration requires a struct");
    enum configPrefix = prefixOf!T();
}

private string prefixOf(T)()
{
    string prefix;
    static foreach (attribute; __traits(getAttributes, T))
    {
        static if (is(typeof(attribute) == ConfigurationProperties))
            prefix = attribute.prefix;
    }
    return prefix;
}

private struct FieldRules
{
    string environment;
    string defaultText;
    bool defaulted;
    bool required;
}

private FieldRules rules(T, string name)()
{
    FieldRules result;
    static foreach (attribute; __traits(getAttributes, __traits(getMember, T, name)))
    {
        {
            static if (is(typeof(attribute) == Env))
                result.environment = attribute.name;
            else static if (is(typeof(attribute) == Default))
            {
                result.defaulted = true;
                result.defaultText = attribute.value;
            }
            else static if (is(attribute == Required) || is(typeof(attribute) == Required))
                result.required = true;
        }
    }
    return result;
}

private string defaultEnvironment(string prefix, string key)
{
    char[] normalized;
    foreach (ch; key)
    {
        if (ch == '.')
            normalized ~= "__";
        else if (ch == '-')
            normalized ~= '_';
        else if (ch >= 'a' && ch <= 'z')
            normalized ~= cast(char)(ch - 'a' + 'A');
        else
            normalized ~= ch;
    }
    return prefix ~ normalized.idup;
}

private struct Binding
{
    Layers layers;
    string envPrefix;
    string processScope;
    string[string] envKeys;
    Origin[string] applied;
    string firstKey;
    Error first;

    void problem(Origin origin, Status status, string key, string message)
    {
        if (first.code == Status.ok || key < firstKey)
        {
            firstKey = key;
            first = origin.report(status, key, message);
        }
    }

    void consumeObject(string key)
    {
        if (const input = key in layers.files)
        {
            if (input.text != "{}")
                problem(input.origin, Status.invalidArgument, key, "must be an object");
            layers.files.remove(key);
        }
    }

    void leaf(T, FieldRules attributes)(ref T destination, string key)
    {
        InputValue input;
        bool present = attributes.defaulted;
        if (present)
            input = InputValue(attributes.defaultText, Origin("@Default"));

        const name = attributes.environment.length == 0 ? defaultEnvironment(envPrefix, key) : attributes.environment;
        if (const prior = name in envKeys)
            problem(Origin("schema"), Status.conflict, (*prior < key) ? *prior : key,
                    "has an ambiguous environment variable");
        envKeys[name] = key;

        take(layers.files, key, input, present);
        take(layers.dotenv, name, input, present);
        if (const value = name in layers.process)
        {
            input = InputValue(*value, Origin("process environment"));
            present = true;
            layers.process.remove(name.idup);
        }
        take(layers.arguments, key, input, present);

        if (!present)
        {
            static if (attributes.required)
            {
                if (destination is T.init)
                    problem(Origin("effective configuration"), Status.notFound, key, "is required");
            }
            return;
        }
        if (!coerce(input, destination))
            problem(input.origin, Status.invalidArgument, key, "does not match the field type");
        else
            applied[key] = input.origin;
    }

    private void take(ref Inputs entries, string name, ref InputValue selected, ref bool present)
    {
        if (const value = name in entries)
        {
            selected = *value;
            present = true;
            entries.remove(name);
        }
    }

    void unknown()
    {
        foreach (key, value; layers.files)
            problem(value.origin, Status.invalidArgument, key, "is unknown");
        foreach (key, value; layers.arguments)
            problem(value.origin, Status.invalidArgument, key, "is unknown");
        foreach (key, value; layers.dotenv)
            problem(value.origin, Status.invalidArgument, key, "is unknown");
        foreach (key, value; layers.process)
        {
            if (processScope.length != 0 && key.startsWith(processScope))
                problem(Origin("process environment"), Status.invalidArgument, key, "is unknown");
        }
    }
}

private void walk(T, string prefix, size_t depth)(ref T value, ref Binding binding)
{
    static if (depth > maxConfigDepth)
        binding.problem(Origin("schema"), Status.resourceExhausted, prefix, "exceeds the nesting limit");
    else
    {
        if (prefix.length != 0)
            binding.consumeObject(prefix);
        static foreach (name; FieldNameTuple!T)
        {
            {
                enum fullKey = prefix.length == 0 ? name : prefix ~ "." ~ name;
                alias Field = typeof(__traits(getMember, T.init, name));
                static if (is(Field == struct))
                    walk!(Field, fullKey, depth + 1)(__traits(getMember, value, name), binding);
                else
                {
                    enum metadata = rules!(T, name)();
                    binding.leaf!(Field, metadata)(__traits(getMember, value, name), fullKey);
                }
            }
        }
    }
}

package(flint.config) Error bind(T)(ref T value, ref Layers layers, string envPrefix, bool rejectUnknown)
{
    enum keyPrefix = configPrefix!T;
    if (keyPrefix.length != 0)
    {
        foreach (part; keyPrefix.split("."))
        {
            if (!keyComponent(part))
                return Origin("schema").report(Status.invalidArgument, "", "has an invalid configuration prefix");
        }
    }
    const environmentScope = keyPrefix.length == 0 ? envPrefix : defaultEnvironment(envPrefix, keyPrefix) ~ "__";
    Binding binding = Binding(layers, envPrefix, environmentScope);
    walk!(T, keyPrefix, 1)(value, binding);
    if (rejectUnknown)
        binding.unknown();
    if (binding.first.code != Status.ok)
        return binding.first;
    return check(value, binding.applied);
}

package(flint.config) Error check(T)(scope const ref T value, scope const(Origin[string]) origins = null)
{
    const count = validate(value, null);
    if (count.valid)
        return Error.init;
    auto violations = new Violation[count.total > 4096 ? 4096 : count.total];
    const report = validate(value, violations);
    if (report.written == 0)
        return Origin("validation").report(Status.invalidArgument, "", "did not pass validation");
    auto earliest = violations[0];
    foreach (candidate; violations[1 .. report.written])
    {
        if (candidate.field < earliest.field)
            earliest = candidate;
    }
    enum prefix = configPrefix!T;
    const key = prefix.length == 0 ? earliest.field : prefix ~ "." ~ earliest.field;
    const origin = key in origins;
    return (origin is null ? Origin("validation") : *origin).report(Status.invalidArgument, key,
            "did not pass " ~ earliest.constraint ~ " validation");
}
