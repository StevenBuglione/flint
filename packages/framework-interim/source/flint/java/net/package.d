/++
Interim stand-in for framework-core's `flint.java.net.URI`: the subset the web packages pass around
(`ResponseEntity.created`, `HttpHeaders.setLocation`, `UriComponents.toUri`). Deleted when `flint:java` has it.
+/
module flint.java.net;

import flint.java.lang : IllegalArgumentException;

@safe:

/// `java.net.URI`, holding the RFC 3986 text it was created from.
struct URI
{
    private string text;

    /// Java's `URI.create(String)`.
    static URI create(string str) pure
    {
        foreach (c; str)
            if (c == ' ' || c == '"' || c == '<' || c == '>' || c == '\\' || c == '^' || c == '`' || c == '{'
                    || c == '|' || c == '}')
                throw new IllegalArgumentException("Illegal character in URI: " ~ str);
        return URI(str);
    }

    private this(string text) pure nothrow @nogc
    {
        this.text = text;
    }

    /// The URI text.
    string toString() const pure nothrow @nogc
    {
        return text;
    }

    /// The URI text with every non-ASCII byte percent-encoded, as Java's `toASCIIString`.
    string toASCIIString() const pure nothrow
    {
        static immutable hex = "0123456789ABCDEF";
        char[] result;
        foreach (char c; text)
        {
            if (c < 0x80)
                result ~= c;
            else
            {
                result ~= '%';
                result ~= hex[c >> 4];
                result ~= hex[c & 15];
            }
        }
        return result.idup;
    }

    /// Whether this URI has a scheme.
    bool isAbsolute() const pure nothrow @nogc
    {
        foreach (i, c; text)
        {
            if (c == ':')
                return i > 0;
            if (c == '/' || c == '?' || c == '#')
                return false;
        }
        return false;
    }

    bool opEquals(const URI other) const pure nothrow @nogc
    {
        return text == other.text;
    }

    size_t toHash() const pure nothrow
    {
        return hashOf(text);
    }
}
