/++
`java.net`: `URI`, parsed into its RFC 3986 components (ported from OpenJDK 21.0.13).
The web layer passes URIs around (`ResponseEntity.created`, `HttpHeaders.setLocation`, `UriComponents.toUri`).
+/
module flint.java.net;

import flint.engine.aot.text : decodeUtf8;
import flint.java.lang : IllegalArgumentException, NullPointerException;
import flint.java.net.urisyntaxexception : URISyntaxException;

@safe:

/// `java.net.URI`, an immutable value holding the parsed components of an RFC 2396 URI reference.
struct URI
{
    private string text_;
    private string scheme_;
    private string fragment_;
    private string authority_;
    private string userInfo_;
    private string host_;
    private int port_ = -1;
    private string path_; // null for an opaque URI
    private string query_;
    private bool opaque_;

    // -- Constructors and factories --

    /// Java's `URI(String)`: parses `str`, throwing `URISyntaxException` when it violates RFC 2396.
    this(string str) pure
    {
        if (str is null)
            throw new NullPointerException();
        UriParser parser;
        parser.input = str;
        parser.parse(false);
        adopt(parser);
    }

    /// Java's `URI(String scheme, String userInfo, String host, int port, String path, String query, String fragment)`.
    this(string scheme, string userInfo, string host, int port, string path, string query, string fragment) pure
    {
        const text = buildText(scheme, null, null, userInfo, host, port, path, query, fragment);
        checkPath(text, scheme, path);
        UriParser parser;
        parser.input = text;
        parser.parse(true);
        adopt(parser);
    }

    /// Java's `URI(String scheme, String authority, String path, String query, String fragment)`.
    this(string scheme, string authority, string path, string query, string fragment) pure
    {
        const text = buildText(scheme, null, authority, null, null, -1, path, query, fragment);
        checkPath(text, scheme, path);
        UriParser parser;
        parser.input = text;
        parser.parse(false);
        adopt(parser);
    }

    /// Java's `URI(String scheme, String host, String path, String fragment)`.
    this(string scheme, string host, string path, string fragment) pure
    {
        this(scheme, null, host, -1, path, null, fragment);
    }

    /// Java's `URI(String scheme, String ssp, String fragment)`.
    this(string scheme, string ssp, string fragment) pure
    {
        UriParser parser;
        parser.input = buildText(scheme, ssp, null, null, null, -1, null, null, fragment);
        parser.parse(false);
        adopt(parser);
    }

    /// Java's `URI.create(String)`: parses `str`, wrapping `URISyntaxException` in `IllegalArgumentException`.
    static URI create(string str) pure
    {
        try
            return URI(str);
        catch (URISyntaxException failure)
            throw new IllegalArgumentException(failure.getMessage(), failure);
    }

    private void adopt(ref UriParser parser) pure nothrow @nogc
    {
        text_ = parser.input;
        scheme_ = parser.scheme;
        fragment_ = parser.fragment;
        authority_ = parser.authority;
        userInfo_ = parser.userInfo;
        host_ = parser.host;
        port_ = parser.port;
        path_ = parser.path;
        query_ = parser.query;
        opaque_ = parser.opaque;
    }

    private static URI assemble(string scheme, string fragment, string authority, string userInfo,
            string host, int port, string path, string query) pure
    {
        URI result;
        result.scheme_ = scheme;
        result.fragment_ = fragment;
        result.authority_ = authority;
        result.userInfo_ = userInfo;
        result.host_ = host;
        result.port_ = port;
        result.path_ = path;
        result.query_ = query;
        result.text_ = buildText(scheme, null, authority, userInfo, host, port, path, query, fragment);
        return result;
    }

    // -- Component accessors --

    /// The scheme (`http`), or null for a relative URI.
    string getScheme() const pure nothrow @nogc
    {
        return scheme_;
    }

    /// Whether this URI has a scheme.
    bool isAbsolute() const pure nothrow @nogc
    {
        return scheme_ !is null;
    }

    /// Whether this URI is absolute and its scheme-specific part does not begin with `/`.
    bool isOpaque() const pure nothrow @nogc
    {
        return opaque_;
    }

    /// The raw scheme-specific part, never null.
    string getRawSchemeSpecificPart() const pure nothrow @nogc
    {
        const start = scheme_ is null ? 0 : scheme_.length + 1;
        const end = fragment_ is null ? text_.length : text_.length - fragment_.length - 1;
        return text_[start .. end];
    }

    /// The decoded scheme-specific part.
    string getSchemeSpecificPart() const pure nothrow
    {
        return decodePercent(getRawSchemeSpecificPart());
    }

    /// The raw authority, or null when undefined.
    string getRawAuthority() const pure nothrow @nogc
    {
        return authority_;
    }

    /// The decoded authority, or null when undefined.
    string getAuthority() const pure nothrow
    {
        return decodePercent(authority_);
    }

    /// The raw user-information, or null when undefined.
    string getRawUserInfo() const pure nothrow @nogc
    {
        return userInfo_;
    }

    /// The decoded user-information, or null when undefined.
    string getUserInfo() const pure nothrow
    {
        return decodePercent(userInfo_);
    }

    /// The host, or null when the authority is registry-based or undefined.
    string getHost() const pure nothrow @nogc
    {
        return host_;
    }

    /// The port, or -1 when undefined.
    int getPort() const pure nothrow @nogc
    {
        return port_;
    }

    /// The raw path, or null for an opaque URI.
    string getRawPath() const pure nothrow @nogc
    {
        return path_;
    }

    /// The decoded path, or null for an opaque URI.
    string getPath() const pure nothrow
    {
        return decodePercent(path_);
    }

    /// The raw query, or null when undefined.
    string getRawQuery() const pure nothrow @nogc
    {
        return query_;
    }

    /// The decoded query, or null when undefined.
    string getQuery() const pure nothrow
    {
        return decodePercent(query_);
    }

    /// The raw fragment, or null when undefined.
    string getRawFragment() const pure nothrow @nogc
    {
        return fragment_;
    }

    /// The decoded fragment, or null when undefined.
    string getFragment() const pure nothrow
    {
        return decodePercent(fragment_);
    }

    // -- Rendering and comparison --

    /// The URI text.
    string toString() const pure nothrow @nogc
    {
        return text_;
    }

    /// The URI text with every non-ASCII byte percent-encoded, as Java's `toASCIIString`.
    string toASCIIString() const pure nothrow
    {
        static immutable hex = "0123456789ABCDEF";
        char[] result;
        foreach (char c; text_)
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

    /// Java's `equals`: component equality with case-insensitive scheme and host and case-insensitive escape hex.
    bool equals(const URI that) const pure nothrow @nogc
    {
        if (this.isOpaque() != that.isOpaque())
            return false;
        if (!equalIgnoringCase(scheme_, that.scheme_))
            return false;
        if (!equal(fragment_, that.fragment_))
            return false;
        if (this.isOpaque())
            return equal(getRawSchemeSpecificPart(), that.getRawSchemeSpecificPart());
        if (!equal(path_, that.path_))
            return false;
        if (!equal(query_, that.query_))
            return false;
        if (authority_ is that.authority_)
            return true;
        if (host_ !is null)
        {
            if (!equal(userInfo_, that.userInfo_))
                return false;
            if (!equalIgnoringCase(host_, that.host_))
                return false;
            if (port_ != that.port_)
                return false;
        }
        else if (authority_ !is null)
        {
            if (!equal(authority_, that.authority_))
                return false;
        }
        else if (authority_ !is that.authority_)
            return false;
        return true;
    }

    /// `equals`.
    bool opEquals(const URI that) const pure nothrow @nogc
    {
        return equals(that);
    }

    /// Java's `hashCode`, based on the URI's components.
    int hashCode() const pure nothrow
    {
        int h = hashIgnoringCase(0, scheme_);
        h = hash(h, fragment_);
        if (isOpaque())
            h = hash(h, getRawSchemeSpecificPart());
        else
        {
            h = hash(h, path_);
            h = hash(h, query_);
            if (host_ !is null)
            {
                h = hash(h, userInfo_);
                h = hashIgnoringCase(h, host_);
                h += 1949 * port_;
            }
            else
                h = hash(h, authority_);
        }
        return h;
    }

    /// `hashCode`.
    size_t toHash() const pure nothrow
    {
        return cast(size_t) hashCode();
    }

    /// Java's `compareTo`: component ordering with case-insensitive scheme and host.
    int compareTo(const URI that) const pure nothrow @nogc
    {
        int c;
        if ((c = compareIgnoringCase(scheme_, that.scheme_)) != 0)
            return c;
        if (isOpaque())
        {
            if (that.isOpaque())
            {
                if ((c = compare(getRawSchemeSpecificPart(), that.getRawSchemeSpecificPart())) != 0)
                    return c;
                return compare(fragment_, that.fragment_);
            }
            return +1;
        }
        else if (that.isOpaque())
            return -1;
        if (host_ !is null && that.host_ !is null)
        {
            if ((c = compare(userInfo_, that.userInfo_)) != 0)
                return c;
            if ((c = compareIgnoringCase(host_, that.host_)) != 0)
                return c;
            if ((c = port_ - that.port_) != 0)
                return c;
        }
        else if ((c = compare(authority_, that.authority_)) != 0)
            return c;
        if ((c = compare(path_, that.path_)) != 0)
            return c;
        if ((c = compare(query_, that.query_)) != 0)
            return c;
        return compare(fragment_, that.fragment_);
    }

    /// `compareTo`.
    int opCmp(const URI that) const pure nothrow @nogc
    {
        return compareTo(that);
    }

    // -- Normalization, resolution, and relativization --

    /// Java's `normalize`: this URI with every `.` and `..` segment resolved.
    URI normalize() const pure
    {
        if (isOpaque() || path_ is null || path_.length == 0)
            return this;
        const normalized = normalizePath(path_);
        if (normalized is path_)
            return this;
        return assemble(scheme_, fragment_, authority_, userInfo_, host_, port_, normalized, query_);
    }

    /// Java's `resolve`: `uri` resolved against this URI.
    URI resolve(const URI child) const pure
    {
        if (child.isOpaque() || isOpaque())
            return child;
        if (child.scheme_ is null && child.authority_ is null && child.path_.length == 0
                && child.fragment_ !is null && child.query_ is null)
        {
            if (fragment_ !is null && equal(child.fragment_, fragment_))
                return this;
            return assemble(scheme_, child.fragment_, authority_, userInfo_, host_, port_, path_, query_);
        }
        if (child.scheme_ !is null)
            return child;
        if (child.authority_ is null)
        {
            const childPath = child.path_;
            string resolvedPath;
            if (childPath.length != 0 && childPath[0] == '/')
                resolvedPath = childPath;
            else
                resolvedPath = resolvePath(path_, childPath, isAbsolute());
            return assemble(scheme_, child.fragment_, authority_, userInfo_, host_, port_, resolvedPath, child.query_);
        }
        return assemble(scheme_, child.fragment_, child.authority_, child.userInfo_, child.host_,
                child.port_, child.path_, child.query_);
    }

    /// Java's `resolve(String)`: parses `str` with `create` and resolves it against this URI.
    URI resolve(string str) const pure
    {
        return resolve(URI.create(str));
    }

    /// Java's `relativize`: `uri` relative to this URI, or `uri` when it cannot be relativized.
    URI relativize(const URI child) const pure
    {
        if (child.isOpaque() || isOpaque())
            return child;
        if (!equalIgnoringCase(scheme_, child.scheme_) || !equal(authority_, child.authority_))
            return child;
        auto basePath = normalizePath(path_);
        const childPath = normalizePath(child.path_);
        if (!equal(basePath, childPath))
        {
            if (basePath.length == 0 || basePath[$ - 1] != '/')
                basePath ~= '/';
            if (childPath.length < basePath.length || !equal(childPath[0 .. basePath.length], basePath))
                return child;
        }
        return assemble(null, child.fragment_, null, null, null, -1, childPath[basePath.length .. $], child.query_);
    }

    /// Java's `parseServerAuthority`: re-parses the authority as a server-based authority.
    URI parseServerAuthority() const pure
    {
        if (host_ !is null || authority_ is null)
            return this;
        UriParser parser;
        parser.input = text_;
        parser.parse(true);
        URI result;
        result.adopt(parser);
        return result;
    }
}

// -- Parsing --

private struct UriParser
{
    string input;
    bool requireServerAuthority;

    string scheme;
    string fragment;
    string authority;
    string userInfo;
    string host;
    int port = -1;
    string path;
    string query;
    bool opaque;

    int ipv6byteCount;

    void fail(string reason) pure
    {
        throw new URISyntaxException(input, reason);
    }

    void fail(string reason, long position) pure
    {
        throw new URISyntaxException(input, reason, cast(int) charIndex(input, position));
    }

    void failExpecting(string expected, long position) pure
    {
        fail("Expected " ~ expected, position);
    }

    bool at(long start, long end, char c) const pure nothrow @nogc
    {
        return start < end && input[cast(size_t) start] == c;
    }

    bool at(long start, long end, string s) const pure nothrow @nogc
    {
        if (s.length > end - start)
            return false;
        foreach (i, char c; s)
            if (input[cast(size_t)(start + i)] != c)
                return false;
        return true;
    }

    long scanChar(long start, long end, char c) const pure nothrow @nogc
    {
        return start < end && input[cast(size_t) start] == c ? start + 1 : start;
    }

    long scanTo(long start, long end, string stop) const pure nothrow @nogc
    {
        long p = start;
        while (p < end)
        {
            if (containsChar(stop, input[cast(size_t) p]))
                break;
            p++;
        }
        return p;
    }

    long scanTo(long start, long end, string err, string stop) const pure nothrow @nogc
    {
        long p = start;
        while (p < end)
        {
            const c = input[cast(size_t) p];
            if (containsChar(err, c))
                return -1;
            if (containsChar(stop, c))
                break;
            p++;
        }
        return p;
    }

    long scanEscape(long start, long end, char first) pure
    {
        long p = start;
        if (first == '%')
        {
            if (p + 3 <= end && isHex(input[cast(size_t)(p + 1)]) && isHex(input[cast(size_t)(p + 2)]))
                return p + 3;
            fail("Malformed escape pair", p);
        }
        else if (first >= 128)
            return p + 1;
        return p;
    }

    long scan(long start, long end, ulong lowMask, ulong highMask) pure
    {
        long p = start;
        while (p < end)
        {
            const c = input[cast(size_t) p];
            if (matchChar(c, lowMask, highMask))
            {
                p++;
                continue;
            }
            if ((lowMask & L_ESCAPED) != 0)
            {
                const q = scanEscape(p, end, c);
                if (q > p)
                {
                    p = q;
                    continue;
                }
            }
            break;
        }
        return p;
    }

    void checkChars(long start, long end, ulong lowMask, ulong highMask, string what) pure
    {
        const p = scan(start, end, lowMask, highMask);
        if (p < end)
            fail("Illegal character in " ~ what, p);
    }

    void checkChar(long p, ulong lowMask, ulong highMask, string what) pure
    {
        checkChars(p, p + 1, lowMask, highMask, what);
    }

    void parse(bool rsa) pure
    {
        requireServerAuthority = rsa;
        const n = cast(long) input.length;
        long p = scanTo(0, n, "/?#", ":");
        if (p >= 0 && at(p, n, ':'))
        {
            if (p == 0)
                failExpecting("scheme name", 0);
            checkChar(0, L_ALPHA, H_ALPHA, "scheme name");
            checkChars(1, p, L_SCHEME, H_SCHEME, "scheme name");
            scheme = input[0 .. cast(size_t) p];
            p++;
            if (at(p, n, '/'))
                p = parseHierarchical(p, n);
            else
            {
                const q = scanTo(p, n, "#");
                if (q <= p)
                    failExpecting("scheme-specific part", p);
                checkChars(p, q, L_URIC, H_URIC, "opaque part");
                path = null;
                opaque = true;
                p = q;
            }
        }
        else
            p = parseHierarchical(0, n);
        if (at(p, n, '#'))
        {
            checkChars(p + 1, n, L_URIC, H_URIC, "fragment");
            fragment = input[cast(size_t)(p + 1) .. cast(size_t) n];
            p = n;
        }
        if (p < n)
            fail("end of URI", p);
    }

    long parseHierarchical(long start, long n) pure
    {
        long p = start;
        if (at(p, n, '/') && at(p + 1, n, '/'))
        {
            p += 2;
            const q = scanTo(p, n, "/?#");
            if (q > p)
                p = parseAuthority(p, q);
            else if (q < n)
            {
                // Deviation: an empty authority is allowed before a non-empty path, query or fragment.
            }
            else
                failExpecting("authority", p);
        }
        auto q = scanTo(p, n, "?#");
        checkChars(p, q, L_PATH, H_PATH, "path");
        path = input[cast(size_t) p .. cast(size_t) q];
        if (path is null)
            path = "";
        p = q;
        if (at(p, n, '?'))
        {
            p++;
            q = scanTo(p, n, "#");
            checkChars(p, q, L_URIC, H_URIC, "query");
            query = input[cast(size_t) p .. cast(size_t) q];
            p = q;
        }
        return p;
    }

    long parseAuthority(long start, long end) pure
    {
        long p = start;
        long q = p;
        long qreg = p;
        URISyntaxException saved;
        bool skipParseException;

        bool serverChars;
        bool regChars;
        if (scanTo(p, end, "]") > p)
            serverChars = scan(p, end, L_SERVER_PERCENT, H_SERVER_PERCENT) == end;
        else
            serverChars = scan(p, end, L_SERVER, H_SERVER) == end;
        regChars = (qreg = scan(p, end, L_REG_NAME, H_REG_NAME)) == end;

        if (regChars && !serverChars)
        {
            authority = input[cast(size_t) p .. cast(size_t) end];
            return end;
        }

        skipParseException = !requireServerAuthority && regChars;
        if (serverChars)
        {
            try
            {
                q = parseServer(p, end, skipParseException);
                if (q < end)
                {
                    if (skipParseException)
                    {
                        userInfo = null;
                        host = null;
                        port = -1;
                        q = p;
                    }
                    else
                        failExpecting("end of authority", q);
                }
                else
                    authority = input[cast(size_t) p .. cast(size_t) end];
            }
            catch (URISyntaxException x)
            {
                userInfo = null;
                host = null;
                port = -1;
                if (requireServerAuthority)
                    throw x;
                saved = x;
                q = p;
            }
        }

        if (q < end)
        {
            if (regChars)
                authority = input[cast(size_t) p .. cast(size_t) end];
            else if (saved !is null)
                throw saved;
            else
                fail("Illegal character in authority", serverChars ? q : qreg);
        }
        return end;
    }

    long parseServer(long start, long end, bool skipParseException) pure
    {
        long p = start;
        long q = scanTo(p, end, "/?#", "@");
        if (q >= p && at(q, end, '@'))
        {
            checkChars(p, q, L_USERINFO, H_USERINFO, "user info");
            userInfo = input[cast(size_t) p .. cast(size_t) q];
            p = q + 1;
        }

        if (at(p, end, '['))
        {
            p++;
            q = scanTo(p, end, "/?#", "]");
            if (q > p && at(q, end, ']'))
            {
                const scopeStart = scanTo(p, q, "%");
                if (scopeStart > p)
                {
                    parseIPv6Reference(p, scopeStart);
                    if (scopeStart + 1 == q)
                        fail("scope id expected");
                    checkChars(scopeStart + 1, q, L_SCOPE_ID, H_SCOPE_ID, "scope id");
                }
                else
                    parseIPv6Reference(p, q);
                host = input[cast(size_t)(p - 1) .. cast(size_t)(q + 1)];
                p = q + 1;
            }
            else
                failExpecting("closing bracket for IPv6 address", q);
        }
        else
        {
            q = parseIPv4Address(p, end);
            if (q <= p)
                q = parseHostname(p, end, skipParseException);
            p = q;
        }

        if (at(p, end, ':'))
        {
            p++;
            q = scanTo(p, end, "/");
            if (q > p)
            {
                checkChars(p, q, L_DIGIT, H_DIGIT, "port number");
                parsePort(p, q);
                p = q;
            }
        }
        else if (p < end && skipParseException)
            return p;

        if (p < end)
            failExpecting("port number", p);
        return p;
    }

    void parsePort(long start, long end) pure
    {
        int value;
        for (long i = start; i < end; i++)
        {
            const digit = input[cast(size_t) i] - '0';
            if (value > (int.max - digit) / 10)
                fail("Malformed port number", start);
            value = value * 10 + digit;
        }
        port = value;
    }

    long scanByte(long start, long end) pure
    {
        long p = start;
        const q = scan(p, end, L_DIGIT, H_DIGIT);
        if (q <= p)
            return q;
        long i = p;
        long j;
        while ((j = scanChar(i, q, '0')) > i)
            i = j;
        const significant = q - i;
        if (significant < 3)
            return q;
        if (significant > 3)
            return p;
        if (parseByteValue(p, q) > 255)
            return p;
        return q;
    }

    long parseByteValue(long start, long end) const pure nothrow @nogc
    {
        long value;
        for (long i = start; i < end; i++)
            value = value * 10 + (input[cast(size_t) i] - '0');
        return value;
    }

    long scanIPv4Address(long start, long end, bool strict) pure
    {
        long p = start;
        const m = scan(p, end, L_DIGIT | L_DOT, H_DIGIT | H_DOT);
        if (m <= p || (strict && m != end))
            return -1;
        for (;;)
        {
            long q;
            if ((q = scanByte(p, m)) <= p)
                break;
            p = q;
            if ((q = scanChar(p, m, '.')) <= p)
                break;
            p = q;
            if ((q = scanByte(p, m)) <= p)
                break;
            p = q;
            if ((q = scanChar(p, m, '.')) <= p)
                break;
            p = q;
            if ((q = scanByte(p, m)) <= p)
                break;
            p = q;
            if ((q = scanChar(p, m, '.')) <= p)
                break;
            p = q;
            if ((q = scanByte(p, m)) <= p)
                break;
            p = q;
            if (q < m)
                break;
            return q;
        }
        if (strict)
            fail("Malformed IPv4 address", p);
        return -1;
    }

    long takeIPv4Address(long start, long end, string expected) pure
    {
        const p = scanIPv4Address(start, end, true);
        if (p <= start)
            failExpecting(expected, start);
        return p;
    }

    long parseIPv4Address(long start, long end) pure
    {
        long p;
        try
            p = scanIPv4Address(start, end, false);
        catch (URISyntaxException)
            p = -1;
        if (p == -1)
            return p;
        if (p > start && p < end && input[cast(size_t) p] != ':')
            return -1;
        if (p > start)
            host = input[cast(size_t) start .. cast(size_t) p];
        return p;
    }

    long parseHostname(long start, long end, bool skipParseException) pure
    {
        long p = start;
        long q;
        long lastLabel = -1;
        do
        {
            q = scan(p, end, L_ALPHANUM, H_ALPHANUM);
            if (q <= p)
                break;
            lastLabel = p;
            p = q;
            q = scan(p, end, L_ALPHANUM | L_DASH, H_ALPHANUM | H_DASH);
            if (q > p)
            {
                if (input[cast(size_t)(q - 1)] == '-')
                    fail("Illegal character in hostname", q - 1);
                p = q;
            }
            q = scanChar(p, end, '.');
            if (q <= p)
                break;
            p = q;
        }
        while (p < end);

        if (p < end && !at(p, end, ':'))
        {
            if (skipParseException)
                return p;
            fail("Illegal character in hostname", p);
        }
        if (lastLabel < 0)
            failExpecting("hostname", start);

        if (lastLabel > start && !matchChar(input[cast(size_t) lastLabel], L_ALPHA, H_ALPHA))
            fail("Illegal character in hostname", lastLabel);

        host = input[cast(size_t) start .. cast(size_t) p];
        return p;
    }

    void parseIPv6Reference(long start, long end) pure
    {
        ipv6byteCount = 0;
        long p = start;
        bool compressed = false;
        long q = scanHexSeq(p, end);
        if (q > p)
        {
            p = q;
            if (at(p, end, "::"))
            {
                compressed = true;
                p = scanHexPost(p + 2, end);
            }
            else if (at(p, end, ':'))
            {
                p = takeIPv4Address(p + 1, end, "IPv4 address");
                ipv6byteCount += 4;
            }
        }
        else if (at(p, end, "::"))
        {
            compressed = true;
            p = scanHexPost(p + 2, end);
        }
        if (p < end)
            fail("Malformed IPv6 address", start);
        if (ipv6byteCount > 16)
            fail("IPv6 address too long", start);
        if (!compressed && ipv6byteCount < 16)
            fail("IPv6 address too short", start);
        if (compressed && ipv6byteCount == 16)
            fail("Malformed IPv6 address", start);
    }

    long scanHexPost(long start, long end) pure
    {
        long p = start;
        if (p == end)
            return p;
        const q = scanHexSeq(p, end);
        if (q > p)
        {
            p = q;
            if (at(p, end, ':'))
            {
                p++;
                p = takeIPv4Address(p, end, "hex digits or IPv4 address");
                ipv6byteCount += 4;
            }
        }
        else
        {
            p = takeIPv4Address(p, end, "hex digits or IPv4 address");
            ipv6byteCount += 4;
        }
        return p;
    }

    long scanHexSeq(long start, long end) pure
    {
        long p = start;
        long q = scan(p, end, L_HEX, H_HEX);
        if (q <= p)
            return -1;
        if (at(q, end, '.'))
            return -1;
        if (q > p + 4)
            fail("IPv6 hexadecimal digit sequence too long", p);
        ipv6byteCount += 2;
        p = q;
        while (p < end)
        {
            if (!at(p, end, ':'))
                break;
            if (at(p + 1, end, ':'))
                break;
            p++;
            q = scan(p, end, L_HEX, H_HEX);
            if (q <= p)
                failExpecting("digits for an IPv6 address", p);
            if (at(q, end, '.'))
            {
                p--;
                break;
            }
            if (q > p + 4)
                fail("IPv6 hexadecimal digit sequence too long", p);
            ipv6byteCount += 2;
            p = q;
        }
        return p;
    }
}

private size_t charIndex(string input, long position) pure nothrow @nogc
{
    size_t read;
    size_t units;
    while (read < input.length && read < cast(size_t) position)
        units += decodeUtf8(input[0 .. cast(size_t) position], read) > 0xFFFF ? 2 : 1;
    return units;
}

// -- Character classes (RFC 2396), ported from OpenJDK's URI masks --

private enum ulong L_DIGIT = 0x3FF000000000000UL;
private enum ulong H_DIGIT = 0UL;
private enum ulong H_UPALPHA = 0x7FFFFFEL;
private enum ulong H_LOWALPHA = 0x7FFFFFE00000000UL;
private enum ulong L_ALPHA = 0UL;
private enum ulong H_ALPHA = H_LOWALPHA | H_UPALPHA;
private enum ulong L_ALPHANUM = L_DIGIT;
private enum ulong H_ALPHANUM = H_ALPHA;
private enum ulong L_HEX = L_DIGIT;
private enum ulong H_HEX = 0x7E0000007EUL;
private enum ulong L_MARK = 0x678200000000UL;
private enum ulong H_MARK = 0x4000000080000000UL;
private enum ulong L_UNRESERVED = L_ALPHANUM | L_MARK;
private enum ulong H_UNRESERVED = H_ALPHANUM | H_MARK;
private enum ulong L_RESERVED = 0xAC00985000000000UL;
private enum ulong H_RESERVED = 0x28000001UL;
private enum ulong L_ESCAPED = 1UL;
private enum ulong H_ESCAPED = 0UL;
private enum ulong L_URIC = L_RESERVED | L_UNRESERVED | L_ESCAPED;
private enum ulong H_URIC = H_RESERVED | H_UNRESERVED | H_ESCAPED;
private enum ulong L_PCHAR = L_UNRESERVED | L_ESCAPED | 0x2400185000000000UL;
private enum ulong H_PCHAR = H_UNRESERVED | H_ESCAPED | 0x1UL;
private enum ulong L_PATH = L_PCHAR | 0x800800000000000UL;
private enum ulong H_PATH = H_PCHAR;
private enum ulong L_DASH = 0x200000000000UL;
private enum ulong H_DASH = 0UL;
private enum ulong L_DOT = 0x400000000000UL;
private enum ulong H_DOT = 0UL;
private enum ulong L_USERINFO = L_UNRESERVED | L_ESCAPED | 0x2C00185000000000UL;
private enum ulong H_USERINFO = H_UNRESERVED | H_ESCAPED;
private enum ulong L_REG_NAME = L_UNRESERVED | L_ESCAPED | 0x2C00185000000000UL;
private enum ulong H_REG_NAME = H_UNRESERVED | H_ESCAPED | 0x1UL;
private enum ulong L_SERVER = L_USERINFO | L_ALPHANUM | L_DASH | 0x400400000000000UL;
private enum ulong H_SERVER = H_USERINFO | H_ALPHANUM | H_DASH | 0x28000001UL;
private enum ulong L_SERVER_PERCENT = L_SERVER | 0x2000000000UL;
private enum ulong H_SERVER_PERCENT = H_SERVER;
private enum ulong L_SCHEME = L_ALPHA | L_DIGIT | 0x680000000000UL;
private enum ulong H_SCHEME = H_ALPHA | H_DIGIT;
private enum ulong L_SCOPE_ID = L_ALPHANUM | 0x400000000000UL;
private enum ulong H_SCOPE_ID = H_ALPHANUM | 0x80000000UL;

private bool matchChar(char c, ulong lowMask, ulong highMask) pure nothrow @nogc
{
    const value = cast(ubyte) c;
    if (value == 0)
        return false;
    if (value < 64)
        return ((1UL << value) & lowMask) != 0;
    if (value < 128)
        return ((1UL << (value - 64)) & highMask) != 0;
    return false;
}

private bool containsChar(string set, char c) pure nothrow @nogc
{
    foreach (char candidate; set)
        if (candidate == c)
            return true;
    return false;
}

private bool isHex(char c) pure nothrow @nogc
{
    const lower = c | 0x20;
    return (c >= '0' && c <= '9') || (lower >= 'a' && lower <= 'f');
}

private int hexValue(char c) pure nothrow @nogc
{
    if (c >= '0' && c <= '9')
        return c - '0';
    return (c | 0x20) - 'a' + 10;
}

private void appendEscape(ref char[] result, char value) pure nothrow
{
    static immutable hex = "0123456789ABCDEF";
    result ~= '%';
    result ~= hex[(value >> 4) & 15];
    result ~= hex[value & 15];
}

private string quote(string s, ulong lowMask, ulong highMask) pure nothrow
{
    char[] result;
    foreach (char c; s)
    {
        if (c < 0x80 && !matchChar(c, lowMask, highMask))
            appendEscape(result, c);
        else
            result ~= c;
    }
    return result.idup;
}

private void appendAuthority(ref char[] result, string authority, string userInfo, string host, int port) pure nothrow
{
    if (host !is null)
    {
        result ~= "//";
        if (userInfo !is null)
        {
            result ~= quote(userInfo, L_USERINFO, H_USERINFO);
            result ~= '@';
        }
        const needsBrackets = host.length > 0 && containsChar(host, ':') && (host[0] != '[' || host[$ - 1] != ']');
        if (needsBrackets)
            result ~= '[';
        result ~= host;
        if (needsBrackets)
            result ~= ']';
        if (port != -1)
        {
            result ~= ':';
            result ~= decimalText(port);
        }
    }
    else if (authority !is null)
    {
        result ~= "//";
        if (authority.length > 0 && authority[0] == '[')
        {
            const end = indexOfChar(authority, ']');
            auto doquote = authority;
            if (end != authority.length && containsChar(authority, ':'))
            {
                result ~= authority[0 .. end + 1];
                doquote = authority[end + 1 .. $];
            }
            result ~= quote(doquote, L_REG_NAME | L_SERVER, H_REG_NAME | H_SERVER);
        }
        else
            result ~= quote(authority, L_REG_NAME | L_SERVER, H_REG_NAME | H_SERVER);
    }
}

private string buildText(string scheme, string opaquePart, string authority, string userInfo,
        string host, int port, string path, string query, string fragment) pure nothrow
{
    char[] result;
    if (scheme !is null)
    {
        result ~= scheme;
        result ~= ':';
    }
    if (opaquePart !is null)
        result ~= quote(opaquePart, L_URIC, H_URIC);
    else
    {
        appendAuthority(result, authority, userInfo, host, port);
        if (path !is null)
            result ~= quote(path, L_PATH, H_PATH);
        if (query !is null)
        {
            result ~= '?';
            result ~= quote(query, L_URIC, H_URIC);
        }
    }
    if (fragment !is null)
    {
        result ~= '#';
        result ~= quote(fragment, L_URIC, H_URIC);
    }
    return result.idup;
}

private string decimalText(int value) pure nothrow
{
    if (value == 0)
        return "0";
    char[12] buffer;
    size_t position = buffer.length;
    uint magnitude = cast(uint) value;
    while (magnitude != 0)
    {
        buffer[--position] = cast(char)('0' + magnitude % 10);
        magnitude /= 10;
    }
    return buffer[position .. $].idup;
}

private size_t indexOfChar(string text, char c) pure nothrow @nogc
{
    foreach (i, char candidate; text)
        if (candidate == c)
            return i;
    return text.length;
}

// -- Component decoding --

private string decodePercent(string s) pure nothrow
{
    if (s is null || indexOfChar(s, '%') == s.length)
        return s;
    char[] result;
    bool betweenBrackets;
    size_t i;
    while (i < s.length)
    {
        const c = s[i];
        if (c == '[')
            betweenBrackets = true;
        else if (betweenBrackets && c == ']')
            betweenBrackets = false;
        if (c != '%' || betweenBrackets)
        {
            result ~= c;
            i++;
            continue;
        }
        while (i + 2 < s.length && s[i] == '%')
        {
            result ~= cast(char)((hexValue(s[i + 1]) << 4) | hexValue(s[i + 2]));
            i += 3;
        }
    }
    return result.idup;
}

// -- Comparison and hashing helpers (Java parity) --

private int toLower(char c) pure nothrow @nogc
{
    return c >= 'A' && c <= 'Z' ? c + ('a' - 'A') : c;
}

private int toUpper(char c) pure nothrow @nogc
{
    return c >= 'a' && c <= 'z' ? c - ('a' - 'A') : c;
}

private bool equal(string s, string t) pure nothrow @nogc
{
    return percentNormalizedComparison(s, t, true) == 0;
}

private bool equalIgnoringCase(string s, string t) pure nothrow @nogc
{
    if (s is null || t is null)
        return s is null && t is null;
    if (s.length != t.length)
        return false;
    foreach (i, char c; s)
        if (toLower(c) != toLower(t[i]))
            return false;
    return true;
}

private int compare(string s, string t) pure nothrow @nogc
{
    return percentNormalizedComparison(s, t, false);
}

private int compareIgnoringCase(string s, string t) pure nothrow @nogc
{
    if (s is null || t is null)
        return s is null && t is null ? 0 : (s is null ? -1 : +1);
    const n = s.length < t.length ? s.length : t.length;
    for (size_t i = 0; i < n; i++)
    {
        const c = toLower(s[i]) - toLower(t[i]);
        if (c != 0)
            return c;
    }
    return cast(int)(s.length - t.length);
}

private int percentNormalizedComparison(string s, string t, bool testForEquality) pure nothrow @nogc
{
    if (s is null || t is null)
        return s is null && t is null ? 0 : (s is null ? -1 : +1);
    if (indexOfChar(s, '%') == s.length)
    {
        // No escapes: a plain lexical comparison is enough.
        const n = s.length < t.length ? s.length : t.length;
        for (size_t i = 0; i < n; i++)
            if (s[i] != t[i])
                return cast(int) s[i] - cast(int) t[i];
        return cast(int)(s.length - t.length);
    }
    const sn = s.length;
    const tn = t.length;
    if (sn != tn && testForEquality)
        return cast(int)(sn - tn);
    const n = sn < tn ? sn : tn;
    size_t i;
    int value;
    while (i < n)
    {
        const c = s[i];
        const d = t[i];
        value = c - d;
        if (c != '%')
        {
            if (value != 0)
                return value;
            i++;
            continue;
        }
        if (d != '%' && value != 0)
            return value;
        i++;
        value = toLower(s[i]) - toLower(t[i]);
        if (value != 0)
            return value;
        i++;
        value = toLower(s[i]) - toLower(t[i]);
        if (value != 0)
            return value;
        i++;
    }
    return cast(int)(sn - tn);
}

private int hash(int hash, string s) pure nothrow
{
    if (s is null)
        return hash;
    return indexOfChar(s, '%') == s.length ? hash * 127 + javaHash(s) : normalizedHash(hash, s);
}

private int normalizedHash(int hash, string s) pure nothrow
{
    int h;
    size_t i;
    while (i < s.length)
    {
        const rune = decodeUtf8(s, i);
        if (rune == '%' && i + 2 <= s.length)
        {
            h = 31 * h + cast(int) '%';
            h = 31 * h + toUpper(s[i]);
            h = 31 * h + toUpper(s[i + 1]);
            i += 2;
            continue;
        }
        if (rune > 0xFFFF)
        {
            const value = cast(uint)(rune - 0x10000);
            h = 31 * h + cast(int)(0xD800 + (value >> 10));
            h = 31 * h + cast(int)(0xDC00 + (value & 0x3FF));
        }
        else
            h = 31 * h + cast(int) rune;
    }
    return hash * 127 + h;
}

private int hashIgnoringCase(int hash, string s) pure nothrow
{
    if (s is null)
        return hash;
    int h = hash;
    foreach (char c; s)
        h = 31 * h + toLower(c);
    return h;
}

private int javaHash(string s) pure nothrow
{
    int h;
    size_t i;
    while (i < s.length)
    {
        const rune = decodeUtf8(s, i);
        if (rune > 0xFFFF)
        {
            const value = cast(uint)(rune - 0x10000);
            h = 31 * h + cast(int)(0xD800 + (value >> 10));
            h = 31 * h + cast(int)(0xDC00 + (value & 0x3FF));
        }
        else
            h = 31 * h + cast(int) rune;
    }
    return h;
}

// -- Path normalization --

private bool needsNormalization(string path, out int segmentCount) pure nothrow @nogc
{
    bool normal = true;
    int segments;
    const end = cast(long) path.length - 1;
    long p;
    while (p <= end)
    {
        if (path[cast(size_t) p] != '/')
            break;
        p++;
    }
    if (p > 1)
        normal = false;
    while (p <= end)
    {
        if (path[cast(size_t) p] == '.' && (p == end || (path[cast(size_t)(p + 1)] == '/'
                || (path[cast(size_t)(p + 1)] == '.' && (p + 1 == end || path[cast(size_t)(p + 2)] == '/')))))
            normal = false;
        segments++;
        while (p <= end)
        {
            if (path[cast(size_t) p++] != '/')
                continue;
            while (p <= end)
            {
                if (path[cast(size_t) p] != '/')
                    break;
                normal = false;
                p++;
            }
            break;
        }
    }
    segmentCount = segments;
    return !normal;
}

private void splitPath(char[] path, int[] segments) pure nothrow @nogc
{
    const end = cast(long) path.length - 1;
    long p;
    size_t i;
    while (p <= end)
    {
        if (path[cast(size_t) p] != '/')
            break;
        path[cast(size_t) p] = '\0';
        p++;
    }
    while (p <= end)
    {
        segments[i++] = cast(int) p++;
        while (p <= end)
        {
            if (path[cast(size_t) p++] != '/')
                continue;
            path[cast(size_t)(p - 1)] = '\0';
            while (p <= end)
            {
                if (path[cast(size_t) p] != '/')
                    break;
                path[cast(size_t) p++] = '\0';
            }
            break;
        }
    }
}

private size_t joinPath(char[] path, int[] segments) pure nothrow @nogc
{
    const end = cast(long) path.length - 1;
    long p;
    if (path[0] == '\0')
        path[p++] = '/';
    foreach (int q; segments)
    {
        if (q == -1)
            continue;
        if (p == q)
        {
            while (p <= end && path[cast(size_t) p] != '\0')
                p++;
            if (p <= end)
                path[cast(size_t) p++] = '/';
        }
        else if (p < q)
        {
            while (q <= end && path[cast(size_t) q] != '\0')
                path[cast(size_t) p++] = path[cast(size_t) q++];
            if (q <= end)
                path[cast(size_t) p++] = '/';
        }
        else
            assert(false);
    }
    return cast(size_t) p;
}

private void removeDots(char[] path, int[] segments) pure nothrow @nogc
{
    const ns = cast(long) segments.length;
    const end = cast(long) path.length - 1;
    for (long i = 0; i < ns; i++)
    {
        int dots;
        while (i < ns)
        {
            const p = segments[cast(size_t) i];
            if (path[cast(size_t) p] == '.')
            {
                if (p == end || path[cast(size_t)(p + 1)] == '\0')
                {
                    dots = 1;
                    break;
                }
                if (path[cast(size_t)(p + 1)] == '.' && (p + 1 == end || path[cast(size_t)(p + 2)] == '\0'))
                {
                    dots = 2;
                    break;
                }
            }
            i++;
        }
        if ((i >= ns) || dots == 0)
            break;
        if (dots == 1)
            segments[cast(size_t) i] = -1;
        else
        {
            long j;
            for (j = i - 1; j >= 0; j--)
                if (segments[cast(size_t) j] != -1)
                    break;
            if (j >= 0)
            {
                const q = segments[cast(size_t) j];
                const previousIsDotDot = path[cast(size_t) q] == '.'
                    && path[cast(size_t)(q + 1)] == '.' && path[cast(size_t)(q + 2)] == '\0';
                if (!previousIsDotDot)
                {
                    segments[cast(size_t) i] = -1;
                    segments[cast(size_t) j] = -1;
                }
            }
        }
    }
}

private void maybeAddLeadingDot(char[] path, int[] segments) pure nothrow @nogc
{
    if (path[0] == '\0')
        return;
    const ns = segments.length;
    size_t first;
    while (first < ns)
    {
        if (segments[first] >= 0)
            break;
        first++;
    }
    if (first >= ns || first == 0)
        return;
    size_t p = cast(size_t) segments[first];
    while (p < path.length && path[p] != ':' && path[p] != '\0')
        p++;
    if (p >= path.length || path[p] == '\0')
        return;
    path[0] = '.';
    path[1] = '\0';
    segments[0] = 0;
}

private string normalizePath(string ps) pure nothrow
{
    int segments;
    if (!needsNormalization(ps, segments))
        return ps;
    auto path = ps.dup;
    auto indices = new int[segments];
    splitPath(path, indices);
    removeDots(path, indices);
    maybeAddLeadingDot(path, indices);
    const length = joinPath(path, indices);
    return path[0 .. length].idup;
}

private string resolvePath(string base, string child, bool absolute) pure nothrow
{
    const slash = lastIndexOfChar(base, '/');
    string path;
    if (child.length == 0)
    {
        if (slash >= 0)
            path = base[0 .. cast(size_t)(slash + 1)];
    }
    else if (slash >= 0 || !absolute)
        path = base[0 .. cast(size_t)(slash + 1)] ~ child;
    else
        path = "/" ~ child;
    return normalizePath(path);
}

private long lastIndexOfChar(string text, char c) pure nothrow @nogc
{
    long result = -1;
    foreach (i, char candidate; text)
        if (candidate == c)
            result = cast(long) i;
    return result;
}

private void checkPath(string text, string scheme, string path) pure
{
    if (scheme !is null && path !is null && path.length != 0 && path[0] != '/')
        throw new URISyntaxException(text, "Relative path in absolute URI");
}
