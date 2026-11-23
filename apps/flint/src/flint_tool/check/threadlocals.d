/// Module-scope variables that D makes thread-local and mutable (ADR-030 runtime section).
///
/// The scan follows `module_thread_locals` in tools/d_source.py, so `flint check` and the Python gate agree.
/// Declarations inside attribute, version and static-if blocks count as module scope; function, aggregate and
/// template bodies do not. A shared, __gshared, immutable, const or enum storage class makes a variable global.
module flint_tool.check.threadlocals;

import flint_tool.check.lexer : Token;

@safe:

/// One module-scope thread-local mutable variable.
struct ThreadLocal
{
    /// Declared name.
    string name;
    /// One-based line of the name.
    size_t line;
}

private immutable string[] scopeAttributes = [
    "public", "private", "package", "protected", "export", "extern", "align", "deprecated", "static",
    "nothrow", "pure", "override", "final", "abstract", "version", "debug", "else", "if", "foreach",
    "__gshared", "synchronized", "auto", "ref"
];
private immutable string[] globalStorage = ["shared", "__gshared", "immutable", "const", "enum"];
private immutable string[] nonVariables = [
    "import", "module", "alias", "struct", "class", "union", "interface", "template", "mixin", "unittest",
    "invariant", "this", "~", "assert", "version", "debug"
];
private immutable string[] trailingFunction = [
    ")", "nothrow", "pure", "nogc", "safe", "trusted", "system", "property", "const", "scope", "return",
    "inout", "immutable", "shared", "live"
];

private bool among(scope const(string)[] list, scope const(char)[] value) pure nothrow @nogc
{
    foreach (entry; list)
        if (entry == value)
            return true;
    return false;
}

/// The index just past the group that opens at `index`, or `tokens.length` when it never closes.
private size_t skipGroup(scope const Token[] tokens, size_t index, string opening, string closing) pure nothrow @nogc
{
    long depth;
    while (index < tokens.length)
    {
        depth += (tokens[index].value == opening) - (tokens[index].value == closing);
        ++index;
        if (depth == 0)
            return index;
    }
    return tokens.length;
}

private struct Attributes
{
    /// A storage class that makes the declaration global or immutable.
    bool storage;
    /// Index of the first token after the attributes.
    size_t rest;
    /// Every token was an attribute.
    bool only;
}

private Attributes attributes(scope const Token[] tokens) pure nothrow @nogc
{
    Attributes result;
    size_t i;
    while (i < tokens.length)
    {
        const value = tokens[i].value;
        const following = i + 1 < tokens.length ? tokens[i + 1].value : null;
        if (value == "@")
        {
            i += 2;
            if (i < tokens.length && tokens[i].value == "(")
                i = skipGroup(tokens, i, "(", ")");
            else if (i - 1 < tokens.length && tokens[i - 1].value == "(")
                i = skipGroup(tokens, i - 1, "(", ")");
            continue;
        }
        if (among(globalStorage, value) && following != "(")
        {
            result.storage = true;
            ++i;
            continue;
        }
        if ((value == "version" || value == "debug") && following == "=")
            break;
        if (among(scopeAttributes, value))
        {
            ++i;
            if (i < tokens.length && tokens[i].value == "(")
                i = skipGroup(tokens, i, "(", ")");
            continue;
        }
        break;
    }
    result.rest = i < tokens.length ? i : tokens.length;
    result.only = result.rest == tokens.length;
    return result;
}

private bool hasTopLevel(scope const Token[] tokens, string token) pure nothrow @nogc
{
    long depth;
    foreach (ref entry; tokens)
    {
        depth += (entry.value == "(" || entry.value == "[") - (entry.value == ")" || entry.value == "]");
        if (depth == 0 && entry.value == token)
            return true;
    }
    return false;
}

private bool letter(char ch) pure nothrow @nogc
{
    return ch == '_' || (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z');
}

private bool identifier(scope const(char)[] text) pure nothrow @nogc
{
    if (text.length == 0 || !letter(text[0]))
        return false;
    foreach (ch; text)
        if (!letter(ch) && !(ch >= '0' && ch <= '9'))
            return false;
    return true;
}

/// Every module-scope variable of a lexed module that is thread-local and mutable.
ThreadLocal[] moduleThreadLocals(scope const Token[] tokens)
{
    ThreadLocal[] found;
    bool[] blocks;
    bool[] labelled = [false];

    bool anyGlobalBlock()
    {
        foreach (block; blocks)
            if (block)
                return true;
        return false;
    }

    void classify(size_t begin, size_t end)
    {
        const declaration = tokens[begin .. end];
        const attrs = attributes(declaration);
        const rest = declaration[attrs.rest .. $];
        if (attrs.storage || anyGlobalBlock() || labelled[$ - 1] || rest.length == 0
                || among(nonVariables, rest[0].value))
            return;
        size_t headLength;
        long depth;
        foreach (ref token; rest)
        {
            depth += (token.value == "(" || token.value == "[") - (token.value == ")" || token.value == "]");
            if (depth == 0 && token.value == "=")
                break;
            ++headLength;
        }
        const head = rest[0 .. headLength];
        // A single name after stripped attributes is an inferred declaration such as `auto cache = [1];`.
        const inferred = head.length == 1 && rest.length > 1 && rest.length < declaration.length;
        if ((head.length < 2 && !inferred) || head.length == 0 || among(trailingFunction, head[$ - 1].value)
                || !identifier(head[$ - 1].value))
            return;
        // const(T) name, immutable(T) name and shared(T) name qualify the variable itself.
        if (among(["const", "immutable", "shared"], head[0].value) && head.length > 1 && head[1].value == "("
                && skipGroup(head, 1, "(", ")") == head.length - 1)
            return;
        found ~= ThreadLocal(head[$ - 1].value, head[$ - 1].line);
    }

    // Skip the module declaration.
    size_t i;
    while (i < tokens.length && tokens[i].value != ";")
        ++i;
    size_t start = ++i;
    while (i < tokens.length)
    {
        const value = tokens[i].value;
        if (value == "(" || value == "[")
        {
            i = skipGroup(tokens, i, value, value == "(" ? ")" : "]");
            continue;
        }
        if (value == ";")
        {
            classify(start, i);
            start = ++i;
            continue;
        }
        if (value == ":" && i > start)
        {
            const attrs = attributes(tokens[start .. i]);
            if (attrs.only)
            {
                if (attrs.storage)
                    labelled[$ - 1] = true;
                start = ++i;
                continue;
            }
        }
        if (value == "{")
        {
            const attrs = attributes(tokens[start .. i]);
            if (hasTopLevel(tokens[start .. i], "="))
            {
                i = skipGroup(tokens, i, "{", "}");
                continue;
            }
            if (attrs.only)
            {
                blocks ~= attrs.storage;
                labelled ~= labelled[$ - 1];
                start = ++i;
                continue;
            }
            i = skipGroup(tokens, i, "{", "}");
            start = i;
            continue;
        }
        if (value == "}")
        {
            if (blocks.length == 0)
                return found;
            blocks = blocks[0 .. $ - 1];
            labelled = labelled[0 .. $ - 1];
            start = ++i;
            continue;
        }
        ++i;
    }
    return found;
}
