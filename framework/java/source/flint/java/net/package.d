/++
`java.net`: `URI`, holding the RFC 3986 text it was created from (clean-room from the Java SE specification).
The web layer passes URIs around (`ResponseEntity.created`, `HttpHeaders.setLocation`, `UriComponents.toUri`).
+/
module flint.java.net;

import flint.engine.aot.text : decimal, decodeUtf8;
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
                const issue = percentIssue(str, index);
                if (issue.reason !is null)
                    throw new IllegalArgumentException(issue.message(str));
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

private struct UriIssue
{
    string reason;
    size_t offset = size_t.max;

    string message(string input) const pure nothrow
    {
        if (offset == size_t.max)
            return reason ~ ": " ~ input;

        // Java reports an index in UTF-16 code units.
        const prefix = input[0 .. offset];
        size_t read;
        size_t units;
        while (read < prefix.length)
            units += decodeUtf8(prefix, read) > 0xFFFF ? 2 : 1;
        return reason ~ " at index " ~ decimal(cast(ulong) units) ~ ": " ~ input;
    }
}

private struct ScopedAddress
{
    size_t marker = size_t.max;
    UriIssue issue;
}

private UriIssue percentIssue(string text, size_t firstPercent) pure nothrow @nogc
{
    const headEnd = delimiter(text, ":/?#");
    const hasScheme = headEnd < text.length && text[headEnd] == ':';
    const scheme = hasScheme ? schemeIssue(text[0 .. headEnd]) : UriIssue.init;
    if (hasScheme && firstPercent < headEnd)
        return scheme; // Percent escapes are never allowed in a scheme name.

    const start = hasScheme ? headEnd + 1 : 0;
    const scoped = scopedAddress(text, start);
    foreach (relativeIndex, byte_; text[firstPercent .. $])
    {
        if (byte_ != '%')
            continue;
        const index = firstPercent + relativeIndex;
        if (index == scoped.marker)
        {
            if (scheme.reason !is null)
                return scheme;
            if (scoped.issue.reason !is null)
                return scoped.issue;
        }
        else if (!validEscape(text[index .. $]))
            return scheme.reason is null ? UriIssue("Malformed escape pair", index) : scheme;
    }
    return UriIssue.init;
}

private bool validEscape(scope const(char)[] escape) pure nothrow @nogc
{
    return escape.length >= 3 && isHex(escape[1]) && isHex(escape[2]);
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

    const hostOffset = authorityStart + hostStart + 1;
    const host = authority[hostStart + 1 .. $];
    const close = delimiter(host, "]");
    const marker = delimiter(host[0 .. close], "%");
    if (marker == close)
        return ScopedAddress.init;
    const absoluteMarker = hostOffset + marker;
    if (close == host.length)
        return ScopedAddress(absoluteMarker, UriIssue("Expected closing bracket for IPv6 address", hostOffset + close));
    if (marker + 1 == close)
        return ScopedAddress(absoluteMarker, UriIssue("scope id expected"));
    if (!validIpv6(host[0 .. close]))
        return ScopedAddress(absoluteMarker, UriIssue("Malformed IPv6 address", hostOffset));
    foreach (offset, byte_; host[marker + 1 .. close])
        if (!isScopeCharacter(byte_))
        {
            const issue = UriIssue("Illegal character in scope id", absoluteMarker + 1 + offset);
            return ScopedAddress(absoluteMarker, issue);
        }
    return ScopedAddress(absoluteMarker, portIssue(host[close + 1 .. $], hostOffset + close + 1));
}

private UriIssue portIssue(string suffix, size_t start) pure nothrow @nogc
{
    if (suffix.length == 0)
        return UriIssue.init;
    if (suffix[0] != ':')
        return UriIssue("Expected port number", start);
    int port;
    foreach (offset, byte_; suffix[1 .. $])
    {
        const digit = byte_ - '0';
        if (digit < 0 || digit > 9)
            return UriIssue("Illegal character in port number", start + 1 + offset);
        if (port > (int.max - digit) / 10)
            return UriIssue("Malformed port number", start + 1);
        port = port * 10 + digit;
    }
    return UriIssue.init;
}

private UriIssue schemeIssue(string part) pure nothrow @nogc
{
    if (part.length == 0)
        return UriIssue("Expected scheme name", 0);
    if (!isAsciiLetter(part[0]))
        return UriIssue("Illegal character in scheme name", 0);
    foreach (offset, byte_; part[1 .. $])
        if (!isAsciiLetter(byte_) && (byte_ < '0' || byte_ > '9') && byte_ != '+' && byte_ != '-' && byte_ != '.')
            return UriIssue("Illegal character in scheme name", offset + 1);
    return UriIssue.init;
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
