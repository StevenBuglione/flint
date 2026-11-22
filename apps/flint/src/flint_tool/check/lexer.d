/// Conservative lexer for policy checks, ported from tools/d_source.py. Not a replacement for the compiler.
///
/// It must agree with the Python lexer token for token, so that `flint check` and tools/gates.py reach the
/// same verdicts. A lexing failure is a policy failure, never a pass.
module flint_tool.check.lexer;

@safe:

/// One policy token: an identifier, a number, a single punctuation byte or `<literal>`.
struct Token
{
    /// Token text, or "<literal>" for any string or character literal.
    string value;
    /// Byte offset of the first byte.
    size_t offset;
    /// One-based line.
    size_t line;
}

/// Why lexing or a structural read failed.
struct LexFailure
{
    /// Message, worded as in tools/d_source.py.
    string message;
    /// One-based line where it was detected.
    size_t line;
}

private bool pythonSpace(char ch) pure nothrow @nogc
{
    // str.isspace() for ASCII, as the Python lexer uses.
    return ch == ' ' || (ch >= '\t' && ch <= '\r') || (ch >= '\x1c' && ch <= '\x1f');
}

private bool identifierStart(char ch) pure nothrow @nogc
{
    return (ch >= 'A' && ch <= 'Z') || (ch >= 'a' && ch <= 'z') || ch == '_';
}

private bool digit(char ch) pure nothrow @nogc
{
    return ch >= '0' && ch <= '9';
}

private bool startsAt(scope const(char)[] source, size_t index, scope const(char)[] text) pure nothrow @nogc
{
    return index + text.length <= source.length && source[index .. index + text.length] == text;
}

/// Tokenize `source`; returns false and sets `failure` on input the policy refuses to interpret.
bool tokenize(string source, out Token[] tokens, out LexFailure failure)
{
    auto lexer = Lexer(source);
    while (lexer.i < source.length)
    {
        if (!lexer.step())
        {
            failure = lexer.failure;
            return false;
        }
    }
    tokens = lexer.tokens;
    return true;
}

private struct Lexer
{
    string source;
    size_t i;
    size_t line = 1;
    Token[] tokens;
    LexFailure failure;

    bool fail(string message, size_t at)
    {
        failure = LexFailure(message, at);
        return false;
    }

    /// Consume one token, comment or run of whitespace.
    bool step()
    {
        const c = source[i];
        if (pythonSpace(c))
        {
            line += c == '\n';
            ++i;
            return true;
        }
        if (startsAt(source, i, "//"))
        {
            while (i < source.length && source[i] != '\n')
                ++i;
            return true;
        }
        if (startsAt(source, i, "/*"))
            return blockComment();
        if (startsAt(source, i, "/+"))
            return nestedComment();
        // Token strings are allowed only inside approved generators. Reject them so unusual string syntax
        // cannot hide a policy violation from this lexer.
        if (startsAt(source, i, "q\"") || startsAt(source, i, "q{"))
            return fail("use checked generator files; token strings require AST review", line);
        if (literalStart())
            return literal();
        word();
        return true;
    }

    bool literalStart() const
    {
        const c = source[i];
        if (c == '"' || c == '\'' || c == '`')
            return true;
        return (c == 'r' || c == 'x') && i + 1 < source.length && source[i + 1] == '"';
    }

    bool blockComment()
    {
        const startLine = line;
        size_t j = i + 2;
        while (j + 1 < source.length && !(source[j] == '*' && source[j + 1] == '/'))
            ++j;
        if (j + 1 >= source.length)
            return fail("unterminated block comment", startLine);
        foreach (ch; source[i .. j + 2])
            line += ch == '\n';
        i = j + 2;
        return true;
    }

    bool nestedComment()
    {
        const startLine = line;
        size_t depth = 1;
        i += 2;
        while (i < source.length && depth)
        {
            if (startsAt(source, i, "/+"))
            {
                ++depth;
                i += 2;
            }
            else if (startsAt(source, i, "+/"))
            {
                --depth;
                i += 2;
            }
            else
            {
                line += source[i] == '\n';
                ++i;
            }
        }
        return depth == 0 || fail("unterminated nested comment", startLine);
    }

    bool literal()
    {
        const start = i;
        const startLine = line;
        const c = source[i];
        const prefixed = c == 'r' || c == 'x';
        const raw = prefixed || c == '`';
        const quote = prefixed ? source[i + 1] : c;
        i += prefixed ? 2 : 1;
        while (i < source.length)
        {
            const ch = source[i];
            line += ch == '\n';
            ++i;
            if (ch == quote)
            {
                tokens ~= Token("<literal>", start, startLine);
                return true;
            }
            if (ch == '\\' && !raw && i < source.length)
            {
                line += source[i] == '\n';
                ++i;
            }
        }
        return fail("unterminated literal", startLine);
    }

    void word()
    {
        const c = source[i];
        size_t j = i + 1;
        if (identifierStart(c))
        {
            while (j < source.length && (identifierStart(source[j]) || digit(source[j])))
                ++j;
        }
        else if (digit(c))
        {
            while (j < source.length && digit(source[j]))
                ++j;
        }
        else if (c >= 0xC0)
        {
            // Python yields one code point; a multi-byte UTF-8 sequence stays one token here too.
            j = i + (c >= 0xF0 ? 4 : c >= 0xE0 ? 3 : 2);
            if (j > source.length)
                j = source.length;
        }
        tokens ~= Token(source[i .. j], i, line);
        i = j;
    }
}

/// Whether `text` is a dotted D module name as tools/d_source.py accepts it.
bool moduleNameShape(scope const(char)[] text) pure nothrow
{
    if (text.length == 0)
        return false;
    bool atStart = true;
    foreach (ch; text)
    {
        if (ch == '.')
        {
            if (atStart)
                return false;
            atStart = true;
            continue;
        }
        if (atStart ? !identifierStart(ch) && ch < 0x80 : !identifierStart(ch) && !digit(ch) && ch < 0x80)
            return false;
        atStart = false;
    }
    return !atStart;
}

/// Imported module names in source order.
bool importedModules(scope const Token[] tokens, out string[] modules, out LexFailure failure)
{
    foreach (i, ref token; tokens)
    {
        if (token.value != "import" || i + 1 >= tokens.length || tokens[i + 1].value == "(")
            continue;
        size_t j = i + 1;
        string[] clause;
        while (j < tokens.length && tokens[j].value != ";")
            clause ~= tokens[j++].value;
        if (j == tokens.length)
        {
            failure = LexFailure("unterminated import", token.line);
            return false;
        }
        if (!clauseModules(clause, token.line, modules, failure))
            return false;
    }
    return true;
}

private bool clauseModules(string[] clause, size_t line, ref string[] modules, out LexFailure failure)
{
    foreach (k, value; clause)
    {
        if (value == ":")
        {
            clause = clause[0 .. k];
            break;
        }
    }
    string[] group;
    foreach (value; clause ~ [","])
    {
        if (value != ",")
        {
            group ~= value;
            continue;
        }
        foreach (k, part; group)
        {
            if (part == "=")
            {
                group = group[k + 1 .. $];
                break;
            }
        }
        string name;
        foreach (part; group)
            name ~= part;
        if (!moduleNameShape(name))
        {
            failure = LexFailure("unsupported import declaration " ~ name, line);
            return false;
        }
        modules ~= name;
        group = null;
    }
    return true;
}

/// The declared module name; the declaration must come first.
bool declaredModule(scope const Token[] tokens, out string name, out LexFailure failure)
{
    if (tokens.length == 0 || tokens[0].value != "module")
    {
        failure = LexFailure("canonical D modules require an explicit module declaration first", 1);
        return false;
    }
    size_t end = 1;
    while (end < tokens.length && tokens[end].value != ";")
        ++end;
    if (end == tokens.length)
    {
        failure = LexFailure("unterminated module declaration", tokens[0].line);
        return false;
    }
    foreach (ref token; tokens[1 .. end])
        name ~= token.value;
    if (!moduleNameShape(name))
    {
        failure = LexFailure("invalid module name", tokens[0].line);
        return false;
    }
    return true;
}

/// The first module default ("safe", "system" or "trusted") before any non-import declaration, or null.
/// A nested `@safe:` or a late declaration cannot satisfy the policy.
string moduleDefault(scope const Token[] tokens)
{
    size_t index;
    while (index < tokens.length && tokens[index].value != ";")
        ++index;
    ++index;
    while (index < tokens.length)
    {
        const attribute = defaultAt(tokens, index);
        if (attribute !is null)
            return attribute;
        const next = afterImport(tokens, index);
        if (next == 0)
            return null;
        index = next;
    }
    return null;
}

private string defaultAt(scope const Token[] tokens, size_t index)
{
    if (index + 2 >= tokens.length || tokens[index].value != "@" || tokens[index + 2].value != ":")
        return null;
    const attribute = tokens[index + 1].value;
    return attribute == "safe" || attribute == "system" || attribute == "trusted" ? attribute : null;
}

/// The index after an import declaration starting at `index` (after protection keywords), or zero.
private size_t afterImport(scope const Token[] tokens, size_t index)
{
    static immutable string[] protections = ["public", "private", "package", "protected", "static"];
    size_t look = index;
    while (look < tokens.length && contains(protections, tokens[look].value))
        ++look;
    if (look + 1 >= tokens.length || tokens[look].value != "import" || tokens[look + 1].value == "(")
        return 0;
    size_t end = look;
    while (end < tokens.length && tokens[end].value != ";")
        ++end;
    return end == tokens.length ? 0 : end + 1;
}

private bool contains(scope const(string)[] list, scope const(char)[] value)
{
    foreach (item; list)
    {
        if (item == value)
            return true;
    }
    return false;
}

/// Whether the tokens contain `mixin(`.
bool hasStringMixin(scope const Token[] tokens)
{
    foreach (i; 1 .. tokens.length)
    {
        if (tokens[i - 1].value == "mixin" && tokens[i].value == "(")
            return true;
    }
    return false;
}

/// One import edge from DMD's -deps output.
struct DependencyEdge
{
    /// Importing module.
    string importing;
    /// Imported module.
    string imported;
}

/// Read DMD -deps output; reject records that cannot be interpreted.
bool compilerDependencyEdges(string text, out DependencyEdge[] edges, out LexFailure failure)
{
    import std.regex : ctRegex, matchFirst;
    import std.string : lineSplitter, strip;

    enum pattern = ctRegex!(
                `^([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*)\s+\(.*?\)\s*:\s*[^:]+\s*:\s*`
                ~ `([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*)\s+\(`);
    size_t number;
    foreach (line; text.lineSplitter)
    {
        ++number;
        if (line.strip.length == 0)
            continue;
        auto match = matchFirst(line, pattern);
        if (match.empty)
        {
            failure = LexFailure("unrecognized DMD dependency record: " ~ (line.length > 160
                    ? line[0 .. 160] : line), number);
            return false;
        }
        edges ~= DependencyEdge(match[1].idup, match[2].idup);
    }
    return true;
}
