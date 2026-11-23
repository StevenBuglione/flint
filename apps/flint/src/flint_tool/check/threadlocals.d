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
    "public", "private", "package", "protected", "export", "extern", "align", "deprecated",
    "static", "nothrow", "pure", "override", "final", "abstract", "version", "debug", "else", "if",
    "foreach", "__gshared", "synchronized", "auto", "ref"
];
private immutable string[] globalStorage = ["shared", "__gshared", "immutable", "const", "enum"];
private immutable string[] nonVariables = [
    "import", "module", "alias", "struct", "class", "union", "interface", "template", "mixin",
    "unittest", "invariant", "this", "~", "assert", "version", "debug"
];
private immutable string[] trailingFunction = [
    ")", "nothrow", "pure", "nogc", "safe", "trusted", "system", "property", "const", "scope",
    "return", "inout", "immutable", "shared", "live"
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

/// The index after the attribute starting at `index`, or `index` when none starts there.
private size_t skipAttribute(scope const Token[] tokens, size_t index, ref bool storage) pure nothrow @nogc
{
    const value = tokens[index].value;
    const following = index + 1 < tokens.length ? tokens[index + 1].value : null;
    if (value == "@")
    {
        // @name, @name(...) or @(...).
        size_t next = index + 2;
        if (following == "(")
            return skipGroup(tokens, index + 1, "(", ")");
        if (next < tokens.length && tokens[next].value == "(")
            next = skipGroup(tokens, next, "(", ")");
        return next < tokens.length ? next : tokens.length;
    }
    if (among(globalStorage, value) && following != "(")
    {
        storage = true;
        return index + 1;
    }
    if ((value == "version" || value == "debug") && following == "=")
        return index;
    if (!among(scopeAttributes, value))
        return index;
    return following == "(" ? skipGroup(tokens, index + 1, "(", ")") : index + 1;
}

private Attributes attributes(scope const Token[] tokens) pure nothrow @nogc
{
    Attributes result;
    size_t index;
    while (index < tokens.length)
    {
        const next = skipAttribute(tokens, index, result.storage);
        if (next == index)
            break;
        index = next;
    }
    result.rest = index;
    result.only = index == tokens.length;
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

/// The tokens of `rest` before its top-level `=`.
private const(Token)[] declarationHead(return scope const(Token)[] rest) pure nothrow @nogc
{
    long depth;
    foreach (index, ref token; rest)
    {
        depth += (token.value == "(" || token.value == "[") - (token.value == ")" || token.value == "]");
        if (depth == 0 && token.value == "=")
            return rest[0 .. index];
    }
    return rest;
}

/// Whether `head`, with `stripped` attribute tokens before it and `rest` from the head on, names a variable.
private bool namesVariable(scope const Token[] head, size_t restLength, size_t stripped) pure nothrow @nogc
{
    if (head.length == 0)
        return false;
    // A single name after stripped attributes is an inferred declaration such as `auto cache = [1];`.
    const inferred = head.length == 1 && restLength > 1 && stripped > 0;
    const name = head[$ - 1].value;
    if ((head.length < 2 && !inferred) || among(trailingFunction, name) || !identifier(name))
        return false;
    // const(T) name, immutable(T) name and shared(T) name qualify the variable itself; a pointer or slice
    // suffix after the group leaves the variable mutable.
    return !(among(["const", "immutable", "shared"], head[0].value) && head.length > 1
            && head[1].value == "(" && skipGroup(head, 1, "(", ")") + 1 == head.length);
}

private struct Scanner
{
    const(Token)[] tokens;
    ThreadLocal[] found;
    /// Per open transparent block, whether its own storage class makes its contents global.
    bool[] blocks;
    /// Per open block, whether a storage label such as `__gshared:` covers the rest of it.
    bool[] labelled = [false];
    size_t start;
    size_t index;

    bool globalScope() const pure nothrow @nogc
    {
        foreach (block; blocks)
            if (block)
                return true;
        return labelled[$ - 1];
    }

    void declaration()
    {
        const tokens = this.tokens[start .. index];
        const attrs = attributes(tokens);
        const rest = tokens[attrs.rest .. $];
        if (attrs.storage || globalScope() || rest.length == 0 || among(nonVariables, rest[0].value))
            return;
        const head = declarationHead(rest);
        if (namesVariable(head, rest.length, attrs.rest))
            found ~= ThreadLocal(head[$ - 1].value, head[$ - 1].line);
    }

    /// An attribute label such as `private:` or `__gshared:`. Returns false for any other colon.
    bool label()
    {
        const attrs = attributes(tokens[start .. index]);
        if (index == start || !attrs.only)
            return false;
        if (attrs.storage)
            labelled[$ - 1] = true;
        return true;
    }

    /// Enter a transparent attribute block, or skip an initializer, function, aggregate or template body.
    void openBlock()
    {
        const prefix = tokens[start .. index];
        if (hasTopLevel(prefix, "="))
        {
            index = skipGroup(tokens, index, "{", "}");
            return;
        }
        const attrs = attributes(prefix);
        if (!attrs.only)
        {
            index = skipGroup(tokens, index, "{", "}");
            start = index;
            return;
        }
        blocks ~= attrs.storage;
        labelled ~= labelled[$ - 1];
        start = ++index;
    }

    /// Leave a transparent block. Returns false on an unbalanced brace.
    bool closeBlock()
    {
        if (blocks.length == 0)
            return false;
        blocks = blocks[0 .. $ - 1];
        labelled = labelled[0 .. $ - 1];
        start = ++index;
        return true;
    }

    void run()
    {
        while (index < tokens.length && tokens[index].value != ";")
            ++index;
        start = ++index;
        while (index < tokens.length)
        {
            const value = tokens[index].value;
            if (value == "(" || value == "[")
                index = skipGroup(tokens, index, value, value == "(" ? ")" : "]");
            else if (value == ";")
            {
                declaration();
                start = ++index;
            }
            else if (value == ":" && label())
                start = ++index;
            else if (value == "{")
                openBlock();
            else if (value == "}" && !closeBlock())
                return;
            else if (value != "}")
                ++index;
        }
    }
}

/// Every module-scope variable of a lexed module that is thread-local and mutable.
ThreadLocal[] moduleThreadLocals(scope const Token[] tokens)
{
    auto scanner = Scanner(tokens.dup);
    scanner.run();
    return scanner.found;
}
