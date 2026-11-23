/// Interface keys: a module's tokens without its function bodies (docs/spring/aot-contract.md section 1.2).
///
/// Editing a method body leaves the interface text unchanged, so Flint AOT neither re-extracts nor regenerates
/// anything. Bodies that can feed compile-time evaluation stay in the text: inferred return types, functions named
/// elsewhere in the interface, and function literals inside initializers.
module flint_tool.engine.aot.iface;

import flint_tool.check.lexer : Token;

@safe:

/// A module's interface: its name, the modules it imports and the hashed interface text.
struct ModuleInterface
{
    /// Module name, or empty when the source declares none.
    string name;
    /// Imported module names, as written.
    string[] imports;
    /// SHA-256 of the interface text.
    string hash;
    /// The interface text itself (tokens joined by spaces), kept for tests.
    string text;
}

/// Read a module's interface from its source. False when the source does not lex.
bool readInterface(string source, out ModuleInterface result)
{
    import flint_tool.check.lexer : LexFailure, tokenize;
    import flint_tool.support.files : sha256Hex;

    Token[] tokens;
    LexFailure failure;
    if (!tokenize(source, tokens, failure))
        return false;
    result.name = moduleName(tokens);
    result.imports = importedModules(tokens);
    result.text = interfaceText(source, tokens);
    result.hash = sha256Hex(cast(const(ubyte)[]) result.text);
    return true;
}

/// The declared module name.
string moduleName(scope const Token[] tokens)
{
    if (tokens.length < 2 || tokens[0].value != "module")
        return null;
    string name;
    foreach (ref token; tokens[1 .. $])
    {
        if (token.value == ";")
            break;
        name ~= token.value;
    }
    return name;
}

/// Every module an `import` declaration names, at any nesting.
string[] importedModules(scope const Token[] tokens)
{
    string[] result;
    foreach (index, ref token; tokens)
    {
        // `import(` is a string import; `.import` cannot occur.
        if (token.value != "import" || (index + 1 < tokens.length && tokens[index + 1].value == "("))
            continue;
        importDeclaration(tokens[index + 1 .. $], result);
    }
    return result;
}

/// The modules one import declaration names: `a.b`, `c = d.e`, `f : g, h`.
private void importDeclaration(scope const Token[] tokens, ref string[] result)
{
    import std.algorithm.searching : canFind;

    string current;
    bool afterColon;
    foreach (ref next; tokens)
    {
        const value = next.value;
        if (value == ";" || value == ":" || value == ",")
        {
            if (!afterColon && current.length && !result.canFind(current))
                result ~= current;
            current = null;
            if (value == ";")
                return;
            afterColon = afterColon || value == ":";
        }
        else if (!afterColon)
            current = value == "=" ? null : current ~ value;
    }
}

private bool isAttributeWord(string value)
{
    import std.algorithm.searching : canFind;

    return [
        "const", "immutable", "inout", "shared", "nothrow", "pure", "scope", "return", "ref",
        "override", "final", "static", "abstract", "synchronized", "@"
    ].canFind(value);
}

/// Keywords that start a declaration whose braces hold declarations, not statements.
private bool opensDeclarations(string value)
{
    import std.algorithm.searching : canFind;

    return [
        "struct", "class", "interface", "union", "enum", "template", "mixin", "version", "debug",
        "else", "extern", "align", "deprecated", "pragma", "foreach", "foreach_reverse", "if",
        "private", "public", "protected", "package", "export", "unittest", "static", "invariant"
    ].canFind(value);
}

private enum Brace
{
    declarations,
    body_,
    kept
}

/// The interface text: tokens joined with spaces, function bodies replaced by `{}` unless kept.
string interfaceText(string source, scope const Token[] tokens)
{
    auto kinds = classify(tokens);
    bool[string] named = namesOutsideBodies(tokens, kinds);
    // Keep the body of every function named elsewhere in the interface: CTFE may run it. Repeat, since a kept
    // body names further functions.
    foreach (round; 0 .. 8)
    {
        bool changed;
        foreach (index, ref token; tokens)
        {
            if (token.value != "{" || kinds[index] != Brace.body_)
                continue;
            const name = functionName(tokens, index);
            if (name.length && (name in named) !is null)
            {
                kinds[index] = Brace.kept;
                changed = true;
                foreach (inner; tokens[index .. matching(tokens, index)])
                    named[inner.value] = true;
            }
        }
        if (!changed)
            break;
    }
    string text;
    size_t index;
    while (index < tokens.length)
    {
        if (tokens[index].value == "{" && kinds[index] == Brace.body_)
        {
            text ~= "{} ";
            index = matching(tokens, index) + 1;
            continue;
        }
        if (tokens[index].value == "unittest")
        {
            index = skipUnittest(tokens, index);
            continue;
        }
        text ~= tokenText(source, tokens, index) ~ " ";
        ++index;
    }
    return text;
}

/// The source of a token; literals keep their text, which the lexer abbreviates.
private string tokenText(string source, scope const Token[] tokens, size_t index)
{
    import std.string : stripRight;

    if (tokens[index].value != "<literal>")
        return tokens[index].value;
    const end = index + 1 < tokens.length ? tokens[index + 1].offset : source.length;
    return source[tokens[index].offset .. end].stripRight;
}

private size_t skipUnittest(scope const Token[] tokens, size_t index)
{
    foreach (next; index + 1 .. tokens.length)
    {
        if (tokens[next].value == "{")
            return matching(tokens, next) + 1;
        if (tokens[next].value == ";")
            return next + 1;
    }
    return tokens.length;
}

/// Index of the brace closing the one at `open`, or the last token.
private size_t matching(scope const Token[] tokens, size_t open)
{
    size_t depth;
    size_t last = open;
    foreach (index; open .. tokens.length)
    {
        last = index;
        if (tokens[index].value == "{")
            ++depth;
        else if (tokens[index].value == "}" && --depth == 0)
            return index;
    }
    return last;
}

/// Classify every `{` at declaration level: declarations inside, a function body, or a body to keep.
private Brace[] classify(scope const Token[] tokens)
{
    auto kinds = new Brace[tokens.length];
    classifyRange(tokens, 0, tokens.length, kinds);
    return kinds;
}

private void classifyRange(scope const Token[] tokens, size_t from, size_t to, Brace[] kinds)
{
    size_t start = from;
    size_t index = from;
    int parens;
    while (index < to)
    {
        const value = tokens[index].value;
        if (value == "(" || value == "[")
            ++parens;
        else if (value == ")" || value == "]")
            --parens;
        else if (parens == 0 && (value == ";" || value == "}"))
            start = index + 1;
        else if (parens == 0 && value == ":" && start == index - 1)
            start = index + 1;
        else if (value == "{" && parens == 0)
        {
            const end = matching(tokens, index);
            kinds[index] = braceKind(tokens, start, index);
            if (kinds[index] == Brace.declarations)
                classifyRange(tokens, index + 1, end, kinds);
            index = end + 1;
            start = index;
            continue;
        }
        ++index;
    }
}

/// Whether the declaration tokens contain `=` outside brackets: a function literal there is part of a value.
private bool hasInitializer(scope const Token[] tokens)
{
    int parens;
    foreach (ref token; tokens)
    {
        if (token.value == "(" || token.value == "[")
            ++parens;
        else if (token.value == ")" || token.value == "]")
            --parens;
        else if (parens == 0 && token.value == "=")
            return true;
    }
    return false;
}

/// Whether the token before a `{` closes a function signature.
private bool endsSignature(scope const Token[] tokens, size_t open)
{
    const previous = tokens[open - 1].value;
    return previous == ")" || previous == "do" || isAttributeWord(previous) || (open >= 2 && tokens[open - 2].value
            == "@");
}

/// Whether the declaration's return type is inferred (`auto f()`, `@safe auto f()`).
private bool inferredReturn(scope const Token[] declaration)
{
    const first = declaration[0].value;
    return first == "auto" || (first == "@" && containsWord(declaration, "auto"));
}

/// Whether the declaration is a constructor, destructor or module constructor.
private bool constructor(scope const Token[] tokens, size_t start, size_t open)
{
    return containsWord(tokens[start .. open], "this") && tokens[open - 1].value != "class";
}

/// What the `{` at `open` starts, given the declaration that began at `start`.
private Brace braceKind(scope const Token[] tokens, size_t start, size_t open)
{
    if (start >= open)
        return Brace.declarations;
    const declaration = tokens[start .. open];
    if (hasInitializer(declaration))
        return Brace.kept;
    if (tokens[start].value == "unittest" || constructor(tokens, start, open))
        return Brace.body_;
    // An inferred return type makes the body part of the signature.
    if (inferredReturn(declaration))
        return endsSignature(tokens, open) ? Brace.kept : Brace.declarations;
    if (aggregateKeyword(declaration))
        return Brace.declarations;
    const function_ = looksLikeFunction(tokens, start, open);
    if (opensDeclarations(tokens[start].value) && !function_)
        return Brace.declarations;
    return endsSignature(tokens, open) && function_ ? Brace.body_ : Brace.declarations;
}

private bool containsWord(scope const Token[] tokens, string word)
{
    foreach (ref token; tokens)
    {
        if (token.value == word)
            return true;
    }
    return false;
}

private bool aggregateKeyword(scope const Token[] tokens)
{
    int parens;
    foreach (ref token; tokens)
    {
        if (token.value == "(")
            ++parens;
        else if (token.value == ")")
            --parens;
        else if (parens == 0 && (token.value == "struct" || token.value == "class"
                || token.value == "interface" || token.value == "union" || token.value == "enum"
                || token.value == "template"))
            return true;
    }
    return false;
}

/// An identifier followed by a parameter list, outside `if`, `version`, `debug`, `foreach` and `extern`.
private bool looksLikeFunction(scope const Token[] tokens, size_t start, size_t open)
{
    import std.algorithm.searching : canFind;

    foreach (index; start .. open)
    {
        const value = tokens[index].value;
        if ([
            "if", "version", "debug", "foreach", "foreach_reverse", "extern", "align", "pragma",
            "deprecated"
        ].canFind(value) && index + 1 < open && tokens[index + 1].value == "(")
            return false;
        if (value == "(" && index > start && identifier(tokens[index - 1].value) && (index < 2
                || tokens[index - 2].value != "@") && !isAttributeWord(tokens[index - 1].value))
            return true;
    }
    return false;
}

private bool identifier(string value)
{
    import std.ascii : isAlpha, isAlphaNum;

    if (value.length == 0 || !(isAlpha(value[0]) || value[0] == '_'))
        return false;
    foreach (ch; value)
    {
        if (!(isAlphaNum(ch) || ch == '_'))
            return false;
    }
    return true;
}

/// The name of the function whose body opens at `open`.
private string functionName(scope const Token[] tokens, size_t open)
{
    int depth;
    // Walk back over attributes and the parameter list(s) to the identifier before the first `(`.
    size_t index = open;
    string name;
    while (index > 0)
    {
        --index;
        const value = tokens[index].value;
        if (value == ")")
            ++depth;
        else if (value == "(")
        {
            --depth;
            if (depth == 0 && index > 0 && identifier(tokens[index - 1].value)
                    && !isAttributeWord(tokens[index - 1].value) && (index < 2 || tokens[index - 2].value != "@"))
                name = tokens[index - 1].value;
        }
        else if (depth == 0 && (value == ";" || value == "}" || value == "{"))
            break;
    }
    return name;
}

/// Identifiers that appear in the interface outside function bodies, excluding each function's own name.
private bool[string] namesOutsideBodies(scope const Token[] tokens, scope const Brace[] kinds)
{
    bool[string] seen;
    size_t index;
    while (index < tokens.length)
    {
        if (tokens[index].value == "{" && kinds[index] == Brace.body_)
        {
            index = matching(tokens, index) + 1;
            continue;
        }
        if (identifier(tokens[index].value) && index + 1 < tokens.length && tokens[index + 1].value != "(")
            seen[tokens[index].value] = true;
        else if (identifier(tokens[index].value) && index > 0 && (tokens[index - 1].value == "="
                || tokens[index - 1].value == "(" || tokens[index - 1].value == "!"
                || tokens[index - 1].value == "," || tokens[index - 1].value == "~"))
            seen[tokens[index].value] = true;
        ++index;
    }
    return seen;
}
