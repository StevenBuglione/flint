/// A Java declaration parser for `flint api extract` (ADR-030, API manifests).
///
/// It reads one compilation unit and returns every type declared in it, with the members a caller outside the
/// package can see. It parses declarations only: method bodies, initializers and enum-constant bodies are skipped by
/// balanced brackets, after a lexer that understands comments, string, character and text-block literals. Java's
/// grammar is regular enough at the declaration level that this recovers the public API without resolving types.
module flint_tool.api.java;

@safe:

/// The kind of a declared type.
enum TypeKind : string
{
    class_ = "class",
    interface_ = "interface",
    enum_ = "enum",
    record = "record",
    annotation = "annotation"
}

/// The kind of a member.
enum MemberKind : string
{
    method = "method",
    constructor = "constructor",
    field = "field",
    constant = "constant",
    attribute = "attribute",
    component = "component"
}

/// One method, constructor, field, enum constant, annotation attribute or record component.
struct Member
{
    /// Kind.
    MemberKind kind;
    /// Simple name; `<init>` for constructors.
    string name;
    /// `public` or `protected`, written or implied.
    string visibility;
    /// Modifiers as written, without visibility and annotations.
    string[] modifiers;
    /// Annotations, normalized: `@Name(args)`.
    string[] annotations;
    /// Generic type parameters: `T extends Comparable<T>`.
    string[] typeParameters;
    /// Return type of a method or attribute, type of a field or component.
    string type;
    /// Parameters, `Type name`, with their annotations.
    string[] parameters;
    /// Declared exceptions.
    string[] throws_;
    /// Default value of an annotation attribute.
    string defaultValue;
    /// Not written in the source: a default constructor, or a record's canonical constructor.
    bool implicit_;

    /// The member part of the element id: `name(Erased,Types)` for methods and constructors, `name` otherwise.
    string signature() const
    {
        if (kind != MemberKind.method && kind != MemberKind.constructor)
            return name;
        string text = name ~ "(";
        foreach (index, parameter; parameters)
            text ~= (index ? "," : "") ~ erasedParameterType(parameter);
        return text ~ ")";
    }
}

/// One declared type, top-level or nested.
struct TypeDecl
{
    /// Package, or empty for the default package.
    string package_;
    /// Name relative to the package: `Outer.Inner` for nested types.
    string name;
    /// Kind.
    TypeKind kind;
    /// `public` or `protected`, written or implied.
    string visibility;
    /// Modifiers as written, without visibility and annotations.
    string[] modifiers;
    /// Annotations, normalized.
    string[] annotations;
    /// Generic type parameters.
    string[] typeParameters;
    /// Superclass (classes) or super-interfaces (interfaces).
    string[] extends_;
    /// Implemented interfaces.
    string[] implements_;
    /// Permitted subclasses of a sealed type.
    string[] permits;
    /// Visible members, in source order.
    Member[] members;

    /// The element id: the canonical Java name.
    string id() const
    {
        return package_.length ? package_ ~ "." ~ name : name;
    }
}

/// The result of parsing one compilation unit.
struct Unit
{
    /// The package declaration.
    string package_;
    /// Every visible type, outer types before their nested types.
    TypeDecl[] types;
    /// Why parsing stopped early, or empty.
    string error;
    /// 1-based line of the error.
    size_t errorLine;
}

/// Parse one Java compilation unit.
Unit parseJava(string source)
{
    Parser parser;
    parser.tokens = lex(source);
    parser.parseUnit();
    return parser.unit;
}

/// The type of a parameter (`final @Nullable Map<K, V>... values` → `Map...`), erased: no annotations, no type
/// arguments, no whitespace.
string erasedParameterType(string parameter)
{
    // The name is the last word; the type is everything before it.
    size_t end = parameter.length;
    while (end > 0 && parameter[end - 1] != ' ')
        end--;
    return eraseType(end ? parameter[0 .. end - 1] : parameter);
}

/// Erase a rendered type: drop annotations, type arguments and whitespace.
string eraseType(string type)
{
    string text;
    size_t depth;
    size_t index;
    while (index < type.length)
    {
        const c = type[index];
        if (c == '@' && depth == 0)
        {
            index = skipAnnotationText(type, index);
            continue;
        }
        if (c == '<')
            depth++;
        else if (c == '>' && depth)
            depth--;
        else if (depth == 0 && c != ' ')
            text ~= c;
        index++;
    }
    return text;
}

private size_t skipAnnotationText(string type, size_t index)
{
    index++;
    while (index < type.length && (isIdentPart(type[index]) || type[index] == '.'))
        index++;
    if (index < type.length && type[index] == '(')
    {
        size_t depth;
        while (index < type.length)
        {
            if (type[index] == '(')
                depth++;
            else if (type[index] == ')' && --depth == 0)
            {
                index++;
                break;
            }
            index++;
        }
    }
    while (index < type.length && type[index] == ' ')
        index++;
    return index;
}

// ---------------------------------------------------------------------------------------------------------------
// Lexer

/// Token classes.
enum Tok : ubyte
{
    word,
    literal,
    punct,
    end
}

/// One token.
struct Token
{
    /// Class.
    Tok tok;
    /// Text; literals keep their quotes.
    string text;
    /// 1-based line.
    size_t line;
}

/// Split Java source into tokens, dropping whitespace and comments. `>` is always one token, so nested type
/// arguments close one by one; `...` and `->` and `::` are single tokens.
Token[] lex(string source)
{
    Token[] tokens;
    size_t index;
    size_t line = 1;
    while (index < source.length)
    {
        if (!skipTrivia(source, index, line))
            tokens ~= nextToken(source, index, line);
    }
    tokens ~= Token(Tok.end, "", line);
    return tokens;
}

/// Skip whitespace or a comment at `index`; false when a token starts there.
private bool skipTrivia(string source, ref size_t index, ref size_t line)
{
    const c = source[index];
    if (isSpace(c))
    {
        line += c == '\n';
        index++;
        return true;
    }
    const next = index + 1 < source.length ? source[index + 1] : '\0';
    if (c != '/' || (next != '/' && next != '*'))
        return false;
    if (next == '/')
    {
        while (index < source.length && source[index] != '\n')
            index++;
    }
    else
        index = skipBlockComment(source, index + 2, line);
    return true;
}

private size_t skipBlockComment(string source, size_t index, ref size_t line)
{
    while (index + 1 < source.length && !(source[index] == '*' && source[index + 1] == '/'))
    {
        line += source[index] == '\n';
        index++;
    }
    return index + 2 <= source.length ? index + 2 : source.length;
}

private bool isSpace(char c) pure nothrow @nogc
{
    return c == ' ' || c == '\n' || c == '\t' || c == '\r' || c == '\f';
}

/// Read the token at `index`.
private Token nextToken(string source, ref size_t index, ref size_t line)
{
    const c = source[index];
    const start = index;
    const startLine = line;
    if (c == '"' || c == '\'')
    {
        index = skipQuoted(source, index, line);
        return Token(Tok.literal, source[start .. index], startLine);
    }
    if (isIdentStart(c))
    {
        while (index < source.length && isIdentPart(source[index]))
            index++;
        return Token(Tok.word, source[start .. index], line);
    }
    if (isDigit(c) || (c == '.' && index + 1 < source.length && isDigit(source[index + 1])))
    {
        index = skipNumber(source, index);
        return Token(Tok.literal, source[start .. index], line);
    }
    size_t width = 1;
    foreach (op; ["...", "->", "::"])
    {
        if (index + op.length <= source.length && source[index .. index + op.length] == op)
        {
            width = op.length;
            break;
        }
    }
    index += width;
    return Token(Tok.punct, source[start .. index], line);
}

private size_t skipQuoted(string source, size_t index, ref size_t line)
{
    const quote = source[index];
    if (quote == '"' && index + 2 < source.length && source[index + 1] == '"' && source[index + 2] == '"')
    {
        // Text block: runs to the next unescaped `"""`.
        index += 3;
        while (index < source.length)
        {
            if (source[index] == '\\')
                index += 2;
            else if (index + 2 < source.length && source[index .. index + 3] == `"""`)
                return index + 3;
            else
            {
                if (source[index] == '\n')
                    line++;
                index++;
            }
        }
        return source.length;
    }
    index++;
    while (index < source.length && source[index] != quote && source[index] != '\n')
        index += source[index] == '\\' ? 2 : 1;
    return index < source.length ? index + 1 : source.length;
}

private size_t skipNumber(string source, size_t index)
{
    const start = index;
    const hex = index + 1 < source.length && source[index] == '0' && (source[index + 1] | 0x20) == 'x';
    while (index < source.length)
    {
        const c = source[index];
        if (isIdentPart(c) || c == '.')
            index++;
        else if ((c == '+' || c == '-') && index > start && (source[index - 1] | 0x20) == (hex ? 'p' : 'e'))
            index++;
        else
            break;
    }
    return index;
}

private bool isIdentStart(char c) pure nothrow @nogc
{
    return c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z' || c == '_' || c == '$' || c >= 0x80;
}

private bool isIdentPart(char c) pure nothrow @nogc
{
    return isIdentStart(c) || isDigit(c);
}

private bool isDigit(char c) pure nothrow @nogc
{
    return c >= '0' && c <= '9';
}

// ---------------------------------------------------------------------------------------------------------------
// Parser

private immutable string[] modifierWords = [
    "public", "protected", "private", "static", "final", "abstract", "default", "synchronized",
    "native", "transient", "volatile", "strictfp", "sealed"
];

private immutable string[] primitiveWords = [
    "boolean", "byte", "char", "short", "int", "long", "float", "double", "void"
];

private struct Modifiers
{
    string[] words;
    string[] annotations;

    bool has(string word) const
    {
        foreach (item; words)
        {
            if (item == word)
                return true;
        }
        return false;
    }

    string visibility() const
    {
        foreach (word; ["public", "protected", "private"])
        {
            if (has(word))
                return word;
        }
        return "";
    }

    string[] others() const
    {
        string[] kept;
        foreach (word; words)
        {
            if (word != "public" && word != "protected" && word != "private")
                kept ~= word;
        }
        return kept;
    }
}

private class ParseError : Exception
{
    size_t line;

    this(string message, size_t line) pure nothrow @safe
    {
        super(message);
        this.line = line;
    }
}

private struct Parser
{
    Token[] tokens;
    size_t at;
    Unit unit;

    ref const(Token) peek(size_t ahead = 0) const return
    {
        // The lexer always ends with an end token, so tokens is never empty.
        if (at + ahead < tokens.length)
            return tokens[at + ahead];
        return tokens[$ - 1];
    }

    bool isAt(string text, size_t ahead = 0) const
    {
        const token = peek(ahead);
        return token.tok != Tok.end && token.tok != Tok.literal && token.text == text;
    }

    bool accept(string text)
    {
        if (!isAt(text))
            return false;
        at++;
        return true;
    }

    void expect(string text)
    {
        if (!accept(text))
            fail("expected `" ~ text ~ "`, found `" ~ peek().text ~ "`");
    }

    string word()
    {
        if (peek().tok != Tok.word)
            fail("expected a name, found `" ~ peek().text ~ "`");
        return tokens[at++].text;
    }

    noreturn fail(string message)
    {
        throw new ParseError(message, peek().line);
    }

    void parseUnit()
    {
        try
        {
            skipAnnotationsBeforePackage();
            if (accept("package"))
            {
                unit.package_ = qualifiedName();
                expect(";");
            }
            while (isAt("import"))
            {
                while (!isAt(";") && peek().tok != Tok.end)
                    at++;
                expect(";");
            }
            while (peek().tok != Tok.end)
            {
                if (accept(";"))
                    continue;
                auto modifiers = parseModifiers();
                if (!startsType())
                    fail("expected a type declaration, found `" ~ peek().text ~ "`");
                parseType(modifiers, null, modifiers.has("public"));
            }
        }
        catch (ParseError error)
        {
            unit.error = error.msg;
            unit.errorLine = error.line;
        }
    }

    // `@NullMarked package x;` appears only in package-info.java, which extract skips; tolerate it anyway.
    void skipAnnotationsBeforePackage()
    {
        const start = at;
        while (isAt("@") && !isAt("interface", 1))
            parseAnnotation();
        if (!isAt("package"))
            at = start;
    }

    string qualifiedName()
    {
        string name = word();
        while (isAt(".") && peek(1).tok == Tok.word)
        {
            at++;
            name ~= "." ~ word();
        }
        return name;
    }

    Modifiers parseModifiers()
    {
        Modifiers modifiers;
        while (true)
        {
            if (isAt("@") && !isAt("interface", 1))
                modifiers.annotations ~= parseAnnotation();
            else if (isAt("non") && isAt("-", 1) && isAt("sealed", 2))
            {
                at += 3;
                modifiers.words ~= "non-sealed";
            }
            else if (peek().tok == Tok.word && isModifierWord(peek().text) && !isAt("(", 1))
                modifiers.words ~= tokens[at++].text;
            else
                return modifiers;
        }
    }

    static bool isModifierWord(string text)
    {
        foreach (word; modifierWords)
        {
            if (word == text)
                return true;
        }
        return false;
    }

    string parseAnnotation()
    {
        expect("@");
        string text = "@" ~ qualifiedName();
        if (isAt("("))
        {
            const start = at;
            skipBalanced("(", ")");
            text ~= render(tokens[start .. at]);
        }
        return text;
    }

    bool startsType() const
    {
        if (isAt("class") || isAt("interface") || isAt("enum"))
            return true;
        if (isAt("@") && isAt("interface", 1))
            return true;
        return isAt("record") && peek(1).tok == Tok.word && (isAt("(", 2) || isAt("<", 2));
    }

    /// Parse a type declaration at its keyword. `visible` says whether it is part of the API.
    void parseType(ref Modifiers modifiers, string outer, bool visible)
    {
        TypeDecl decl;
        if (accept("@"))
        {
            expect("interface");
            decl.kind = TypeKind.annotation;
        }
        else
        {
            const keyword = word();
            decl.kind = keyword == "class" ? TypeKind.class_ : keyword == "interface"
                ? TypeKind.interface_ : keyword == "enum" ? TypeKind.enum_ : TypeKind.record;
        }
        const simple = word();
        decl.package_ = unit.package_;
        decl.name = outer.length ? outer ~ "." ~ simple : simple;
        decl.visibility = modifiers.visibility.length ? modifiers.visibility : "public";
        decl.modifiers = modifiers.others();
        decl.annotations = modifiers.annotations;
        if (isAt("<"))
            decl.typeParameters = parseTypeParameters();
        Member[] components;
        if (decl.kind == TypeKind.record)
            components = parseRecordHeader();
        while (true)
        {
            if (accept("extends"))
                decl.extends_ = typeList();
            else if (accept("implements"))
                decl.implements_ = typeList();
            else if (accept("permits"))
                decl.permits = typeList();
            else
                break;
        }
        const slot = unit.types.length;
        if (visible)
        {
            unit.types ~= decl;
            unit.types[slot].members ~= components;
        }
        expect("{");
        Body body = Body(decl.kind, decl.name, simple, visible);
        if (decl.kind == TypeKind.enum_)
            body.members ~= parseEnumConstants();
        parseBody(body);
        expect("}");
        if (visible)
            unit.types[slot].members ~= implicitConstructors(decl, components, body.constructors) ~ body.members;
    }

    /// The constructors Java declares without source: a class's default constructor, a record's canonical one.
    static Member[] implicitConstructors(ref const TypeDecl decl, const(Member)[] components, const(string)[] declared)
    {
        Member constructor;
        constructor.kind = MemberKind.constructor;
        constructor.name = "<init>";
        constructor.visibility = decl.visibility;
        constructor.implicit_ = true;
        if (decl.kind == TypeKind.class_ && declared.length == 0)
            return [constructor];
        if (decl.kind != TypeKind.record)
            return null;
        foreach (ref component; components)
            constructor.parameters ~= component.type ~ " " ~ component.name;
        foreach (signature; declared)
        {
            if (signature == constructor.signature)
                return null;
            if (signature == "compact")
                constructor.implicit_ = false;
        }
        return [constructor];
    }

    Member[] parseRecordHeader()
    {
        Member[] components;
        expect("(");
        while (!accept(")"))
        {
            const modifiers = parseModifiers();
            Member component;
            component.kind = MemberKind.component;
            component.visibility = "public";
            component.annotations = modifiers.annotations.dup;
            component.type = parseTypeText();
            component.name = word();
            components ~= component;
            if (!isAt(")"))
                expect(",");
        }
        return components;
    }

    Member[] parseEnumConstants()
    {
        Member[] constants;
        while (!isAt(";") && !isAt("}"))
        {
            const modifiers = parseModifiers();
            Member constant;
            constant.kind = MemberKind.constant;
            constant.visibility = "public";
            constant.annotations = modifiers.annotations.dup;
            constant.name = word();
            if (isAt("("))
                skipBalanced("(", ")");
            if (isAt("{"))
                skipBalanced("{", "}");
            constants ~= constant;
            if (!accept(","))
                break;
        }
        accept(";");
        return constants;
    }

    /// What a type body's members are collected into.
    static struct Body
    {
        TypeKind kind;
        string name;
        string simple;
        bool visible;
        Member[] members;
        string[] constructors;
    }

    void parseBody(ref Body body)
    {
        while (!isAt("}"))
        {
            if (peek().tok == Tok.end)
                fail("unterminated body of " ~ body.name);
            if (!skipBodyNoise())
                parseMember(body);
        }
    }

    /// Skip a stray `;` or an instance or static initializer block.
    bool skipBodyNoise()
    {
        if (accept(";"))
            return true;
        if (isAt("static") && isAt("{", 1))
            at++;
        if (!isAt("{"))
            return false;
        skipBalanced("{", "}");
        return true;
    }

    void parseMember(ref Body body)
    {
        auto modifiers = parseModifiers();
        const implicitPublic = body.kind == TypeKind.interface_ || body.kind == TypeKind.annotation;
        const written = modifiers.visibility;
        const visibility = written.length ? written : (implicitPublic ? "public" : "");
        const visible = body.visible && (visibility == "public" || visibility == "protected");
        if (startsType())
            return parseType(modifiers, body.name, visible);
        Member member;
        member.visibility = visibility;
        member.modifiers = modifiers.others();
        member.annotations = modifiers.annotations;
        if (isAt("<"))
            member.typeParameters = parseTypeParameters();
        // A constructor, or the compact canonical constructor of a record.
        if (isAt(body.simple) && (isAt("(", 1) || (body.kind == TypeKind.record && isAt("{", 1))))
            return parseConstructor(body, member, visible);
        member.type = parseTypeText();
        member.name = word();
        if (isAt("("))
            return parseMethod(body, member, visible);
        member.kind = MemberKind.field;
        parseFieldDeclarators(member, visible, body.members);
    }

    void parseConstructor(ref Body body, ref Member member, bool visible)
    {
        at++;
        member.kind = MemberKind.constructor;
        member.name = "<init>";
        const hasParens = isAt("(");
        if (hasParens)
            member.parameters = parseParameters();
        if (accept("throws"))
            member.throws_ = typeList();
        skipBalanced("{", "}");
        body.constructors ~= hasParens ? member.signature : "compact";
        // The compact form (`Name { ... }`) is listed as the record's canonical constructor.
        if (visible && hasParens)
            body.members ~= member;
    }

    void parseMethod(ref Body body, ref Member member, bool visible)
    {
        member.kind = body.kind == TypeKind.annotation ? MemberKind.attribute : MemberKind.method;
        member.parameters = parseParameters();
        while (isAt("[") || isAt("@"))
            member.type ~= parseDims();
        if (accept("throws"))
            member.throws_ = typeList();
        if (accept("default"))
            member.defaultValue = render(skipValue());
        if (isAt("{"))
            skipBalanced("{", "}");
        else
            expect(";");
        if (visible)
            body.members ~= member;
    }

    void parseFieldDeclarators(Member first, bool visible, ref Member[] members)
    {
        auto member = first;
        const baseType = first.type;
        while (true)
        {
            while (isAt("[") || isAt("@"))
                member.type ~= parseDims();
            if (accept("="))
                skipInitializer();
            if (visible)
                members ~= member;
            if (!accept(","))
                break;
            member.type = baseType;
            member.name = word();
        }
        expect(";");
    }

    /// Skip a field initializer up to the `,` that starts the next declarator or the closing `;`.
    void skipInitializer()
    {
        while (true)
        {
            const token = peek();
            if (token.tok == Tok.end)
                fail("unterminated field initializer");
            if (isAt(";"))
                return;
            if (isAt(",") && startsDeclarator(1))
                return;
            if (isAt("("))
                skipBalanced("(", ")");
            else if (isAt("{"))
                skipBalanced("{", "}");
            else if (isAt("["))
                skipBalanced("[", "]");
            else
                at++;
        }
    }

    /// Whether a further field declarator starts `ahead` tokens on: a name that is not a primitive type, then any
    /// `[]` pairs, then `=`, `,` or `;`. `new HashMap<String, byte[]>()` has `, byte[]` followed by `>`, so its
    /// comma does not end the initializer.
    bool startsDeclarator(size_t ahead) const
    {
        if (peek(ahead).tok != Tok.word || isPrimitive(peek(ahead).text))
            return false;
        size_t next = ahead + 1;
        while (isAt("[", next) && isAt("]", next + 1))
            next += 2;
        return isAt("=", next) || isAt(",", next) || isAt(";", next);
    }

    static bool isPrimitive(string word)
    {
        foreach (primitive; primitiveWords)
        {
            if (primitive == word)
                return true;
        }
        return false;
    }

    /// The tokens of an annotation attribute default, up to the `;`.
    const(Token)[] skipValue()
    {
        const start = at;
        while (!isAt(";"))
        {
            if (peek().tok == Tok.end)
                fail("unterminated default value");
            if (isAt("("))
                skipBalanced("(", ")");
            else if (isAt("{"))
                skipBalanced("{", "}");
            else
                at++;
        }
        return tokens[start .. at];
    }

    string[] parseParameters()
    {
        string[] parameters;
        expect("(");
        while (!accept(")"))
        {
            auto modifiers = parseModifiers();
            string text;
            foreach (annotation; modifiers.annotations)
                text ~= annotation ~ " ";
            string type = parseTypeText();
            // Receiver parameter: `Outer Outer.this`.
            if (isAt("this") || (peek().tok == Tok.word && isAt(".", 1) && isAt("this", 2)))
            {
                while (!isAt(",") && !isAt(")"))
                    at++;
                accept(",");
                continue;
            }
            const name = word();
            while (isAt("[") || isAt("@"))
                type ~= parseDims();
            parameters ~= text ~ type ~ " " ~ name;
            if (!isAt(")"))
                expect(",");
        }
        return parameters;
    }

    string[] parseTypeParameters()
    {
        string[] parameters;
        expect("<");
        while (!accept(">"))
        {
            string text;
            while (isAt("@"))
                text ~= parseAnnotation() ~ " ";
            text ~= word();
            if (accept("extends"))
            {
                text ~= " extends " ~ parseTypeText();
                while (accept("&"))
                    text ~= " & " ~ parseTypeText();
            }
            parameters ~= text;
            if (!isAt(">"))
                expect(",");
        }
        return parameters;
    }

    string[] typeList()
    {
        string[] types = [parseTypeText()];
        while (accept(","))
            types ~= parseTypeText();
        return types;
    }

    /// Parse a type and render it canonically: `@A Map<K, List<V>>[]`, `T...`.
    string parseTypeText()
    {
        string text;
        while (isAt("@"))
            text ~= parseAnnotation() ~ " ";
        if (accept("?"))
        {
            text ~= "?";
            if (accept("extends"))
                text ~= " extends " ~ parseTypeText();
            else if (accept("super"))
                text ~= " super " ~ parseTypeText();
            return text;
        }
        text ~= word();
        if (isAt("<"))
            text ~= typeArguments();
        while (isAt(".") && (peek(1).tok == Tok.word || isAt("@", 1)))
        {
            at++;
            text ~= ".";
            while (isAt("@"))
                text ~= parseAnnotation() ~ " ";
            text ~= word();
            if (isAt("<"))
                text ~= typeArguments();
        }
        while (isAt("[") || (isAt("@") && annotatedSuffix() == "["))
            text ~= parseDims();
        if (isAt("@") && annotatedSuffix() == "...")
        {
            while (isAt("@"))
                text ~= " " ~ parseAnnotation();
            text ~= " ";
        }
        if (accept("..."))
            text ~= "...";
        return text;
    }

    // `String @Nullable []` and `Object @Nullable ...`: the token after the annotations.
    string annotatedSuffix()
    {
        const start = at;
        scope (exit)
            at = start;
        while (isAt("@"))
            parseAnnotation();
        return peek().text;
    }

    string parseDims()
    {
        string text;
        while (isAt("@"))
            text ~= " " ~ parseAnnotation() ~ " ";
        expect("[");
        expect("]");
        return text ~ "[]";
    }

    string typeArguments()
    {
        expect("<");
        string text = "<";
        bool first = true;
        while (!accept(">"))
        {
            if (!first)
                expect(",");
            if (isAt(">"))
                continue;
            text ~= (first ? "" : ", ") ~ parseTypeText();
            first = false;
        }
        return text ~ ">";
    }

    void skipBalanced(string open, string close)
    {
        expect(open);
        size_t depth = 1;
        while (depth)
        {
            const token = peek();
            if (token.tok == Tok.end)
                fail("unbalanced `" ~ open ~ "`");
            if (token.tok == Tok.punct)
            {
                if (token.text == open)
                    depth++;
                else if (token.text == close)
                    depth--;
            }
            at++;
        }
    }
}

/// Render tokens with canonical spacing: a space between words, after commas and around `=`.
string render(scope const(Token)[] tokens)
{
    string text;
    foreach (index, ref token; tokens)
    {
        if (index)
        {
            const previous = tokens[index - 1];
            const wordy = previous.tok != Tok.punct && token.tok != Tok.punct;
            if (wordy || previous.text == "," || previous.text == "=" || token.text == "="
                    || previous.text == "->" || token.text == "->")
                text ~= " ";
        }
        text ~= token.text;
    }
    return text;
}
