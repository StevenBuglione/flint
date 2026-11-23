/++
Interim port of spring-core's `MimeType`, `MimeTypeUtils` and `InvalidMimeTypeException`, which
`flint.http.MediaType` builds on. It belongs to framework-core's `flint.util` and moves there (or is
replaced by theirs) when `flint:core` lands; the web packages depend only on these Spring names.

Ported from spring-projects/spring-framework v7.1.0, spring-core/src/main/java/org/springframework/util/
(MimeType.java, MimeTypeUtils.java, InvalidMimeTypeException.java).
Copyright 2002-present the original author or authors.
Licensed under the Apache License, Version 2.0 (https://www.apache.org/licenses/LICENSE-2.0).
Modified by the Flint authors: translated to D under the rulebook (docs/spring/api-mapping.md). `MimeType`
is a struct (ADR-030 section 5); its parameter map is an insertion-ordered, case-insensitive view.
+/
module flint.util;

import flint.java.lang : IllegalArgumentException;
import flint.java.nio.charset : Charset, UnsupportedCharsetException;

@safe:

/// One `name=value` parameter of a MIME type, as given (values keep their quotes).
struct MimeTypeParameter
{
    string key; ///
    string value; ///
}

/++
A read-only, insertion-ordered map of MIME type parameters whose keys compare ignoring ASCII case, as
Spring's `LinkedCaseInsensitiveMap` (R10: stands in for `Map<String, String>` until `flint.java.util.Map`).
+/
struct MimeTypeParameters
{
    private const(MimeTypeParameter)[] entries;

    /// Number of parameters.
    int size() const pure nothrow @nogc
    {
        return cast(int) entries.length;
    }

    /// Whether there are none.
    bool isEmpty() const pure nothrow @nogc
    {
        return entries.length == 0;
    }

    /// The value for `key`, ignoring case, or `null`.
    string get(scope const(char)[] key) const pure nothrow @nogc
    {
        foreach (ref entry; entries)
            if (equalsIgnoreCase(entry.key, key))
                return entry.value;
        return null;
    }

    /// Whether `key` is present, ignoring case.
    bool containsKey(scope const(char)[] key) const pure nothrow @nogc
    {
        foreach (ref entry; entries)
            if (equalsIgnoreCase(entry.key, key))
                return true;
        return false;
    }

    /// The keys in insertion order.
    string[] keySet() const pure nothrow
    {
        auto keys = new string[entries.length];
        foreach (i, ref entry; entries)
            keys[i] = entry.key;
        return keys;
    }

    /// The parameters in insertion order.
    const(MimeTypeParameter)[] entrySet() const pure nothrow @nogc
    {
        return entries;
    }

    /// `foreach (key, value; parameters)`.
    int opApply(scope int delegate(string, string) pure @safe dg) const pure
    {
        foreach (ref entry; entries)
            if (auto result = dg(entry.key, entry.value))
                return result;
        return 0;
    }

    /// ditto
    int opApply(scope int delegate(string, string) @safe dg) const
    {
        foreach (ref entry; entries)
            if (auto result = dg(entry.key, entry.value))
                return result;
        return 0;
    }
}

/++
A MIME type (RFC 2046), with type, subtype and parameters.

Constructors check every token and parameter as Spring's do and throw `IllegalArgumentException` (or, from
`valueOf`, `InvalidMimeTypeException`).
+/
struct MimeType
{
    package(flint) enum string WILDCARD_TYPE = "*";
    private enum string PARAM_CHARSET = "charset";

    private string mimeType;
    private string mimeSubtype;
    private const(MimeTypeParameter)[] parameterList;
    private Charset resolvedCharset;

    /// `type/*`.
    this(string type) pure
    {
        this(type, WILDCARD_TYPE);
    }

    /// `type/subtype` with no parameters.
    this(string type, string subtype) pure
    {
        this(type, subtype, cast(const(MimeTypeParameter)[]) null);
    }

    /// `type/subtype;charset=<charset>`.
    this(string type, string subtype, Charset charset) pure
    {
        this(type, subtype, [MimeTypeParameter(PARAM_CHARSET, charset.name())]);
    }

    /// `type/subtype` with `parameters`, checked and stored in order.
    this(string type, string subtype, scope const(MimeTypeParameter)[] parameters) pure
    {
        hasLength(type, "'type' must not be empty");
        hasLength(subtype, "'subtype' must not be empty");
        checkToken(type);
        checkToken(subtype);
        mimeType = toLowerAscii(type);
        mimeSubtype = toLowerAscii(subtype);
        parameterList = createParametersMap(parameters);
        resolveCharset();
    }

    /// A copy of `other` with its charset parameter set to `charset`.
    this(MimeType other, Charset charset) pure
    {
        mimeType = other.mimeType;
        mimeSubtype = other.mimeSubtype;
        auto map = other.parameterList.dup;
        put(map, MimeTypeParameter(PARAM_CHARSET, charset.name()));
        parameterList = map;
        resolvedCharset = charset;
    }

    /// A copy of `other`'s type and subtype with `parameters`.
    this(MimeType other, scope const(MimeTypeParameter)[] parameters) pure
    {
        mimeType = other.mimeType;
        mimeSubtype = other.mimeSubtype;
        parameterList = createParametersMap(parameters);
        resolveCharset();
    }

    private void resolveCharset() pure
    {
        const charset = parameters().get(PARAM_CHARSET);
        if (charset !is null)
            resolvedCharset = Charset.forName(unquote(charset));
    }

    private static void checkToken(scope const(char)[] token) pure
    {
        foreach (ch; token)
        {
            if (!isTokenChar(ch))
                throw new IllegalArgumentException("Invalid token character '" ~ ch ~ "' in token \"" ~ token.idup
                        ~ "\"");
        }
    }

    private const(MimeTypeParameter)[] createParametersMap(scope const(MimeTypeParameter)[] parameters) pure
    {
        if (parameters.length == 0)
            return null;
        MimeTypeParameter[] map;
        foreach (ref parameter; parameters)
        {
            checkParameters(parameter.key, parameter.value);
            put(map, parameter);
        }
        return map;
    }

    /// Spring's protected `checkParameters`: a non-empty token name and a token or quoted-string value.
    package(flint) static void checkParameters(string parameter, string value) pure
    {
        hasLength(parameter, "'parameter' must not be empty");
        hasLength(value, "'value' must not be empty");
        checkToken(parameter);
        if (!isQuotedString(value))
            checkToken(value);
    }

    private static bool isQuotedString(scope const(char)[] s) pure nothrow @nogc
    {
        if (s.length < 2)
            return false;
        return (s[0] == '"' && s[$ - 1] == '"') || (s[0] == '\'' && s[$ - 1] == '\'');
    }

    /// Spring's protected `unquote`: strips matching quotes and backslash escapes.
    package(flint) static string unquote(string s) pure nothrow
    {
        if (!isQuotedString(s))
            return s;
        string inner = s[1 .. $ - 1];
        bool escaped;
        foreach (c; inner)
            if (c == '\\')
                escaped = true;
        if (!escaped)
            return inner;
        char[] sb;
        for (size_t i = 0; i < inner.length; i++)
        {
            char c = inner[i];
            if (c == '\\' && i + 1 < inner.length)
            {
                i++;
                c = inner[i];
            }
            sb ~= c;
        }
        return sb.idup;
    }

    /// Whether the primary type is the wildcard `*`.
    bool isWildcardType() const pure nothrow @nogc
    {
        return getType() == WILDCARD_TYPE;
    }

    /// Whether the subtype is `*` or a suffixed wildcard such as `*+xml`.
    bool isWildcardSubtype() const pure nothrow @nogc
    {
        const subtype = getSubtype();
        return subtype == WILDCARD_TYPE || (subtype.length >= 2 && subtype[0 .. 2] == "*+");
    }

    /// Whether neither the type nor the subtype is a wildcard.
    bool isConcrete() const pure nothrow @nogc
    {
        return !isWildcardType() && !isWildcardSubtype();
    }

    /// The primary type, lowercase.
    string getType() const pure nothrow @nogc
    {
        return mimeType;
    }

    /// The subtype, lowercase.
    string getSubtype() const pure nothrow @nogc
    {
        return mimeSubtype;
    }

    /// The subtype suffix after the last `+` (RFC 6839), or `null`.
    string getSubtypeSuffix() const pure nothrow @nogc
    {
        const index = lastIndexOf(mimeSubtype, '+');
        if (index >= 0 && mimeSubtype.length > index)
            return mimeSubtype[index + 1 .. $];
        return null;
    }

    /// The charset parameter, or `null` (R5: a nullable value becomes a pointer).
    // dfmt off
    const(Charset)* getCharset() const pure nothrow @nogc return
    // dfmt on
    {
        return resolvedCharset == Charset.init ? null : &resolvedCharset;
    }

    /// The value of parameter `name`, ignoring case, or `null`.
    string getParameter(scope const(char)[] name) const pure nothrow @nogc
    {
        return parameters().get(name);
    }

    /// All parameters, read-only.
    MimeTypeParameters getParameters() const pure nothrow @nogc
    {
        return parameters();
    }

    private MimeTypeParameters parameters() const pure nothrow @nogc
    {
        return MimeTypeParameters(parameterList);
    }

    /++
    Whether this MIME type includes `other`: `text/*` includes `text/plain` and `text/html`;
    `application/*+xml` includes `application/soap+xml`. Not symmetric.
    +/
    bool includes(const MimeType other) const pure nothrow @nogc
    {
        if (other == MimeType.init)
            return false;
        if (isWildcardType())
            return true;
        else if (getType() == other.getType())
        {
            if (getSubtype() == other.getSubtype())
                return true;
            if (isWildcardSubtype())
            {
                const thisPlusIdx = lastIndexOf(getSubtype(), '+');
                if (thisPlusIdx == -1)
                    return true;
                else
                {
                    const otherPlusIdx = lastIndexOf(other.getSubtype(), '+');
                    if (otherPlusIdx != -1)
                    {
                        const thisSubtypeNoSuffix = getSubtype()[0 .. thisPlusIdx];
                        const thisSubtypeSuffix = getSubtype()[thisPlusIdx + 1 .. $];
                        const otherSubtypeSuffix = other.getSubtype()[otherPlusIdx + 1 .. $];
                        if (thisSubtypeSuffix == otherSubtypeSuffix && thisSubtypeNoSuffix == WILDCARD_TYPE)
                            return true;
                    }
                }
            }
        }
        return false;
    }

    /// Whether this MIME type is compatible with `other`. Symmetric.
    bool isCompatibleWith(const MimeType other) const pure nothrow @nogc
    {
        if (other == MimeType.init)
            return false;
        if (isWildcardType() || other.isWildcardType())
            return true;
        else if (getType() == other.getType())
        {
            if (getSubtype() == other.getSubtype())
                return true;
            if (isWildcardSubtype() || other.isWildcardSubtype())
            {
                const thisSuffix = getSubtypeSuffix();
                const otherSuffix = other.getSubtypeSuffix();
                if (getSubtype() == WILDCARD_TYPE || other.getSubtype() == WILDCARD_TYPE)
                    return true;
                else if (isWildcardSubtype() && thisSuffix !is null)
                    return thisSuffix == other.getSubtype() || (otherSuffix !is null && thisSuffix == otherSuffix);
                else if (other.isWildcardSubtype() && otherSuffix !is null)
                    return getSubtype() == otherSuffix || (thisSuffix !is null && otherSuffix == thisSuffix);
            }
        }
        return false;
    }

    /// Whether type and subtype equal `other`'s, ignoring parameters.
    bool equalsTypeAndSubtype(const MimeType other) const pure nothrow @nogc
    {
        if (other == MimeType.init)
            return false;
        return equalsIgnoreCase(mimeType, other.mimeType) && equalsIgnoreCase(mimeSubtype, other.mimeSubtype);
    }

    /// Whether some element of `mimeTypes` has this type and subtype.
    bool isPresentIn(scope const(MimeType)[] mimeTypes) const pure nothrow @nogc
    {
        foreach (ref candidate; mimeTypes)
            if (candidate.equalsTypeAndSubtype(this))
                return true;
        return false;
    }

    /// Java's `equals`: type and subtype ignoring case, and equal parameters (charsets compared as charsets).
    bool equals(const MimeType other) const pure nothrow @nogc
    {
        return equalsIgnoreCase(mimeType, other.mimeType) && equalsIgnoreCase(mimeSubtype,
                other.mimeSubtype) && parametersAreEqual(other);
    }

    bool opEquals(const MimeType other) const pure nothrow @nogc
    {
        return equals(other);
    }

    private bool parametersAreEqual(const MimeType other) const pure nothrow @nogc
    {
        if (parameterList.length != other.parameterList.length)
            return false;
        foreach (ref entry; parameterList)
        {
            if (!other.parameters().containsKey(entry.key))
                return false;
            if (equalsIgnoreCase(PARAM_CHARSET, entry.key))
            {
                if (resolvedCharset != other.resolvedCharset)
                    return false;
            }
            else if (!unquotedEquals(entry.value, other.parameters().get(entry.key)))
                return false;
        }
        return true;
    }

    private static bool unquotedEquals(string a, string b) pure nothrow @nogc
    {
        const x = isQuotedString(a) ? a[1 .. $ - 1] : a;
        const y = isQuotedString(b) ? b[1 .. $ - 1] : b;
        return x == y;
    }

    /// Java's `hashCode`.
    int hashCode() const pure nothrow
    {
        int result = javaHash(mimeType);
        result = 31 * result + javaHash(mimeSubtype);
        result = 31 * result + parametersHashCode();
        return result;
    }

    size_t toHash() const pure nothrow
    {
        return cast(size_t) cast(uint) hashCode();
    }

    private int parametersHashCode() const pure nothrow
    {
        int result = 0;
        foreach (ref entry; parameterList)
        {
            const valueHash = equalsIgnoreCase(PARAM_CHARSET, entry.key) ? (resolvedCharset == Charset.init
                    ? 0 : javaHash(resolvedCharset.name())) : javaHash(unquote(entry.value));
            result += javaHash(toLowerAscii(entry.key)) ^ valueHash;
        }
        return result;
    }

    /// `type/subtype;key=value...`, parameters in insertion order.
    string toString() const pure nothrow
    {
        char[] builder;
        appendTo(builder);
        return builder.idup;
    }

    /// Spring's protected `appendTo(StringBuilder)`.
    package(flint) void appendTo(ref char[] builder) const pure nothrow
    {
        builder ~= mimeType;
        builder ~= '/';
        builder ~= mimeSubtype;
        foreach (ref entry; parameterList)
        {
            builder ~= ';';
            builder ~= entry.key;
            builder ~= '=';
            builder ~= entry.value;
        }
    }

    /// Java's `compareTo`: type, subtype, parameter count, then parameters sorted by name.
    int compareTo(const MimeType other) const pure nothrow
    {
        int comp = compareIgnoreCase(getType(), other.getType());
        if (comp != 0)
            return comp;
        comp = compareIgnoreCase(getSubtype(), other.getSubtype());
        if (comp != 0)
            return comp;
        comp = getParameters().size() - other.getParameters().size();
        if (comp != 0)
            return comp;
        auto thisAttributes = sortedKeys(getParameters().keySet());
        auto otherAttributes = sortedKeys(other.getParameters().keySet());
        foreach (i, thisAttribute; thisAttributes)
        {
            const otherAttribute = otherAttributes[i];
            comp = compareIgnoreCase(thisAttribute, otherAttribute);
            if (comp != 0)
                return comp;
            if (equalsIgnoreCase(PARAM_CHARSET, thisAttribute))
            {
                const thisCharset = getCharset();
                const otherCharset = other.getCharset();
                if (thisCharset is null && otherCharset is null)
                    continue;
                if (thisCharset is null)
                    return -1;
                if (otherCharset is null)
                    return 1;
                comp = thisCharset.compareTo(*otherCharset);
                if (comp != 0)
                    return comp;
            }
            else
            {
                const thisValue = getParameters().get(thisAttribute);
                string otherValue = other.getParameters().get(otherAttribute);
                if (otherValue is null)
                    otherValue = "";
                comp = compareOrdinal(unquote(thisValue), unquote(otherValue));
                if (comp != 0)
                    return comp;
            }
        }
        return 0;
    }

    int opCmp(const MimeType other) const pure nothrow
    {
        return compareTo(other);
    }

    /// Whether this type is more specific than `other` (wildcards, then parameter count).
    bool isMoreSpecific(const MimeType other) const pure nothrow @nogc
    {
        const thisWildcard = isWildcardType();
        const otherWildcard = other.isWildcardType();
        if (thisWildcard && !otherWildcard) // */* > audio/*
            return false;
        else if (!thisWildcard && otherWildcard) // audio/* < */*
            return true;
        else
        {
            const thisWildcardSubtype = isWildcardSubtype();
            const otherWildcardSubtype = other.isWildcardSubtype();
            if (thisWildcardSubtype && !otherWildcardSubtype) // audio/* > audio/basic
                return false;
            else if (!thisWildcardSubtype && otherWildcardSubtype) // audio/basic < audio/*
                return true;
            else if (getType() == other.getType() && getSubtype() == other.getSubtype())
                return getParameters().size() > other.getParameters().size();
            else
                return false;
        }
    }

    /// Whether this type is less specific than `other`.
    bool isLessSpecific(const MimeType other) const pure nothrow @nogc
    {
        return other.isMoreSpecific(this);
    }

    /// A constant whose type and subtype are already valid lowercase tokens (CTFE-friendly).
    package(flint) static MimeType literal(string type, string subtype) pure nothrow @nogc
    {
        MimeType result;
        result.mimeType = type;
        result.mimeSubtype = subtype;
        return result;
    }

    /// Parses `value`, as `MimeTypeUtils.parseMimeType`.
    static MimeType valueOf(string value) pure
    {
        return MimeTypeUtils.parseMimeType(value);
    }
}

/// `org.springframework.util.InvalidMimeTypeException`.
class InvalidMimeTypeException : IllegalArgumentException
{
    private string invalidMimeType;

    ///
    this(string mimeType, string message, string file = __FILE__, size_t line = __LINE__) pure nothrow
    {
        super(message is null
                ? "Invalid mime type \"" ~ mimeType ~ "\"" : "Invalid mime type \"" ~ mimeType ~ "\": " ~ message,
                null, file, line);
        invalidMimeType = mimeType;
    }

    /// The offending MIME type.
    string getMimeType() const pure nothrow @nogc
    {
        return invalidMimeType;
    }
}

/// `org.springframework.util.MimeTypeUtils`: constants and parsing.
struct MimeTypeUtils
{
    static immutable MimeType ALL = MimeType.literal("*", "*"); ///
    enum string ALL_VALUE = "*/*"; ///
    static immutable MimeType APPLICATION_GRAPHQL = MimeType.literal("application", "graphql+json"); ///
    enum string APPLICATION_GRAPHQL_VALUE = "application/graphql+json"; ///
    static immutable MimeType APPLICATION_JSON = MimeType.literal("application", "json"); ///
    enum string APPLICATION_JSON_VALUE = "application/json"; ///
    static immutable MimeType APPLICATION_OCTET_STREAM = MimeType.literal("application", "octet-stream"); ///
    enum string APPLICATION_OCTET_STREAM_VALUE = "application/octet-stream"; ///
    static immutable MimeType APPLICATION_XML = MimeType.literal("application", "xml"); ///
    enum string APPLICATION_XML_VALUE = "application/xml"; ///
    static immutable MimeType IMAGE_GIF = MimeType.literal("image", "gif"); ///
    enum string IMAGE_GIF_VALUE = "image/gif"; ///
    static immutable MimeType IMAGE_JPEG = MimeType.literal("image", "jpeg"); ///
    enum string IMAGE_JPEG_VALUE = "image/jpeg"; ///
    static immutable MimeType IMAGE_PNG = MimeType.literal("image", "png"); ///
    enum string IMAGE_PNG_VALUE = "image/png"; ///
    static immutable MimeType TEXT_HTML = MimeType.literal("text", "html"); ///
    enum string TEXT_HTML_VALUE = "text/html"; ///
    static immutable MimeType TEXT_PLAIN = MimeType.literal("text", "plain"); ///
    enum string TEXT_PLAIN_VALUE = "text/plain"; ///
    static immutable MimeType TEXT_XML = MimeType.literal("text", "xml"); ///
    enum string TEXT_XML_VALUE = "text/xml"; ///

    /++
    Parses one MIME type.
    Throws: `InvalidMimeTypeException` when it cannot be parsed.
    +/
    static MimeType parseMimeType(string mimeType) pure
    {
        if (mimeType.length == 0)
            throw new InvalidMimeTypeException(mimeType, "'mimeType' must not be empty");
        return MimeTypeParser(mimeType).parse();
    }

    /// Parses a comma-separated list of MIME types.
    static MimeType[] parseMimeTypes(string mimeTypes) pure
    {
        if (mimeTypes.length == 0)
            return null;
        auto tokens = tokenizeList(mimeTypes);
        auto result = new MimeType[tokens.length];
        foreach (i, token; tokens)
            result[i] = parseMimeType(token);
        return result;
    }

    /// Splits a comma-separated list, honouring quoted strings.
    deprecated("since 7.1.0, for removal") static string[] tokenize(string mimeTypes) pure nothrow
    {
        return tokenizeList(mimeTypes);
    }

    package(flint) static string[] tokenizeList(string mimeTypes) pure nothrow
    {
        if (mimeTypes.length == 0)
            return null;
        string[] tokens;
        bool inQuotes;
        size_t startIndex;
        size_t i;
        while (i < mimeTypes.length)
        {
            switch (mimeTypes[i])
            {
            case '"':
                inQuotes = !inQuotes;
                break;
            case ',':
                if (!inQuotes)
                {
                    const trimmed = trim(mimeTypes[startIndex .. i]);
                    if (trimmed.length != 0)
                        tokens ~= trimmed;
                    startIndex = i + 1;
                }
                break;
            case '\\':
                i++;
                break;
            default:
                break;
            }
            i++;
        }
        const trimmed = trim(mimeTypes[startIndex < mimeTypes.length ? startIndex : $ .. $]);
        if (trimmed.length != 0)
            tokens ~= trimmed;
        return tokens;
    }

    /// Joins with `", "`.
    static string toString(scope const(MimeType)[] mimeTypes) pure nothrow
    {
        char[] builder;
        foreach (i, ref mimeType; mimeTypes)
        {
            mimeType.appendTo(builder);
            if (i + 1 < mimeTypes.length)
                builder ~= ", ";
        }
        return builder.idup;
    }

    /++
    Sorts by specificity with Spring's stable bubble sort.
    Throws: `InvalidMimeTypeException` for more than 50 elements.
    +/
    static void sortBySpecificity(T)(T[] mimeTypes)
    {
        if (mimeTypes.length > 50)
        {
            string joined;
            foreach (i, ref mimeType; mimeTypes)
                joined ~= (i == 0 ? "" : ", ") ~ mimeType.toString();
            throw new InvalidMimeTypeException(joined, "Too many elements");
        }
        bubbleSort!((ref a, ref b) => a.isLessSpecific(b))(mimeTypes);
    }

    package(flint) static void bubbleSort(alias swap, T)(T[] list)
    {
        const len = list.length;
        for (size_t i = 0; i < len; i++)
        {
            for (size_t j = 1; j < len - i; j++)
            {
                if (swap(list[j - 1], list[j]))
                {
                    auto prev = list[j - 1];
                    list[j - 1] = list[j];
                    list[j] = prev;
                }
            }
        }
    }
}

private struct MimeTypeParser
{
    private enum State : ubyte
    {
        INITIAL,
        TYPE,
        SUBTYPE,
        PARAM_SEPARATOR,
        WHITESPACE,
        PARAM_NAME,
        PARAM_NAME_END,
        PARAM_VALUE_START,
        PARAM_VALUE_TOKEN,
        PARAM_VALUE_QUOTED,
        PARAM_VALUE_ESCAPED
    }

    string input;
    size_t index;
    size_t mark;
    string type = "";
    string subtype = "";
    MimeTypeParameter[] parameters;
    string paramName;
    MimeType parsed;
    bool hasParsed;

    this(string input) pure nothrow @nogc
    {
        this.input = input;
    }

    MimeType parse() pure
    {
        State state = State.INITIAL;
        for (; index < input.length; index++)
            state = process(state, input[index]);
        onEof(state);
        if (!hasParsed)
            throw new InvalidMimeTypeException(input, "'mimeType' must not be empty");
        return parsed;
    }

    private State process(State state, char c) pure
    {
        final switch (state)
        {
        case State.INITIAL:
            if (c == ' ' || c == '\t')
                return state;
            mark = index;
            return State.TYPE;
        case State.TYPE:
            if (c == '/')
            {
                type = input[mark .. index];
                if (type.length == 0)
                    throw new InvalidMimeTypeException(input, "'type' must not be empty");
                mark = index + 1;
                return State.SUBTYPE;
            }
            if (c == ';' || c == ' ' || c == '\t')
            {
                resolveBareType(input[mark .. index]);
                return c == ';' ? State.WHITESPACE : State.PARAM_SEPARATOR;
            }
            return state;
        case State.SUBTYPE:
            if (c == ';' || c == ' ' || c == '\t')
            {
                subtype = input[mark .. index];
                return c == ';' ? State.WHITESPACE : State.PARAM_SEPARATOR;
            }
            return state;
        case State.PARAM_SEPARATOR:
            if (c == ' ' || c == '\t')
                return state;
            if (c == ';')
                return State.WHITESPACE;
            throw new InvalidMimeTypeException(input, "Unexpected character '" ~ c ~ "', expected ';'");
        case State.WHITESPACE:
            if (c == ' ' || c == '\t' || c == ';')
                return state;
            if (c == '=')
                throw new InvalidMimeTypeException(input, "missing parameter name before '='");
            mark = index;
            return State.PARAM_NAME;
        case State.PARAM_NAME:
            if (c == '=')
            {
                paramName = input[mark .. index];
                return State.PARAM_VALUE_START;
            }
            if (c == ' ' || c == '\t')
            {
                paramName = input[mark .. index];
                return State.PARAM_NAME_END;
            }
            if (c == ';')
            {
                paramName = input[mark .. index];
                throw missingParameterValue();
            }
            return state;
        case State.PARAM_NAME_END:
            if (c == ' ' || c == '\t')
                return state;
            if (c == '=')
                return State.PARAM_VALUE_START;
            if (c == ';')
                throw missingParameterValue();
            throw new InvalidMimeTypeException(input, "Unexpected character '" ~ c ~ "' after parameter name");
        case State.PARAM_VALUE_START:
            if (c == ' ' || c == '\t')
                return state;
            if (c == ';')
                throw missingParameterValue();
            mark = index;
            return c == '"' ? State.PARAM_VALUE_QUOTED : State.PARAM_VALUE_TOKEN;
        case State.PARAM_VALUE_TOKEN:
            if (c == ';' || c == ' ' || c == '\t')
            {
                extractParameter(input[mark .. index]);
                return c == ';' ? State.WHITESPACE : State.PARAM_SEPARATOR;
            }
            return state;
        case State.PARAM_VALUE_QUOTED:
            if (c == '"')
            {
                extractParameter(input[mark .. index + 1]);
                return State.PARAM_SEPARATOR;
            }
            if (c == '\\')
                return State.PARAM_VALUE_ESCAPED;
            return state;
        case State.PARAM_VALUE_ESCAPED:
            return State.PARAM_VALUE_QUOTED;
        }
    }

    private void onEof(State state) pure
    {
        final switch (state)
        {
        case State.INITIAL:
            break;
        case State.TYPE:
            resolveBareType(input[mark .. $]);
            emitMimeType();
            break;
        case State.SUBTYPE:
            subtype = input[mark .. $];
            emitMimeType();
            break;
        case State.PARAM_SEPARATOR:
            emitMimeType();
            break;
        case State.WHITESPACE:
            if (type.length != 0)
                emitMimeType();
            break;
        case State.PARAM_NAME:
            paramName = input[mark .. $];
            throw missingParameterValue();
        case State.PARAM_NAME_END:
        case State.PARAM_VALUE_START:
            throw missingParameterValue();
        case State.PARAM_VALUE_TOKEN:
        case State.PARAM_VALUE_QUOTED:
        case State.PARAM_VALUE_ESCAPED:
            extractParameter(input[mark .. $]);
            emitMimeType();
            break;
        }
    }

    private void resolveBareType(string candidate) pure
    {
        if (candidate != MimeType.WILDCARD_TYPE)
            throw new InvalidMimeTypeException(input, "does not contain '/'");
        type = MimeType.WILDCARD_TYPE;
        subtype = MimeType.WILDCARD_TYPE;
    }

    private void extractParameter(string value) pure
    {
        if (trim(paramName).length == 0)
            throw new IllegalArgumentException("'paramName' must not be empty");
        foreach (ref existing; parameters)
            if (equalsIgnoreCase(existing.key, paramName))
                throw new InvalidMimeTypeException(input, "duplicate parameter '" ~ paramName ~ "=" ~ value ~ "'");
        parameters ~= MimeTypeParameter(paramName, value);
    }

    private InvalidMimeTypeException missingParameterValue() pure
    {
        return new InvalidMimeTypeException(input, "missing value for parameter '" ~ paramName ~ "'");
    }

    private void emitMimeType() pure
    {
        if (type == MimeType.WILDCARD_TYPE && subtype != MimeType.WILDCARD_TYPE)
            throw new InvalidMimeTypeException(input, "wildcard type is legal only in '*/*' (all mime types)");
        try
            parsed = MimeType(type, subtype, parameters);
        catch (UnsupportedCharsetException ex)
            throw new InvalidMimeTypeException(input, "unsupported charset '" ~ ex.getCharsetName() ~ "'");
        catch (IllegalArgumentException ex)
            throw new InvalidMimeTypeException(input, ex.getMessage());
        hasParsed = true;
    }
}

// ---------------------------------------------------------------------------------------------------------
// Text helpers (Java String semantics on ASCII; R14).

private bool isTokenChar(char ch) pure nothrow @nogc
{
    if (ch <= 31 || ch >= 127)
        return false;
    foreach (separator; "()<>@,;:\\\"/[]?={} \t")
        if (ch == separator)
            return false;
    return true;
}

private void hasLength(scope const(char)[] text, string message) pure
{
    if (text.length == 0)
        throw new IllegalArgumentException(message);
}

private void put(ref MimeTypeParameter[] map, MimeTypeParameter entry) pure nothrow
{
    foreach (i, ref existing; map)
    {
        if (equalsIgnoreCase(existing.key, entry.key))
        {
            // LinkedCaseInsensitiveMap.put drops the old key and appends the new one.
            map = map[0 .. i] ~ map[i + 1 .. $] ~ entry;
            return;
        }
    }
    map ~= entry;
}

package(flint) string toLowerAscii(string text) pure nothrow
{
    foreach (i, c; text)
    {
        if (c >= 'A' && c <= 'Z')
        {
            auto result = text.dup;
            foreach (ref d; result[i .. $])
                if (d >= 'A' && d <= 'Z')
                    d = cast(char)(d + 32);
            return result.idup;
        }
    }
    return text;
}

package(flint) bool equalsIgnoreCase(scope const(char)[] a, scope const(char)[] b) pure nothrow @nogc
{
    return a.length == b.length && compareIgnoreCase(a, b) == 0;
}

package(flint) int compareIgnoreCase(scope const(char)[] a, scope const(char)[] b) pure nothrow @nogc
{
    const n = a.length < b.length ? a.length : b.length;
    foreach (i; 0 .. n)
    {
        const x = lowerChar(a[i]), y = lowerChar(b[i]);
        if (x != y)
            return x - y;
    }
    return cast(int) a.length - cast(int) b.length;
}

private int compareOrdinal(scope const(char)[] a, scope const(char)[] b) pure nothrow @nogc
{
    const n = a.length < b.length ? a.length : b.length;
    foreach (i; 0 .. n)
        if (a[i] != b[i])
            return a[i] - b[i];
    return cast(int) a.length - cast(int) b.length;
}

private char lowerChar(char c) pure nothrow @nogc
{
    return c >= 'A' && c <= 'Z' ? cast(char)(c + 32) : c;
}

private ptrdiff_t lastIndexOf(scope const(char)[] text, char c) pure nothrow @nogc
{
    for (ptrdiff_t i = cast(ptrdiff_t) text.length - 1; i >= 0; i--)
        if (text[i] == c)
            return i;
    return -1;
}

package(flint) string trim(string text) pure nothrow @nogc
{
    size_t start, end = text.length;
    while (start < end && text[start] <= ' ')
        start++;
    while (end > start && text[end - 1] <= ' ')
        end--;
    return text[start .. end];
}

private string[] sortedKeys(string[] keys) pure nothrow
{
    // Insertion sort by String.CASE_INSENSITIVE_ORDER; parameter lists are short.
    for (size_t i = 1; i < keys.length; i++)
    {
        auto key = keys[i];
        size_t j = i;
        while (j > 0 && compareIgnoreCase(keys[j - 1], key) > 0)
        {
            keys[j] = keys[j - 1];
            j--;
        }
        keys[j] = key;
    }
    return keys;
}

private int javaHash(scope const(char)[] text) pure nothrow @nogc
{
    int hash;
    foreach (c; text)
        hash = 31 * hash + c; // ASCII tokens; MIME tokens are ASCII by construction
    return hash;
}
