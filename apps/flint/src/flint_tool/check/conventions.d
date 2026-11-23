/// Application conventions that `flint check` and every build enforce (ADR-028 sections 3 and 5).
///
/// - FLINT-E0530: a field of class or interface type that some constructor of its aggregate leaves unassigned may
///   be null. Constructor injection assigns it; a value that needs no identity belongs in a struct.
/// - FLINT-E0531: an attribute on a REST handler that the framework makes unneeded: `nothrow` or `@nogc` on a
///   controller that runs on a worker thread anyway, because another of its handlers is not both, and `scope` on
///   a parameter the framework passes as an owned value.
///
/// The rules read tokens, not types: a class is one the project declares.
module flint_tool.check.conventions;

import flint_tool.check.lexer : Token;
import flint_tool.diagnostics.report : Report;

@safe:

/// Handler counts for the attributes-per-handler metric.
struct HandlerMetric
{
    /// Route handlers found.
    long handlers;
    /// `nothrow`, `@nogc`, `scope`, `pure`, `return` and `@trusted` on them and their parameters.
    long attributes;
}

/// Names of the classes and interfaces declared in `tokens`.
string[] declaredClasses(scope const Token[] tokens)
{
    string[] names;
    foreach (index, ref token; tokens)
    {
        if ((token.value == "class" || token.value == "interface") && index + 1 < tokens.length
                && identifier(tokens[index + 1].value))
            names ~= tokens[index + 1].value;
    }
    return names;
}

/// FLINT-E0530 over one file.
void checkNullableFields(string file, string text, scope const Token[] tokens,
        scope const bool[string] classes, ref Report report)
{
    foreach (ref aggregate; aggregates(tokens))
    {
        foreach (ref field; aggregate.fields)
        {
            if ((field.type in classes) is null || field.initialized)
                continue;
            bool assigned = aggregate.constructors.length != 0;
            foreach (ref constructor; aggregate.constructors)
                assigned = assigned && assigns(tokens[constructor.begin .. constructor.end], field.name);
            if (!assigned)
                report.add(fieldDiagnostic(file, text, field, aggregate.name));
        }
    }
}

/// FLINT-E0531 over one file, adding its handlers to `metric`.
void checkHandlerAttributes(string file, string text, scope const Token[] tokens,
        ref HandlerMetric metric, ref Report report)
{
    foreach (ref aggregate; aggregates(tokens))
    {
        if (!aggregate.controller)
            continue;
        bool allReactor = true;
        foreach (ref handler; aggregate.handlers)
            allReactor = allReactor && handler.nothrow_ && handler.nogc;
        foreach (ref handler; aggregate.handlers)
        {
            metric.handlers++;
            metric.attributes += handler.attributes;
            if (!allReactor && (handler.nothrow_ || handler.nogc))
                report.add(attributeDiagnostic(file, text,
                        handler.line, aggregate.name ~ "." ~ handler.name,
                        "`nothrow`/`@nogc` changes nothing here: another handler of "
                        ~ aggregate.name ~ " may throw or allocate, so the controller runs on a worker thread",
                        "remove them, or make every handler of the controller nothrow @nogc to run it on the reactor"));
            foreach (line; handler.scopedValues)
                report.add(attributeDiagnostic(file, text, line, aggregate.name ~ "." ~ handler.name,
                        "`scope` is unneeded: the framework passes this argument as an owned value",
                        "remove `scope`; keep it only on `ref scope RequestContext`"));
        }
    }
}

private struct Field
{
    string type;
    string name;
    size_t line;
    bool initialized;
}

private struct Range
{
    size_t begin;
    size_t end;
}

private struct Handler
{
    string name;
    size_t line;
    bool nothrow_;
    bool nogc;
    long attributes;
    size_t[] scopedValues;
}

private struct Aggregate
{
    string name;
    bool controller;
    Field[] fields;
    Range[] constructors;
    Handler[] handlers;
}

private bool identifier(string value) pure
{
    import std.ascii : isAlpha;

    return value.length && (isAlpha(value[0]) || value[0] == '_');
}

private Aggregate[] aggregates(scope const Token[] tokens)
{
    Aggregate[] found;
    foreach (index, ref token; tokens)
    {
        if ((token.value != "struct" && token.value != "class") || index + 1 >= tokens.length
                || !identifier(tokens[index + 1].value))
            continue;
        size_t open = index + 2;
        while (open < tokens.length && tokens[open].value != "{" && tokens[open].value != ";")
            open++;
        if (open >= tokens.length || tokens[open].value == ";")
            continue;
        const close = matching(tokens, open);
        Aggregate aggregate;
        aggregate.name = tokens[index + 1].value;
        aggregate.controller = annotatedBefore(tokens, index, "RestController");
        readMembers(tokens, open + 1, close, aggregate);
        found ~= aggregate;
    }
    return found;
}

private size_t matching(scope const Token[] tokens, size_t open)
{
    const opener = tokens[open].value;
    const closer = opener == "{" ? "}" : opener == "(" ? ")" : "]";
    size_t depth;
    foreach (index; open .. tokens.length)
    {
        if (tokens[index].value == opener)
            depth++;
        else if (tokens[index].value == closer && --depth == 0)
            return index;
    }
    return tokens.length;
}

// Whether `@name` appears among the attributes before the declaration starting at `index`.
private bool annotatedBefore(scope const Token[] tokens, size_t index, string name)
{
    size_t position = index;
    while (position > 0)
    {
        const previous = tokens[position - 1].value;
        if (previous == ";" || previous == "{" || previous == "}")
            break;
        position--;
        if (previous == name && position > 0 && tokens[position - 1].value == "@")
            return true;
    }
    return false;
}

private void readMembers(scope const Token[] tokens, size_t begin, size_t end, ref Aggregate aggregate)
{
    size_t start = begin;
    size_t index = begin;
    while (index < end)
    {
        const value = tokens[index].value;
        if (value == "{")
        {
            const close = matching(tokens, index);
            member(tokens, start, index, close, aggregate);
            index = close + 1;
            start = index;
        }
        else if (value == ";")
        {
            member(tokens, start, index, index, aggregate);
            start = ++index;
        }
        else if (value == "(" || value == "[")
            index = matching(tokens, index) + 1;
        else
            index++;
    }
}

private void member(scope const Token[] tokens, size_t start, size_t head, size_t bodyEnd, ref Aggregate aggregate)
{
    if (start >= head)
        return;
    // A constructor: `this(...)` other than the postblit `this(this)`.
    foreach (index; start .. head)
    {
        if (tokens[index].value == "this" && index + 1 < head && tokens[index + 1].value == "("
                && !(index + 2 < head && tokens[index + 2].value == "this"))
        {
            if (bodyEnd > head)
                aggregate.constructors ~= Range(head, bodyEnd);
            return;
        }
    }
    const open = parameterOpen(tokens, start, head);
    if (open < head)
    {
        if (bodyEnd > head && hasRoute(tokens, start, open))
            aggregate.handlers ~= handler(tokens, start, open, head);
        return;
    }
    if (bodyEnd != head)
        return;
    field(tokens, start, head, aggregate);
}

// The parameter list's `(`, skipping a UDA's arguments (`@Get("/")`) and template arguments (`!(...)`); `head`
// when the declaration has none.
private size_t parameterOpen(scope const Token[] tokens, size_t start, size_t head)
{
    size_t index = start;
    while (index < head)
    {
        if (tokens[index].value != "(")
        {
            index++;
            continue;
        }
        const uda = index >= start + 2 && identifier(tokens[index - 1].value) && tokens[index - 2].value == "@";
        if (!uda && index > start && tokens[index - 1].value != "!")
            return index;
        index = matching(tokens, index) + 1;
    }
    return head;
}

private bool hasRoute(scope const Token[] tokens, size_t start, size_t open)
{
    foreach (index; start + 1 .. open)
    {
        if (tokens[index - 1].value == "@")
        {
            switch (tokens[index].value)
            {
            case "Get":
            case "Post":
            case "Put":
            case "Delete":
            case "RequestMapping":
                return true;
            default:
                break;
            }
        }
    }
    return false;
}

private Handler handler(scope const Token[] tokens, size_t start, size_t open, size_t head)
{
    Handler result;
    result.name = tokens[open - 1].value;
    result.line = tokens[open - 1].line;
    const close = matching(tokens, open);
    foreach (index; start .. head)
    {
        if (index <= open || index >= close)
            signatureAttribute(tokens, index, result);
    }
    parameters(tokens, open, close, result);
    return result;
}

// Count one token of the handler's own attributes.
private void signatureAttribute(scope const Token[] tokens, size_t index, ref Handler result)
{
    const value = tokens[index].value;
    const attribute = index > 0 && tokens[index - 1].value == "@";
    const nogc = attribute && value == "nogc";
    if (value == "nothrow" || nogc || value == "pure" || (attribute && value == "trusted")
            || value == "return" || value == "scope")
        result.attributes++;
    result.nothrow_ = result.nothrow_ || value == "nothrow";
    result.nogc = result.nogc || nogc;
}

// Parameters, split at commas outside nested parentheses (a UDA's arguments).
private void parameters(scope const Token[] tokens, size_t open, size_t close, ref Handler result)
{
    size_t parameter = open + 1;
    size_t depth;
    foreach (index; open + 1 .. close + 1)
    {
        const value = index < close ? tokens[index].value : ",";
        if (value == "(" || value == "[")
            depth++;
        else if (value == ")" || value == "]")
            depth--;
        else if (value == "," && depth == 0)
        {
            parameterAttributes(tokens[parameter .. index], result);
            parameter = index + 1;
        }
    }
}

private void parameterAttributes(scope const Token[] parameter, ref Handler result)
{
    bool scoped;
    bool framework;
    size_t line;
    foreach (ref token; parameter)
    {
        if (token.value == "scope")
        {
            scoped = true;
            line = token.line;
            result.attributes++;
        }
        else if (token.value == "return" || token.value == "nothrow")
            result.attributes++;
        framework = framework || token.value == "RequestContext" || token.value == "Request"
            || token.value == "RequestArena";
    }
    if (scoped && !framework)
        result.scopedValues ~= line;
}

private void field(scope const Token[] tokens, size_t start, size_t end, ref Aggregate aggregate)
{
    // `[attributes] Type name [= initializer];`.
    size_t equals;
    if (!declarationShape(tokens, start, end, equals) || equals < start + 2)
        return;
    const name = tokens[equals - 1].value;
    const type = tokens[equals - 2].value;
    if (!identifier(name) || !identifier(type))
        return;
    // `= null` leaves the field null.
    const initialized = equals != end && !(equals + 1 < end && tokens[equals + 1].value == "null");
    aggregate.fields ~= Field(type, name, tokens[equals - 1].line, initialized);
}

// Whether tokens look like a field rather than an alias, enum, import, static or mixin member, or a function
// pointer; `equals` is the initializer's `=`, or `end`.
private bool declarationShape(scope const Token[] tokens, size_t start, size_t end, out size_t equals)
{
    equals = end;
    size_t index = start;
    while (index < end)
    {
        const value = tokens[index].value;
        if (value == "alias" || value == "enum" || value == "import" || value == "static" || value == "mixin")
            return false;
        if (value == "(")
        {
            // Only a UDA's arguments may have parentheses before the name.
            if (!(index >= start + 2 && tokens[index - 2].value == "@"))
                return false;
            index = matching(tokens, index) + 1;
            continue;
        }
        if (value == "=" && equals == end)
            equals = index;
        index++;
    }
    return true;
}

// Whether a constructor body assigns `name`: `name = ...` or `this.name = ...`, not `==`.
private bool assigns(scope const Token[] body, string name)
{
    foreach (index, ref token; body)
    {
        if (token.value != name || index + 1 >= body.length || body[index + 1].value != "=")
            continue;
        if (index + 2 < body.length && body[index + 2].value == "=")
            continue;
        if (index > 0 && body[index - 1].value == "." && !(index > 1 && body[index - 2].value == "this"))
            continue;
        return true;
    }
    return false;
}

private imported!"flint_tool.diagnostics.report".Diagnostic fieldDiagnostic(string file, string text,
        const ref Field field, string owner)
{
    import flint_tool.diagnostics.report : Severity, at, diagnostic;

    return at(diagnostic("FLINT-E0530", Severity.error,
            "field `" ~ field.name ~ "` of class type `" ~ field.type ~ "` in " ~ owner ~ " may be null",
            "assign it in every constructor (constructor injection), or hold a " ~ "struct instead of a class"),
            file, field.line, 0, text);
}

private imported!"flint_tool.diagnostics.report".Diagnostic attributeDiagnostic(string file,
        string text, size_t line, string handler, string message, string fix)
{
    import flint_tool.diagnostics.report : Severity, at, diagnostic;

    return at(diagnostic("FLINT-E0531", Severity.error, handler ~ ": " ~ message, fix), file, line, 0, text);
}

unittest
{
    import flint_tool.check.lexer : LexFailure, tokenize;

    Token[] tokens;
    LexFailure failure;
    const source = "" ~ "@Service final class Greeter { string text; }\n" ~ "@Service final class Clock { }\n"
        ~ "@RestController(\"/a\") struct Injected\n" ~ "{\n" ~ "private Greeter greeter;\n"
        ~ "private Clock clock = null;\n" ~ "this(Greeter greeter) { this.greeter = greeter; }\n"
        ~ "@Get(\"/:id\") Result!string get(@PathVariable(\"id\") scope string id) nothrow @nogc { return x; }\n"
        ~ "@Post(\"\") Result!string post(ref scope RequestContext context) { return x; }\n"
        ~ "}\n" ~ "final class Lazy { Greeter later; Clock clock; this() { clock = new Clock; } }\n"
        ~ "struct Plain { Greeter greeter; }\n";
    assert(tokenize(source, tokens, failure));
    bool[string] classes;
    foreach (name; declaredClasses(tokens))
        classes[name] = true;
    assert("Greeter" in classes && "Clock" in classes && "Lazy" in classes);
    Report report;
    checkNullableFields("a.d", "", tokens, classes, report);
    string[] flagged;
    foreach (ref item; report.items)
        flagged ~= item.message;
    assert(flagged.length == 3, flagged[0]);
    assert(flagged[0] == "field `clock` of class type `Clock` in Injected may be null", flagged[0]);
    assert(flagged[1] == "field `later` of class type `Greeter` in Lazy may be null", flagged[1]);
    assert(flagged[2] == "field `greeter` of class type `Greeter` in Plain may be null", flagged[2]);

    Report attributes;
    HandlerMetric metric;
    checkHandlerAttributes("a.d", "", tokens, metric, attributes);
    assert(metric.handlers == 2 && metric.attributes == 4);
    string seen;
    foreach (ref item; attributes.items)
        seen ~= item.message ~ " | ";
    assert(attributes.items.length == 2, seen);
    assert(attributes.items[0].message == "Injected.get: `nothrow`/`@nogc` changes nothing here: another handler of "
            ~ "Injected may throw or allocate, so the controller runs on a worker thread");
    assert(attributes.items[1].message
            == "Injected.get: `scope` is unneeded: the framework passes this argument " ~ "as an owned value");
}
