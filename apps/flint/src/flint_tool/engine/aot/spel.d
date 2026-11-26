/// SpEL compiled to D (docs/spring/aot-contract.md section 9): Spring Expression Language expressions in
/// annotations become typed D expressions at build time.
///
/// The compiler parses the SpEL subset Spring applications write in annotations, then types each node against
/// what the build knows: literals, the method's parameters and result, the beans by name, and the fields,
/// getters and methods of the model's types. What only the runtime knows (a security root's `hasRole`, a
/// placeholder's value) becomes a call on the generated code's context, whose result is converted where the
/// expression needs it.
module flint_tool.engine.aot.spel;

@safe:

/// A compiled expression: D source and its D type.
struct Compiled
{
    /// D expression.
    string code;
    /// D type: "int", "long", "float", "double", "bool", "string", "null", a model type's name, or "Any" for runtime
    /// values.
    string type;
}

/// What the compiler asks about names; the caller answers from the model and the use site.
interface SpelScope
{
    /// `#name`: a variable (a method parameter, `#result`, `#root`...), or false when unknown.
    bool variable(string name, out Compiled result);
    /// `@name`: a bean, or false when unknown.
    bool bean(string name, out Compiled result);
    /// `${key:default}` inside the expression, as a string.
    Compiled placeholder(string expression);
    /// A function or property of the evaluation root (`hasRole('A')`, `authentication`), or false when the use
    /// site has no root.
    bool root(string name, Compiled[] arguments, bool call, out Compiled result);
    /// A member of a model type: a public field, a getter's property, or a method; false when unknown.
    bool member(string type, string name, Compiled[] arguments, bool call, string target, out Compiled result);
}

/// Why compilation failed (FLINT-E1107).
struct SpelError
{
    /// Message naming the construct.
    string message;
}

/// Compile `source` (without `#{` `}`) in `scope_`.
bool compileSpel(string source, SpelScope scope_, out Compiled result, out SpelError error)
{
    Token[] tokens;
    if (!lex(source, tokens, error))
        return false;
    auto parser = Parser(tokens, scope_);
    result = parser.expression();
    if (parser.error.length == 0 && parser.position < tokens.length)
        parser.error = "unexpected `" ~ tokens[parser.position].text ~ "`";
    if (parser.error.length)
    {
        error = SpelError("SpEL `" ~ source ~ "`: " ~ parser.error);
        return false;
    }
    return true;
}

/// `#{...}` templates, as `@Value` holds them: literal text and expressions concatenated. Returns the parts:
/// even indexes are literal text, odd indexes expression sources.
bool splitTemplate(string text, out string[] parts, out SpelError error)
{
    size_t start;
    size_t index;
    string literal;
    while (index < text.length)
    {
        if (text[index] == '#' && index + 1 < text.length && text[index + 1] == '{')
        {
            const end = closingBrace(text, index + 2);
            if (end == size_t.max)
            {
                error = SpelError("unterminated `#{` in \"" ~ text ~ "\"");
                return false;
            }
            parts ~= literal ~ text[start .. index];
            parts ~= text[index + 2 .. end];
            literal = null;
            index = end + 1;
            start = index;
            continue;
        }
        ++index;
    }
    parts ~= literal ~ text[start .. $];
    return true;
}

private size_t closingBrace(string text, size_t from)
{
    int depth = 1;
    bool quoted;
    foreach (index; from .. text.length)
    {
        const ch = text[index];
        if (ch == '\'')
            quoted = !quoted;
        else if (!quoted && ch == '{')
            ++depth;
        else if (!quoted && ch == '}' && --depth == 0)
            return index;
    }
    return size_t.max;
}

/// Whether a D type is numeric for SpEL.
bool numeric(string type)
{
    import std.algorithm.searching : canFind;

    return [
        "byte", "ubyte", "short", "ushort", "int", "uint", "long", "ulong", "float", "double", "real"
    ].canFind(type);
}

private bool integral(string type)
{
    return numeric(type) && type != "float" && type != "double" && type != "real";
}

/++
Java's binary numeric promotion, which SpEL's operators apply to their operands: `double` if either is (D's `real`
counts as `double`), else `float`, else `long` (D's unsigned and 64-bit types count as `long`), else `int`. So
`int` arithmetic stays `int` and wraps at 32 bits as Java's does (D defines two's complement overflow).
+/
private string promoted(string a, string b)
{
    static bool any(string a, string b, scope const string[] types...)
    {
        foreach (type; types)
            if (a == type || b == type)
                return true;
        return false;
    }

    if (any(a, b, "double", "real"))
        return "double";
    if (any(a, b, "float"))
        return "float";
    if (any(a, b, "long", "ulong", "uint"))
        return "long";
    return "int";
}

/// D code converting `value` to `type`; the generated module may instantiate `std.conv.to`.
string convert(Compiled value, string type)
{
    if (value.type == type)
        return value.code;
    if (value.type == "Any")
        return "(" ~ value.code ~ ").get!(" ~ type ~ ")()";
    if (value.type == "null")
        return "(" ~ type ~ ").init";
    if (numeric(value.type) && numeric(type))
        return "cast(" ~ type ~ ") (" ~ value.code ~ ")";
    return "imported!\"std.conv\".to!(" ~ type ~ ")(" ~ value.code ~ ")";
}

// ---- lexer ----

private enum Kind
{
    number,
    text,
    name,
    symbol
}

private struct Token
{
    Kind kind;
    string text;
}

private bool lex(string source, out Token[] tokens, out SpelError error)
{
    import std.ascii : isAlpha, isDigit, isWhite;

    size_t index;
    while (index < source.length)
    {
        const ch = source[index];
        bool ok = true;
        if (isWhite(ch))
            ++index;
        else if (isDigit(ch))
            tokens ~= lexNumber(source, index);
        else if (ch == '\'' || ch == '"')
            ok = lexString(source, index, tokens, error);
        else if (ch == '$' && index + 1 < source.length && source[index + 1] == '{')
            ok = lexPlaceholder(source, index, tokens, error);
        else if (isAlpha(ch) || ch == '_')
            tokens ~= lexName(source, index);
        else
            ok = lexSymbol(source, index, tokens, error);
        if (!ok)
            return false;
    }
    return true;
}

private Token lexNumber(string source, ref size_t index)
{
    import std.ascii : isAlphaNum, isDigit;

    const start = index;
    while (index < source.length && (isAlphaNum(source[index]) || (source[index] == '.'
            && index + 1 < source.length && isDigit(source[index + 1]))))
        ++index;
    return Token(Kind.number, source[start .. index]);
}

private Token lexName(string source, ref size_t index)
{
    import std.ascii : isAlphaNum;

    const start = index;
    while (index < source.length && (isAlphaNum(source[index]) || source[index] == '_'))
        ++index;
    return Token(Kind.name, source[start .. index]);
}

private bool lexString(string source, ref size_t index, ref Token[] tokens, ref SpelError error)
{
    const quote = source[index++];
    string text;
    while (index < source.length)
    {
        if (source[index] != quote)
        {
            text ~= source[index++];
            continue;
        }
        // A doubled quote is an escaped quote.
        if (index + 1 < source.length && source[index + 1] == quote)
        {
            text ~= quote;
            index += 2;
            continue;
        }
        ++index;
        tokens ~= Token(Kind.text, text);
        return true;
    }
    error = SpelError("unterminated string in `" ~ source ~ "`");
    return false;
}

private bool lexPlaceholder(string source, ref size_t index, ref Token[] tokens, ref SpelError error)
{
    const end = closingBrace(source, index + 2);
    if (end == size_t.max)
    {
        error = SpelError("unterminated `${` in `" ~ source ~ "`");
        return false;
    }
    tokens ~= Token(Kind.symbol, source[index .. end + 1]);
    index = end + 1;
    return true;
}

private bool lexSymbol(string source, ref size_t index, ref Token[] tokens, ref SpelError error)
{
    foreach (symbol; [
        "?.[", ".?[", ".![", "?.", "?:", "==", "!=", "<=", ">=", "&&", "||", "!", "<", ">", "+",
        "-", "*", "/", "%", "^", "?", ":", ".", ",", "(", ")", "[", "]", "#", "@"
    ])
    {
        if (index + symbol.length <= source.length && source[index .. index + symbol.length] == symbol)
        {
            tokens ~= Token(Kind.symbol, symbol);
            index += symbol.length;
            return true;
        }
    }
    error = SpelError("unexpected `" ~ source[index .. index + 1] ~ "` in `" ~ source ~ "`");
    return false;
}

// ---- parser and typer ----

private struct Parser
{
    Token[] tokens;
    SpelScope scope_;
    size_t position;
    string error;

    this(Token[] tokens, SpelScope scope_)
    {
        this.tokens = tokens;
        this.scope_ = scope_;
    }

    bool peek(string text)
    {
        if (position >= tokens.length || tokens[position].kind == Kind.text)
            return false;
        const token = tokens[position].text;
        // Spring matches its textual operators ignoring case (`Ge`, `AND`, `Div`): peekIdentifierToken's
        // equalsIgnoreCase and the tokenizer's upper-cased ALTERNATIVE_OPERATOR_NAMES.
        if (tokens[position].kind == Kind.name && textualOperator(text))
            return token.length == text.length && asciiEqualIgnoringCase(token, text);
        return token == text;
    }

    static bool textualOperator(string text) pure nothrow @nogc
    {
        switch (text)
        {
        case "and", "or", "not", "div", "mod", "eq", "ne", "lt", "le", "gt", "ge":
            return true;
        default:
            return false;
        }
    }

    static bool asciiEqualIgnoringCase(scope const(char)[] a, scope const(char)[] b) pure nothrow @nogc
    {
        foreach (i, c; a)
        {
            const lower = c >= 'A' && c <= 'Z' ? cast(char)(c + 32) : c;
            if (lower != b[i])
                return false;
        }
        return true;
    }

    bool accept(string text)
    {
        if (!peek(text))
            return false;
        ++position;
        return true;
    }

    void fail(string message)
    {
        if (error.length == 0)
            error = message;
    }

    Compiled expression()
    {
        auto condition = or_();
        if (accept("?:"))
        {
            auto fallback = expression();
            return elvis(condition, fallback);
        }
        if (accept("?"))
        {
            auto whenTrue = expression();
            if (!accept(":"))
                fail("`:` missing in a ternary");
            auto whenFalse = expression();
            return ternary(condition, whenTrue, whenFalse);
        }
        return condition;
    }

    Compiled or_()
    {
        auto left = and_();
        while (accept("or") || accept("||"))
            left = Compiled("(" ~ truth(left) ~ " || " ~ truth(and_()) ~ ")", "bool");
        return left;
    }

    Compiled and_()
    {
        auto left = relation();
        while (accept("and") || accept("&&"))
            left = Compiled("(" ~ truth(left) ~ " && " ~ truth(relation()) ~ ")", "bool");
        return left;
    }

    Compiled relation()
    {
        static immutable string[2][] operators = [
            ["==", "=="], ["!=", "!="], ["<=", "<="], [">=", ">="], ["<", "<"], [">", ">"],
            ["eq", "=="], ["ne", "!="], ["le", "<="], ["ge", ">="], ["lt", "<"], ["gt", ">"]
        ];
        auto left = additive();
        foreach (operator; operators)
        {
            if (accept(operator[0]))
                return compare(left, operator[1], additive());
        }
        if (accept("instanceof") || accept("matches") || accept("between"))
            fail("`" ~ tokens[position - 1].text ~ "` is not supported yet");
        return left;
    }

    Compiled additive()
    {
        auto left = multiplicative();
        for (;;)
        {
            if (accept("+"))
                left = add(left, multiplicative());
            else if (accept("-"))
                left = arithmetic(left, "-", multiplicative());
            else
                return left;
        }
    }

    Compiled multiplicative()
    {
        auto left = power();
        for (;;)
        {
            if (accept("*"))
                left = arithmetic(left, "*", power());
            else if (accept("/") || accept("div"))
                left = arithmetic(left, "/", power());
            else if (accept("%") || accept("mod"))
                left = arithmetic(left, "%", power());
            else
                return left;
        }
    }

    Compiled power()
    {
        auto left = unary();
        if (accept("^"))
            return arithmetic(left, "^^", unary());
        return left;
    }

    Compiled unary()
    {
        if (accept("!") || accept("not"))
            return Compiled("!" ~ truth(unary()), "bool");
        if (accept("-"))
        {
            auto operand = numericOf(unary());
            const type = promoted(operand.type, "int");
            return Compiled("(-" ~ convert(operand, type) ~ ")", type);
        }
        if (accept("+"))
            return unary();
        return postfix(primary());
    }

    Compiled primary()
    {
        if (position >= tokens.length)
        {
            fail("the expression ends early");
            return Compiled("null", "null");
        }
        auto token = tokens[position++];
        final switch (token.kind)
        {
        case Kind.number:
            return number(token.text);
        case Kind.text:
            // Spring resolves placeholders before parsing, so '${name}' is the property's text.
            if (token.text.length > 2
                    && imported!"std.algorithm.searching".canFind(token.text, "${"))
                return scope_.placeholder(token.text);
            return Compiled(literal(token.text), "string");
        case Kind.name:
            return name(token.text);
        case Kind.symbol:
            return symbol(token.text);
        }
    }

    Compiled symbol(string text)
    {
        if (text == "(")
        {
            auto inner = expression();
            if (!accept(")"))
                fail("`)` missing");
            return Compiled("(" ~ inner.code ~ ")", inner.type);
        }
        if (text == "#")
            return variable();
        if (text == "@")
            return beanReference();
        if (text.length > 2 && text[0 .. 2] == "${")
            return Compiled(scope_.placeholder(text).code, "placeholder:" ~ scope_.placeholder(text).code);
        fail("unexpected `" ~ text ~ "`");
        return Compiled("null", "null");
    }

    Compiled variable()
    {
        if (position >= tokens.length || tokens[position].kind != Kind.name)
        {
            fail("a variable name must follow `#`");
            return Compiled("null", "null");
        }
        const name = tokens[position++].text;
        Compiled result;
        if (!scope_.variable(name, result))
            fail("unknown variable `#" ~ name ~ "`");
        return result;
    }

    Compiled beanReference()
    {
        if (position >= tokens.length || (tokens[position].kind != Kind.name && tokens[position].kind != Kind.text))
        {
            fail("a bean name must follow `@`");
            return Compiled("null", "null");
        }
        const name = tokens[position++].text;
        Compiled result;
        if (!scope_.bean(name, result))
            fail("no bean named `" ~ name ~ "`");
        return result;
    }

    Compiled name(string text)
    {
        switch (text)
        {
        case "true", "false":
            return Compiled(text, "bool");
        case "null":
            return Compiled("null", "null");
        case "T":
            if (peek("("))
                fail("type references `T(...)` are not supported yet");
            break;
        case "new":
            fail("constructor calls are not supported yet");
            break;
        default:
            break;
        }
        Compiled[] arguments;
        const call = peek("(");
        if (call)
            arguments = argumentList();
        Compiled result;
        if (!scope_.root(text, arguments, call, result))
            fail("unknown " ~ (call ? "function `" ~ text ~ "()`" : "name `" ~ text ~ "`"));
        return result;
    }

    Compiled[] argumentList()
    {
        Compiled[] arguments;
        accept("(");
        if (accept(")"))
            return arguments;
        for (;;)
        {
            arguments ~= expression();
            if (accept(")"))
                return arguments;
            if (!accept(","))
            {
                fail("`,` or `)` expected in an argument list");
                return arguments;
            }
        }
    }

    Compiled postfix(Compiled target)
    {
        for (;;)
        {
            if (error.length)
                return target;
            if (peek(".?[") || peek(".!["))
            {
                fail("collection selection and projection are not supported yet");
                return target;
            }
            const safe = peek("?.");
            if (accept(".") || accept("?."))
                target = memberOf(target, safe);
            else if (accept("["))
            {
                auto key = expression();
                if (!accept("]"))
                    fail("`]` missing");
                target = indexOf(target, key);
            }
            else
                return target;
        }
    }

    Compiled memberOf(Compiled target, bool safe)
    {
        if (position >= tokens.length || tokens[position].kind != Kind.name)
        {
            fail("a property or method name must follow `.`");
            return target;
        }
        const name = tokens[position++].text;
        Compiled[] arguments;
        const call = peek("(");
        if (call)
            arguments = argumentList();
        Compiled result;
        if (builtinMember(target, name, arguments, result))
            return result;
        if (!scope_.member(target.type, name, arguments, call, target.code, result))
        {
            fail("`" ~ target.type ~ "` has no " ~ (call ? "method `" : "property `") ~ name ~ "`");
            return target;
        }
        if (safe)
            return Compiled("(" ~ target.code ~ " is null ? (" ~ result.type ~ ").init : " ~ result.code ~ ")",
                    result.type);
        return result;
    }

    /// Java's String and array members that Spring expressions use.
    bool builtinMember(Compiled target, string name, Compiled[] arguments, out Compiled result)
    {
        const array = target.type.length > 2 && target.type[$ - 2 .. $] == "[]";
        if (target.type != "string" && !array)
            return false;
        if (name == "length" || name == "size")
        {
            // Java's String.length(), array length and Collection.size() are ints.
            result = Compiled("cast(int) (" ~ target.code ~ ").length", "int");
            return true;
        }
        if (name == "isEmpty")
        {
            result = Compiled("((" ~ target.code ~ ").length == 0)", "bool");
            return true;
        }
        return target.type == "string" && stringMethod(target, name, arguments, result);
    }

    bool stringMethod(Compiled target, string name, Compiled[] arguments, out Compiled result)
    {
        static immutable string[2][] unary = [
            ["toUpperCase", "std.uni\".toUpper"], ["toLowerCase", "std.uni\".toLower"],
            ["trim", "std.string\".strip"]
        ];
        foreach (entry; unary)
        {
            if (name == entry[0] && arguments.length == 0)
            {
                result = Compiled("imported!\"" ~ entry[1] ~ "(" ~ target.code ~ ")", "string");
                return true;
            }
        }
        static immutable string[2][] tests = [
            ["startsWith", "startsWith"], ["endsWith", "endsWith"], ["contains", "canFind"]
        ];
        foreach (entry; tests)
        {
            if (name == entry[0] && arguments.length == 1)
            {
                const call = "imported!\"std.algorithm.searching\"." ~ entry[1];
                result = Compiled(call ~ "(" ~ target.code ~ ", " ~ convert(arguments[0], "string") ~ ")", "bool");
                return true;
            }
        }
        return false;
    }

    Compiled indexOf(Compiled target, Compiled key)
    {
        if (target.type.length > 2 && target.type[$ - 2 .. $] == "[]")
            return Compiled("(" ~ target.code ~ ")[cast(size_t) " ~ numericOf(key).code ~ "]", target.type[0 .. $ - 2]);
        if (target.type == "string")
            return Compiled("(" ~ target.code ~ ")[cast(size_t) " ~ numericOf(key).code ~ " .. $][0 .. 1]", "string");
        fail("indexing `" ~ target.type ~ "` is not supported yet");
        return target;
    }

    // ---- typing ----

    /++
    A numeric literal, typed as Spring's tokenizer types it: a real literal has a '.', an exponent or a d/f suffix
    ('f' makes it a float); an integer literal is an int unless it has the 'L' suffix, and an int literal outside the
    int range is an error (SpelMessage.NOT_AN_INTEGER), not a long.
    +/
    Compiled number(string text)
    {
        import std.algorithm.searching : canFind;
        import std.ascii : toLower;

        const hex = text.canFind("0x") || text.canFind("0X");
        const suffix = text.length > 1 ? toLower(text[$ - 1]) : ' ';
        const exponent = !hex && (text.canFind('e') || text.canFind('E'));
        if (!hex && (text.canFind('.') || exponent || suffix == 'd' || suffix == 'f'))
            return realLiteral(suffix == 'd' || suffix == 'f' ? text[0 .. $ - 1] : text, suffix == 'f', exponent);
        if (suffix == 'l')
            return Compiled(text[0 .. $ - 1] ~ "L", "long");
        if (!fitsInt(text, hex))
        {
            fail("the value '" ~ text ~ "' cannot be parsed as an int");
            return Compiled("0", "int");
        }
        return Compiled(text, "int");
    }

    // A real literal's digits, through spelDouble/spelFloat: DMD would otherwise fold an operation on constants at
    // 80-bit precision (0.1 + 0.2 printing 0.3, not Java's 0.30000000000000004).
    static Compiled realLiteral(string digits, bool isFloat, bool exponent)
    {
        import std.algorithm.searching : canFind;

        const whole = digits.canFind('.') || exponent ? digits : digits ~ ".0";
        return isFloat ? Compiled(runtime ~ "spelFloat(" ~ whole ~ "f)", "float") : Compiled(
                runtime ~ "spelDouble(" ~ whole ~ ")", "double");
    }

    // The runtime module that keeps real literals out of constant folding.
    enum runtime = `imported!"flint.engine.aot.expression".`;

    // Whether an integer literal's digits (decimal, or hex after 0x) are within Java's int range, as
    // Integer.parseInt accepts them (radix 16 for hex) in Spring's tokenizer.
    static bool fitsInt(string digits, bool hex)
    {
        static uint digitValue(char c) pure nothrow @nogc
        {
            if (c >= '0' && c <= '9')
                return c - '0';
            if (c >= 'a' && c <= 'f')
                return c - 'a' + 10;
            return c >= 'A' && c <= 'F' ? c - 'A' + 10 : uint.max;
        }

        ulong value;
        const rest = hex ? digits[2 .. $] : digits;
        const base = hex ? 16 : 10;
        foreach (c; rest)
        {
            const d = digitValue(c);
            if (d >= base)
                return false;
            value = value * base + d;
            if (value > int.max)
                return false;
        }
        return rest.length != 0;
    }

    /// Placeholders take the type their use needs: a number beside a number, a string elsewhere.
    Compiled resolved(Compiled value, string type)
    {
        if (value.type.length > 12 && value.type[0 .. 12] == "placeholder:")
        {
            const code = value.type[12 .. $];
            if (type == "string")
                return Compiled(code, "string");
            return Compiled(convert(Compiled(code, "string"), type), type);
        }
        return value;
    }

    Compiled numericOf(Compiled value)
    {
        value = resolved(value, "long");
        if (value.type == "Any")
            return Compiled(convert(value, "long"), "long");
        if (!numeric(value.type))
            fail("`" ~ value.type ~ "` is not a number");
        return value;
    }

    string truth(Compiled value)
    {
        if (value.type == "bool")
            return value.code;
        if (value.type == "Any")
            return convert(value, "bool");
        if (value.type.length > 12 && value.type[0 .. 12] == "placeholder:")
            return "(" ~ value.type[12 .. $] ~ " == \"true\")";
        fail("`" ~ value.type ~ "` is not a boolean");
        return "false";
    }

    Compiled add(Compiled left, Compiled right)
    {
        const leftText = left.type == "string" || right.type == "string";
        if (leftText)
            return Compiled("(" ~ text(left) ~ " ~ " ~ text(right) ~ ")", "string");
        return arithmetic(left, "+", right);
    }

    string text(Compiled value)
    {
        value = resolved(value, "string");
        return value.type == "string" ? value.code : convert(value, "string");
    }

    Compiled arithmetic(Compiled left, string operator, Compiled right)
    {
        auto a = numericOf(resolved(left, resolved(right, "long").type == "double" ? "double" : "long"));
        auto b = numericOf(resolved(right, a.type == "double" ? "double" : "long"));
        // OpPower on integers is Java's (long) Math.pow (spelPowLong: truncation toward zero, saturation); every
        // other operator applies Java's binary numeric promotion.
        if (operator == "^^" && integral(a.type) && integral(b.type))
            return Compiled(runtime ~ "spelPowLong(" ~ convert(a, "long") ~ ", " ~ convert(b, "long") ~ ")", "long");
        const type = promoted(a.type, b.type);
        return Compiled("(" ~ convert(a, type) ~ " " ~ operator ~ " " ~ convert(b, type) ~ ")", type);
    }

    Compiled compare(Compiled left, string operator, Compiled right)
    {
        if (left.type == "null" || right.type == "null")
            return compareNull(left.type == "null" ? right : left, operator, left.type == "null");
        left = resolved(left, right.type);
        right = resolved(right, left.type);
        if (numeric(left.type) || numeric(right.type))
        {
            auto a = numericOf(left);
            auto b = numericOf(right);
            const type = promoted(a.type, b.type);
            return Compiled("(" ~ convert(a, type) ~ " " ~ operator ~ " " ~ convert(b, type) ~ ")", "bool");
        }
        if (left.type == "Any" && right.type != "Any")
            left = Compiled(convert(left, right.type), right.type);
        if (right.type == "Any" && left.type != "Any")
            right = Compiled(convert(right, left.type), left.type);
        const ordering = operator != "==" && operator != "!=";
        if (ordering && left.type != "string")
            fail("`" ~ operator ~ "` compares numbers and strings only");
        // Java's String.compareTo orders by UTF-16 code units, where D's operators compare UTF-8 bytes: a
        // supplementary character (a surrogate pair) sorts before U+E000..U+FFFF in Java.
        if (ordering)
            return Compiled("(" ~ runtime ~ "spelCompareStrings(" ~ left.code ~ ", " ~ right.code ~ ") " ~ operator ~ " 0)",
                    "bool");
        return Compiled("(" ~ left.code ~ " " ~ operator ~ " " ~ right.code ~ ")", "bool");
    }

    /++
    A comparison with the `null` literal. Spring's StandardTypeComparator orders null before every value, and two
    nulls are equal, so an ordering operator's result depends only on whether the other operand is null. That
    operand is still evaluated once (`|| true`, `&& false`), as Spring evaluates both sides.
    +/
    static Compiled compareNull(Compiled value, string operator, bool nullOnLeft)
    {
        if (value.type == "null")
            return Compiled(operator == "==" || operator == "<=" || operator == ">=" ? "true" : "false", "bool");
        // A number or boolean is never null; spelIsNull still evaluates it (D rejects `is null` on it).
        const test = value.type == "Any" ? "(" ~ value.code ~ ").isNull" : numeric(value.type)
            || value.type == "bool" ? runtime ~ "spelIsNull(" ~ value.code ~ ")" : "(" ~ value.code ~ ") is null";
        string code;
        switch (operator)
        {
        case "==":
            code = "(" ~ test ~ ")";
            break;
        case "!=":
            code = "!(" ~ test ~ ")";
            break;
        case "<":
            code = nullOnLeft ? "!(" ~ test ~ ")" : "(" ~ test ~ " && false)";
            break;
        case "<=":
            code = nullOnLeft ? "(" ~ test ~ " || true)" : "(" ~ test ~ ")";
            break;
        case ">":
            code = nullOnLeft ? "(" ~ test ~ " && false)" : "!(" ~ test ~ ")";
            break;
        default: // ">="
            code = nullOnLeft ? "(" ~ test ~ ")" : "(" ~ test ~ " || true)";
            break;
        }
        return Compiled(code, "bool");
    }

    Compiled elvis(Compiled value, Compiled fallback)
    {
        value = resolved(value, fallback.type == "null" ? "string" : fallback.type);
        if (value.type == "string")
            return Compiled("((" ~ value.code ~ ").length ? " ~ value.code ~ " : " ~ text(fallback) ~ ")", "string");
        return Compiled("((" ~ value.code ~ ") is null ? " ~ convert(fallback,
                value.type) ~ " : " ~ value.code ~ ")", value.type);
    }

    Compiled ternary(Compiled condition, Compiled whenTrue, Compiled whenFalse)
    {
        const type = whenTrue.type == whenFalse.type ? whenTrue.type : numeric(whenTrue.type)
            && numeric(whenFalse.type) ? "double" : whenTrue.type == "null" ? whenFalse.type : whenTrue.type;
        return Compiled("(" ~ truth(condition) ~ " ? " ~ convert(resolved(whenTrue, type),
                type) ~ " : " ~ convert(resolved(whenFalse, type), type) ~ ")", type);
    }

    static string literal(string text)
    {
        import flint_tool.engine.aot.conditions : literal;

        return literal(text);
    }
}
