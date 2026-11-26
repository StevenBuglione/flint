/++
`java.net`: `URI`, holding the RFC 3986 text it was created from (clean-room from the Java SE specification).
The web layer passes URIs around (`ResponseEntity.created`, `HttpHeaders.setLocation`, `UriComponents.toUri`).
+/
module flint.java.net;

import flint.java.lang : IllegalArgumentException;
import flint.java.net.internal.ipv6literal : isScopeCharacter, validIpv6;

@safe:

/// `java.net.URI`, holding the RFC 3986 text it was created from.
struct URI
{
    private string text;

    /// Java's `URI.create(String)`.
    static URI create(string str) pure
    {
        bool escapesChecked;
        foreach (index, c; str)
        {
            if (c == ' ' || c == '"' || c == '<' || c == '>' || c == '\\' || c == '^' || c == '`'
                    || c == '{' || c == '|' || c == '}')
                throw new IllegalArgumentException("Illegal character in URI: " ~ str);
            if (c == '%' && !escapesChecked)
            {
                if (!validPercentEscapes(str, index))
                    throw new IllegalArgumentException("Invalid percent syntax in URI: " ~ str);
                escapesChecked = true;
            }
        }
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

    /// The scheme (`http`), or null for a relative URI.
    string getScheme() const pure nothrow @nogc
    {
        foreach (i, c; text)
        {
            if (c == ':')
                return i > 0 ? text[0 .. i] : null;
            if (c == '/' || c == '?' || c == '#')
                return null;
        }
        return null;
    }

    /// Java's `equals`: equal text.
    bool equals(const URI other) const pure nothrow @nogc
    {
        return text == other.text;
    }

    /// Equal text.
    bool opEquals(const URI other) const pure nothrow @nogc
    {
        return text == other.text;
    }

    /// Hash of the text.
    size_t toHash() const pure nothrow
    {
        return hashOf(text);
    }
}

private struct ScopedAddress
{
    size_t marker = size_t.max;
    bool valid;
}

private bool validPercentEscapes(string text, size_t firstPercent) pure nothrow @nogc
{
    const headEnd = delimiter(text, ":/?#");
    const hasScheme = headEnd < text.length && text[headEnd] == ':';
    if (hasScheme && firstPercent < headEnd)
        return false; // Percent escapes are never allowed in a scheme name.

    const start = hasScheme ? headEnd + 1 : 0;
    const scoped = scopedAddress(text, start);
    foreach (relativeIndex, byte_; text[firstPercent .. $])
    {
        if (byte_ != '%')
            continue;
        const index = firstPercent + relativeIndex;
        if (index == scoped.marker)
        {
            if (!scoped.valid || (hasScheme && !validScheme(text[0 .. headEnd])))
                return false;
        }
        else if (text.length - index < 3 || !isHex(text[index + 1]) || !isHex(text[index + 2]))
            return false;
    }
    return true;
}

private ScopedAddress scopedAddress(string text, size_t start) pure nothrow @nogc
{
    if (text.length - start < 2 || text[start .. start + 2] != "//")
        return ScopedAddress.init;
    const authorityStart = start + 2;
    const authority = text[authorityStart .. authorityStart + delimiter(text[authorityStart .. $], "/?#")];
    const userEnd = delimiter(authority, "@");
    const hostStart = userEnd == authority.length ? 0 : userEnd + 1;
    if (hostStart == authority.length || authority[hostStart] != '[')
        return ScopedAddress.init;

    const host = authority[hostStart + 1 .. $];
    const close = delimiter(host, "]");
    const marker = delimiter(host[0 .. close], "%");
    if (marker == close)
        return ScopedAddress.init;
    const absoluteIndex = authorityStart + hostStart + 1 + marker;
    if (close == host.length || !validIpv6(host[0 .. close]))
        return ScopedAddress(absoluteIndex, false);
    foreach (byte_; host[marker + 1 .. close])
        if (!isScopeCharacter(byte_))
            return ScopedAddress(absoluteIndex, false);
    return ScopedAddress(absoluteIndex, validPortSuffix(host[close + 1 .. $]));
}

private bool validPortSuffix(string suffix) pure nothrow @nogc
{
    if (suffix.length == 0)
        return true;
    if (suffix[0] != ':')
        return false;
    int port;
    foreach (byte_; suffix[1 .. $])
    {
        const digit = byte_ - '0';
        if (digit < 0 || digit > 9 || port > (int.max - digit) / 10)
            return false;
        port = port * 10 + digit;
    }
    return true;
}

private bool validScheme(string part) pure nothrow @nogc
{
    if (part.length == 0 || !isAsciiLetter(part[0]))
        return false;
    foreach (byte_; part[1 .. $])
        if (!isAsciiLetter(byte_) && (byte_ < '0' || byte_ > '9') && byte_ != '+' && byte_ != '-' && byte_ != '.')
            return false;
    return true;
}

private size_t delimiter(string text, string choices) pure nothrow @nogc
{
    foreach (position, byte_; text)
        foreach (choice; choices)
            if (byte_ == choice)
                return position;
    return text.length;
}

private bool isHex(char byte_) pure nothrow @nogc
{
    const lower = byte_ | 0x20;
    return (byte_ >= '0' && byte_ <= '9') || (lower >= 'a' && lower <= 'f');
}

private bool isAsciiLetter(char byte_) pure nothrow @nogc
{
    const lower = byte_ | 0x20;
    return lower >= 'a' && lower <= 'z';
}
