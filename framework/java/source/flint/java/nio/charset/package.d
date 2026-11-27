/++
`java.nio.charset`: `Charset` and `StandardCharsets` for the charsets Flint knows (clean-room from the Java SE
specification). `Charset` is a value naming one canonical charset; Java's identity comparison of the shared
instances is `==` here, and `Charset.init` names no charset.
+/
module flint.java.nio.charset;

import flint.java.lang : IllegalArgumentException, stringHashCode;

@safe:

/++
`java.nio.charset.Charset`. A value naming one canonical charset; Java's identity comparison of the
shared instances is `==` here. `Charset.init` names no charset.
+/
struct Charset
{
    private ubyte id; // 1-based index into `known`; 0 is no charset

    private static struct Known
    {
        string canonical;
        string[] aliases;
    }

    private static immutable Known[6] known = [
        Known("UTF-8", ["UTF8", "unicode-1-1-utf-8"]),
        Known("US-ASCII", [
            "ASCII", "us", "ISO646-US", "iso-ir-6", "ANSI_X3.4-1968", "cp367", "csASCII"
        ]),
        Known("ISO-8859-1", [
            "ISO8859_1", "ISO8859-1", "latin1", "l1", "8859_1", "cp819", "csISOLatin1"
        ]), Known("UTF-16", ["UTF_16", "utf16", "unicode"]),
        Known("UTF-16BE", ["UTF_16BE", "X-UTF-16BE"]), Known("UTF-16LE", ["UTF_16LE", "X-UTF-16LE"]),
    ];

    /// The canonical name (`"UTF-8"`).
    string name() const pure nothrow @nogc
    {
        return id == 0 ? null : known[id - 1].canonical;
    }

    /// Java's `displayName()`: the canonical name.
    string displayName() const pure nothrow @nogc
    {
        return name();
    }

    /// The canonical name.
    string toString() const pure nothrow @nogc
    {
        return name();
    }

    /// Java's `compareTo`: canonical names compared ignoring ASCII case.
    int compareTo(const Charset other) const pure nothrow @nogc
    {
        return compareIgnoreCase(name(), other.name());
    }

    /// Java's `hashCode`: the canonical name's `String.hashCode`.
    int hashCode() const pure nothrow @nogc
    {
        return stringHashCode(name());
    }

    /// Java's `equals`: two charsets are equal when their canonical names are equal.
    bool opEquals(const Charset other) const pure nothrow @nogc
    {
        return id == other.id;
    }

    /// The canonical name's hash, matching `hashCode`.
    size_t toHash() const pure nothrow @nogc
    {
        return cast(size_t) stringHashCode(name());
    }

    /// Java's `canEncode`: whether this charset can encode. True for all six standard charsets.
    bool canEncode() const pure nothrow @nogc
    {
        return id != 0;
    }

    /// Java's `isRegistered`: whether this charset is in the IANA registry. True for all six standard charsets.
    bool isRegistered() const pure nothrow @nogc
    {
        const canonical = name();
        if (canonical is null)
            return false;
        if (canonical.length >= 2 && (canonical[0] == 'X' || canonical[0] == 'x') && canonical[1] == '-')
            return false;
        return true;
    }

    /// Java 18+'s `defaultCharset`: UTF-8 for the six standard charsets.
    static Charset defaultCharset() pure nothrow @nogc
    {
        return Charset(1);
    }

    /// Java's `contains`: the standard containment table. Every UTF charset contains all six; US-ASCII only
    /// itself; ISO-8859-1 itself and US-ASCII.
    bool contains(const Charset other) const pure nothrow @nogc
    {
        switch (id)
        {
        case 2:
            return other.id == 2;
        case 3:
            return other.id == 2 || other.id == 3;
        case 1, 4, 5, 6:
            return other.id >= 1 && other.id <= 6;
        default:
            return false;
        }
    }

    /++
    The charset named `charsetName` or one of its aliases, ignoring case.
    Throws: `UnsupportedCharsetException` for a legal name this port does not know, `IllegalCharsetNameException`
    for a name with an illegal character.
    +/
    static Charset forName(scope const(char)[] charsetName) pure
    {
        const found = lookup(charsetName);
        if (found != 0)
            return Charset(found);
        throw new UnsupportedCharsetException(charsetName.idup);
    }

    /// Java's `forName(String, Charset)`: the named charset, or `fallback` when the name is illegal or unknown.
    static Charset forName(scope const(char)[] charsetName, Charset fallback) pure
    {
        try
            return forName(charsetName);
        catch (IllegalCharsetNameException)
            return fallback;
        catch (UnsupportedCharsetException)
            return fallback;
    }

    /// Whether `forName` would succeed. Throws `IllegalCharsetNameException` for a name with an illegal character.
    static bool isSupported(scope const(char)[] charsetName) pure
    {
        return lookup(charsetName) != 0;
    }

    private static ubyte lookup(scope const(char)[] charsetName) pure
    {
        foreach (i, ref entry; known)
        {
            if (equalsIgnoreCase(entry.canonical, charsetName))
                return cast(ubyte)(i + 1);
            foreach (alias_; entry.aliases)
                if (equalsIgnoreCase(alias_, charsetName))
                    return cast(ubyte)(i + 1);
        }
        checkName(charsetName);
        return 0;
    }

    /// Java's `checkName`: the first character must be a letter or digit; the rest may also be `- + : _ .`.
    private static void checkName(scope const(char)[] charsetName) pure
    {
        if (charsetName.length == 0)
            throw new IllegalCharsetNameException(charsetName.idup);
        foreach (i, c; charsetName)
        {
            const alpha = (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z');
            const digit = c >= '0' && c <= '9';
            if (alpha || digit)
                continue;
            if (i > 0 && (c == '-' || c == '+' || c == ':' || c == '_' || c == '.'))
                continue;
            throw new IllegalCharsetNameException(charsetName.idup);
        }
    }
}

/// `java.nio.charset.StandardCharsets`.
struct StandardCharsets
{
    static immutable Charset UTF_8 = Charset(1); ///
    static immutable Charset US_ASCII = Charset(2); ///
    static immutable Charset ISO_8859_1 = Charset(3); ///
    static immutable Charset UTF_16 = Charset(4); ///
    static immutable Charset UTF_16BE = Charset(5); ///
    static immutable Charset UTF_16LE = Charset(6); ///
}

/// `java.nio.charset.UnsupportedCharsetException`.
class UnsupportedCharsetException : IllegalArgumentException
{
    private string charsetName;

    /// The exception for `charsetName`.
    this(string charsetName, string file = __FILE__, size_t line = __LINE__) pure nothrow
    {
        super(charsetName, null, file, line);
        this.charsetName = charsetName;
    }

    /// The name that was not supported.
    string getCharsetName() const pure nothrow @nogc
    {
        return charsetName;
    }
}

/// `java.nio.charset.IllegalCharsetNameException`.
class IllegalCharsetNameException : IllegalArgumentException
{
    /// The exception for `charsetName`.
    this(string charsetName, string file = __FILE__, size_t line = __LINE__) pure nothrow
    {
        super(charsetName, null, file, line);
    }
}

private bool equalsIgnoreCase(scope const(char)[] a, scope const(char)[] b) pure nothrow @nogc
{
    return a.length == b.length && compareIgnoreCase(a, b) == 0;
}

private int compareIgnoreCase(scope const(char)[] a, scope const(char)[] b) pure nothrow @nogc
{
    const n = a.length < b.length ? a.length : b.length;
    foreach (i; 0 .. n)
    {
        const x = lower(a[i]), y = lower(b[i]);
        if (x != y)
            return x - y;
    }
    return cast(int) a.length - cast(int) b.length;
}

private char lower(char c) pure nothrow @nogc
{
    return c >= 'A' && c <= 'Z' ? cast(char)(c + 32) : c;
}
