module flint.config.internal.bind;

import flint.arena : Error, Status;
import flint.config.internal.layers : Layers;
import flint.config.internal.sources : InputValue, Inputs, Origin, keyComponent, maxConfigDepth;
import flint.config.internal.values : coerce;
import flint.config.types : ConfigurationProperties, Default, Env, Required;
import flint.validate : Violation, validate;
import std.algorithm.searching : startsWith;
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
    // A multi-type load keeps consumed inputs for later types and records them here instead.
    bool retainInputs;
    string[string] claimedKeys;
    string[string] claimedNames;

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
            consume(layers.files, key, claimedKeys);
        }
    }

    void leaf(T)(ref T destination, string key, FieldRules attributes)
    {
        InputValue input;
        if (!selectInput(attributes, key, input))
        {
            if (attributes.required && destination is T.init)
                problem(Origin("effective configuration"), Status.notFound, key, "is required");
            return;
        }
        if (!coerce(input, destination))
            problem(input.origin, Status.invalidArgument, key, "does not match the field type");
        else
            record(key, input.origin);
    }

    // Kept out of the leaf template so applications do not instantiate the map insertion.
    private void record(string key, Origin origin)
    {
        applied[key] = origin;
    }

    private bool selectInput(FieldRules attributes, string key, out InputValue input)
    {
        bool present = attributes.defaulted;
        if (present)
            input = InputValue(attributes.defaultText, Origin("@Default"));

        string name = attributes.environment.length == 0 ? defaultEnvironment(envPrefix, key) : attributes.environment;
        if (const prior = name in envKeys)
            problem(Origin("schema"), Status.conflict, (*prior < key) ? *prior : key,
                    "has an ambiguous environment variable");
        envKeys[name] = key;

        take(layers.files, key, input, present, claimedKeys);
        take(layers.dotenv, name, input, present, claimedNames);
        if (const value = name in layers.process)
        {
            input = InputValue(*value, Origin("process environment"));
            present = true;
            if (retainInputs)
                claimedNames[name] = null;
            else
                layers.process.remove(name);
        }
        take(layers.arguments, key, input, present, claimedKeys);

        return present;
    }

    private void take(ref Inputs entries, string name, ref InputValue selected, ref bool present,
            ref string[string] claimed)
    {
        if (const value = name in entries)
        {
            selected = *value;
            present = true;
            consume(entries, name, claimed);
        }
    }

    private void consume(ref Inputs entries, string name, ref string[string] claimed)
    {
        if (retainInputs)
            claimed[name] = null;
        else
            entries.remove(name);
    }

    void unknown()
    {
        const string[1] own = [processScope];
        unknown(own[]);
    }

    void unknown(scope const(string)[] scopes)
    {
        foreach (key, value; layers.files)
        {
            if (key !in claimedKeys)
                problem(value.origin, Status.invalidArgument, key, "is unknown");
        }
        foreach (key, value; layers.arguments)
        {
            if (key !in claimedKeys)
                problem(value.origin, Status.invalidArgument, key, "is unknown");
        }
        foreach (key, value; layers.dotenv)
        {
            if (key !in claimedNames)
                problem(value.origin, Status.invalidArgument, key, "is unknown");
        }
        foreach (key, value; layers.process)
        {
            if (key in claimedNames)
                continue;
            foreach (environmentScope; scopes)
            {
                if (environmentScope.length != 0 && key.startsWith(environmentScope))
                {
                    problem(Origin("process environment"), Status.invalidArgument, key, "is unknown");
                    break;
                }
            }
        }
    }

    // Prepare the next type of a multi-type load; problems and claimed inputs accumulate.
    void next(string keyPrefix)
    {
        processScope = environmentScope(envPrefix, keyPrefix);
        envKeys = null;
        applied = null;
    }
}

private string environmentScope(string envPrefix, string keyPrefix)
{
    return keyPrefix.length == 0 ? envPrefix : defaultEnvironment(envPrefix, keyPrefix) ~ "__";
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
                    binding.leaf(__traits(getMember, value, name), fullKey, metadata);
                }
            }
        }
    }
}

private bool validConfigPrefix(string prefix) pure nothrow @nogc
{
    if (prefix.length == 0)
        return true;
    size_t begin;
    foreach (index, ch; prefix)
    {
        if (ch != '.')
            continue;
        if (!keyComponent(prefix[begin .. index]))
            return false;
        begin = index + 1;
    }
    return keyComponent(prefix[begin .. $]);
}

package(flint.config) Error bind(T)(ref T value, ref Layers layers, string envPrefix, bool rejectUnknown)
{
    enum keyPrefix = configPrefix!T;
    enum valid = validConfigPrefix(keyPrefix);
    if (!valid)
        return Origin("schema").report(Status.invalidArgument, "", "has an invalid configuration prefix");
    Binding binding = Binding(layers, envPrefix, environmentScope(envPrefix, keyPrefix));
    walk!(T, keyPrefix, 1)(value, binding);
    if (rejectUnknown)
        binding.unknown();
    if (binding.first.code != Status.ok)
        return binding.first;
    return check(value, binding.applied);
}

/// Bind several types from one snapshot; a key is unknown only when no bound type claims it.
package(flint.config) Error bindAll(T...)(ref Layers layers, bool rejectUnknown, ref T values)
{
    Binding binding = Binding(layers, layers.envPrefix);
    binding.retainInputs = true;
    string[T.length] scopes;
    Origin[string][T.length] applied;
    static foreach (index, Type; T)
    {
        {
            enum keyPrefix = configPrefix!Type;
            enum valid = validConfigPrefix(keyPrefix);
            if (!valid)
                return Origin("schema").report(Status.invalidArgument, "", "has an invalid configuration prefix");
            binding.next(keyPrefix);
            walk!(Type, keyPrefix, 1)(values[index], binding);
            scopes[index] = binding.processScope;
            applied[index] = binding.applied;
        }
    }
    if (rejectUnknown)
        binding.unknown(scopes[]);
    if (binding.first.code != Status.ok)
        return binding.first;
    static foreach (index; 0 .. T.length)
    {
        {
            const invalid = check(values[index], applied[index]);
            if (invalid.code != Status.ok)
                return invalid;
        }
    }
    return Error.init;
}

package(flint.config) Error check(T)(scope const ref T value, scope const(Origin[string]) origins = null)
{
    const count = validate(value, null);
    if (count.valid)
        return Error.init;
    auto violations = violationBuffer(count.total);
    const report = validate(value, violations);
    return earliestViolation(violations[0 .. report.written], configPrefix!T, origins);
}

// The type-independent parts of check stay out of each application's instantiation.
private Violation[] violationBuffer(size_t total)
{
    return new Violation[total > 4096 ? 4096 : total];
}

private Error earliestViolation(scope const(Violation)[] violations, string prefix, scope const(Origin[string]) origins)
{
    if (violations.length == 0)
        return Origin("validation").report(Status.invalidArgument, "", "did not pass validation");
    size_t first;
    foreach (index, ref candidate; violations)
    {
        if (candidate.field < violations[first].field)
            first = index;
    }
    const earliest = violations[first];
    const key = prefix.length == 0 ? earliest.field : prefix ~ "." ~ earliest.field;
    const origin = key in origins;
    return (origin is null ? Origin("validation") : *origin).report(Status.invalidArgument, key,
            "did not pass " ~ earliest.constraint ~ " validation");
}
