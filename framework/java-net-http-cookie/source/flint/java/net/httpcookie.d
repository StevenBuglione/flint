/*
 * Copyright (c) 2005, 2023, Oracle and/or its affiliates. All rights reserved.
 * DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS FILE HEADER.
 *
 * This code is free software; you can redistribute it and/or modify it
 * under the terms of the GNU General Public License version 2 only, as
 * published by the Free Software Foundation.  Oracle designates this
 * particular file as subject to the "Classpath" exception as provided
 * by Oracle in the LICENSE file that accompanied this code.
 *
 * This code is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
 * FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
 * version 2 for more details (a copy is included in the LICENSE file that
 * accompanied this code).
 *
 * You should have received a copy of the GNU General Public License version
 * 2 along with this work; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin St, Fifth Floor, Boston, MA 02110-1301 USA.
 *
 * Please contact Oracle, 500 Oracle Parkway, Redwood Shores, CA 94065 USA
 * or visit www.oracle.com if you need additional information or have any
 * questions.
 */

/* Ported from openjdk 21.0.13: src/java.base/share/classes/java/net/HttpCookie.java.
 * Modified by the Flint authors: D final class with R5 Nullable!string for absent vs empty
 * optional attributes, R26 slice semantics, pure D attribute dispatch and Netscape date parsing,
 * and mixin JavaObject equality/hashing.
 */
/** Java SE's HTTP cookie model and Set-Cookie / Set-Cookie2 header parser. */
module flint.java.net.httpcookie;

import flint.engine.aot.clock : currentTimeMillis;
import flint.java.lang : IllegalArgumentException, stringHashCode;
import flint.java.lang.javaobject : JavaObject;
import flint.java.util : ArrayList, List;
import std.typecons : Nullable;

@safe:

private enum long MAX_AGE_UNSPECIFIED = -1;
private enum string SET_COOKIE = "set-cookie:";
private enum string SET_COOKIE2 = "set-cookie2:";

private struct OptString
{
    string value;
    bool present;

    Nullable!string toNullable() const pure nothrow @nogc
    {
        return present ? Nullable!string(value) : Nullable!string.init;
    }

    static OptString fromSlice(string s) pure nothrow @nogc
    {
        return s is null ? OptString.init : OptString(s, true);
    }

    static OptString fromNullable(Nullable!string s) pure nothrow @nogc
    {
        return s.isNull ? OptString.init : OptString(s.get, true);
    }
}

private pragma(inline, false) void throwIllegal(string message) pure
{
    throw new IllegalArgumentException(message);
}

/// Represents an HTTP cookie (Netscape draft, RFC 2109 and RFC 2965).
final class HttpCookie
{
    mixin JavaObject;

    private immutable string name_;
    private OptString value_;

    private OptString comment_;
    private OptString commentURL_;
    private bool toDiscard_;
    private OptString domain_;
    private long maxAge_ = MAX_AGE_UNSPECIFIED;
    private OptString path_;
    private OptString portlist_;
    private bool secure_;
    private bool httpOnly_;
    private int version_ = 1;

    private immutable OptString header_;
    private immutable long whenCreated_;

    /// Constructs a cookie with the given `name` and `value` (`null` means absent value).
    this(string name, string value)
    {
        this(name, OptString.fromSlice(value), OptString.init, currentTimeMillis());
    }

    /// Constructs a cookie with the given `name` and nullable `value`.
    this(string name, Nullable!string value)
    {
        this(name, OptString.fromNullable(value), OptString.init, currentTimeMillis());
    }

    package this(string name, OptString value, OptString header, long creationTime) pure
    {
        const trimmed = javaTrim(name);
        if (trimmed.length == 0 || !isToken(trimmed) || trimmed[0] == '$')
            throwIllegal("Illegal cookie name");

        this.name_ = trimmed;
        this.value_ = value;
        this.toDiscard_ = false;
        this.secure_ = false;
        this.whenCreated_ = creationTime;
        this.portlist_ = OptString.init;
        this.header_ = header;
    }

    private this(const HttpCookie src) pure nothrow @nogc
    {
        this.name_ = src.name_;
        this.value_ = src.value_;
        this.comment_ = src.comment_;
        this.commentURL_ = src.commentURL_;
        this.toDiscard_ = src.toDiscard_;
        this.domain_ = src.domain_;
        this.maxAge_ = src.maxAge_;
        this.path_ = src.path_;
        this.portlist_ = src.portlist_;
        this.secure_ = src.secure_;
        this.httpOnly_ = src.httpOnly_;
        this.version_ = src.version_;
        this.header_ = src.header_;
        this.whenCreated_ = src.whenCreated_;
    }

    /// Parses cookies from a `Set-Cookie` or `Set-Cookie2` header string.
    static List!HttpCookie parse(string header)
    {
        return parseWithTime(header, false, currentTimeMillis());
    }

    package static List!HttpCookie parseWithTime(string header, bool retainHeader, long nowMillis)
    {
        const guessedVersion = guessCookieVersion(header);

        string body_ = header;
        if (startsWithIgnoreCaseAscii(body_, SET_COOKIE2))
            body_ = body_[SET_COOKIE2.length .. $];
        else if (startsWithIgnoreCaseAscii(body_, SET_COOKIE))
            body_ = body_[SET_COOKIE.length .. $];

        auto cookies = new ArrayList!HttpCookie();
        if (guessedVersion == 0)
        {
            auto cookie = parseInternal(body_, retainHeader, nowMillis);
            cookie.setVersion(0);
            cookies.add(cookie);
        }
        else
        {
            size_t quoteCount = 0;
            size_t start = 0;
            foreach (idx, char c; body_)
            {
                if (c == '"')
                    quoteCount++;
                else if (c == ',' && (quoteCount & 1) == 0)
                {
                    auto cookie = parseInternal(body_[start .. idx], retainHeader, nowMillis);
                    cookie.setVersion(1);
                    cookies.add(cookie);
                    start = idx + 1;
                }
            }
            auto cookie = parseInternal(body_[start .. $], retainHeader, nowMillis);
            cookie.setVersion(1);
            cookies.add(cookie);
        }

        return cookies;
    }

    /// Reports whether this cookie has expired.
    bool hasExpired() const nothrow @nogc
    {
        return hasExpiredAt(currentTimeMillis());
    }

    package bool hasExpiredAt(long nowMillis) const pure nothrow @nogc
    {
        if (maxAge_ == 0)
            return true;
        if (maxAge_ < 0)
            return false;
        const long deltaSecond = (nowMillis - whenCreated_) / 1000;
        return deltaSecond > maxAge_;
    }

    /// Sets the comment describing the cookie's purpose.
    void setComment(string purpose) pure nothrow @nogc
    {
        comment_ = OptString.fromSlice(purpose);
    }

    /// Sets the nullable comment describing the cookie's purpose.
    void setComment(Nullable!string purpose) pure nothrow @nogc
    {
        comment_ = OptString.fromNullable(purpose);
    }

    /// Returns the comment, or null if none.
    Nullable!string getComment() const pure nothrow @nogc
    {
        return comment_.toNullable();
    }

    /// Sets the comment URL.
    void setCommentURL(string purpose) pure nothrow @nogc
    {
        commentURL_ = OptString.fromSlice(purpose);
    }

    /// Sets the nullable comment URL.
    void setCommentURL(Nullable!string purpose) pure nothrow @nogc
    {
        commentURL_ = OptString.fromNullable(purpose);
    }

    /// Returns the comment URL, or null if none.
    Nullable!string getCommentURL() const pure nothrow @nogc
    {
        return commentURL_.toNullable();
    }

    /// Sets the RFC 2965 discard flag.
    void setDiscard(bool discard) pure nothrow @nogc
    {
        toDiscard_ = discard;
    }

    /// Returns the discard flag.
    bool getDiscard() const pure nothrow @nogc
    {
        return toDiscard_;
    }

    /// Sets the port list.
    void setPortlist(string ports) pure nothrow @nogc
    {
        portlist_ = OptString.fromSlice(ports);
    }

    /// Sets the nullable port list.
    void setPortlist(Nullable!string ports) pure nothrow @nogc
    {
        portlist_ = OptString.fromNullable(ports);
    }

    /// Returns the port list, or null if none.
    Nullable!string getPortlist() const pure nothrow @nogc
    {
        return portlist_.toNullable();
    }

    /// Sets the domain pattern (lowercased).
    void setDomain(string pattern) pure nothrow
    {
        setDomainOpt(OptString.fromSlice(pattern));
    }

    /// Sets the nullable domain pattern (lowercased).
    void setDomain(Nullable!string pattern) pure nothrow
    {
        setDomainOpt(OptString.fromNullable(pattern));
    }

    private void setDomainOpt(OptString pattern) pure nothrow
    {
        if (pattern.present)
            domain_ = OptString(asciiToLower(pattern.value), true);
        else
            domain_ = OptString.init;
    }

    /// Returns the domain name, or null if none.
    Nullable!string getDomain() const pure nothrow @nogc
    {
        return domain_.toNullable();
    }

    /// Sets the maximum age in seconds.
    void setMaxAge(long expiry) pure nothrow @nogc
    {
        maxAge_ = expiry;
    }

    /// Returns the maximum age in seconds (`-1` if unspecified).
    long getMaxAge() const pure nothrow @nogc
    {
        return maxAge_;
    }

    /// Sets the cookie path.
    void setPath(string uri) pure nothrow @nogc
    {
        path_ = OptString.fromSlice(uri);
    }

    /// Sets the nullable cookie path.
    void setPath(Nullable!string uri) pure nothrow @nogc
    {
        path_ = OptString.fromNullable(uri);
    }

    /// Returns the path, or null if none.
    Nullable!string getPath() const pure nothrow @nogc
    {
        return path_.toNullable();
    }

    /// Sets whether the cookie requires a secure protocol.
    void setSecure(bool flag) pure nothrow @nogc
    {
        secure_ = flag;
    }

    /// Returns whether the cookie requires a secure protocol.
    bool getSecure() const pure nothrow @nogc
    {
        return secure_;
    }

    /// Returns the cookie name.
    string getName() const pure nothrow @nogc
    {
        return name_;
    }

    /// Sets the cookie value.
    void setValue(string newValue) pure nothrow @nogc
    {
        value_ = OptString.fromSlice(newValue);
    }

    /// Sets the nullable cookie value.
    void setValue(Nullable!string newValue) pure nothrow @nogc
    {
        value_ = OptString.fromNullable(newValue);
    }

    /// Returns the cookie value, or null if absent.
    Nullable!string getValue() const pure nothrow @nogc
    {
        return value_.toNullable();
    }

    /// Returns the protocol version (0 or 1).
    int getVersion() const pure nothrow @nogc
    {
        return version_;
    }

    /// Sets the protocol version (must be 0 or 1).
    void setVersion(int v) pure
    {
        if (v != 0 && v != 1)
            throwIllegal("cookie version should be 0 or 1");
        version_ = v;
    }

    /// Returns whether the cookie is HttpOnly.
    bool isHttpOnly() const pure nothrow @nogc
    {
        return httpOnly_;
    }

    /// Sets whether the cookie is HttpOnly.
    void setHttpOnly(bool httpOnly) pure nothrow @nogc
    {
        this.httpOnly_ = httpOnly;
    }

    /// Checks whether `host` domain-matches `domain` per RFC 2965 section 3.3.2.
    static bool domainMatches(string domain, string host) pure nothrow @nogc
    {
        if (domain is null || host is null)
            return false;

        const bool isLocalDomain = equalsIgnoreCaseAscii(".local", domain);
        if (!isLocalDomain && !hasEmbeddedDot(domain))
            return false;

        if (indexOfChar(host, '.', 0) == -1 && matchesLocalHost(domain, host, isLocalDomain))
            return true;

        return matchDomainSuffix(domain, host);
    }

    /// Returns the Cookie header string representation (without leading `Cookie:`).
    override string toString() const pure nothrow
    {
        if (version_ > 0)
            return buildRFC2965(name_, value_.present ? value_.value : "null", path_, domain_, portlist_);
        return buildNetscape(name_, value_.present ? value_.value : "null");
    }

    /// Tests equality by case-insensitive name and domain and case-sensitive path.
    bool equals(const Object obj) const pure nothrow @nogc
    {
        if (obj is this)
            return true;
        const other = cast(const HttpCookie) obj;
        if (other is null)
            return false;
        return equalsIgnoreCaseAscii(name_, other.name_) && optEqualsIgnoreCaseAscii(domain_,
                other.domain_) && optEquals(path_, other.path_);
    }

    /// Returns the Java hash code: sum of lower-cased name, lower-cased domain and path hashes.
    int hashCode() const pure nothrow @nogc
    {
        const int h1 = asciiLowerHashCode(name_);
        const int h2 = domain_.present ? asciiLowerHashCode(domain_.value) : 0;
        const int h3 = path_.present ? stringHashCode(path_.value) : 0;
        return h1 + h2 + h3;
    }

    /// Returns a copy of this cookie.
    HttpCookie clone() const pure nothrow
    {
        return new HttpCookie(this);
    }

    package long getCreationTime() const pure nothrow @nogc
    {
        return whenCreated_;
    }

    private long expiryDate2DeltaSeconds(scope const(char)[] dateString) const pure nothrow @nogc
    {
        long epochSec;
        if (!parseCookieDate(dateString, epochSec))
            return 0;
        return (epochSec * 1000L - whenCreated_) / 1000L;
    }
}

private pragma(inline, false) string buildNetscape(string name, string val) pure nothrow
{
    char[] buf = new char[](name.length + 1 + val.length);
    buf[0 .. name.length] = name;
    buf[name.length] = '=';
    buf[name.length + 1 .. $] = val;
    return buf;
}

private pragma(inline, false) string buildRFC2965(string name, string val, OptString path,
        OptString domain, OptString portlist) pure nothrow
{
    size_t len = name.length + 3 + val.length;
    if (path.present)
        len += 8 + path.value.length + 1;
    if (domain.present)
        len += 10 + domain.value.length + 1;
    if (portlist.present)
        len += 8 + portlist.value.length + 1;

    char[] buf = new char[](len);
    size_t pos = 0;

    void put(scope const(char)[] part) pure nothrow @nogc
    {
        buf[pos .. pos + part.length] = part;
        pos += part.length;
    }

    put(name);
    put(`="`);
    put(val);
    put(`"`);
    if (path.present)
    {
        put(`;$Path="`);
        put(path.value);
        put(`"`);
    }
    if (domain.present)
    {
        put(`;$Domain="`);
        put(domain.value);
        put(`"`);
    }
    if (portlist.present)
    {
        put(`;$Port="`);
        put(portlist.value);
        put(`"`);
    }
    return buf;
}

private string javaTrim(string s) pure nothrow @nogc
{
    size_t start = 0;
    size_t end = s.length;
    while (start < end && s[start] <= ' ')
        start++;
    while (end > start && s[end - 1] <= ' ')
        end--;
    return s[start .. end];
}

private bool isToken(scope const(char)[] value) pure nothrow @nogc
{
    foreach (char c; value)
    {
        if (c < 0x20 || c >= 0x7f || c == ',' || c == ';' || c == ' ')
            return false;
    }
    return true;
}

private ptrdiff_t indexOfChar(scope const(char)[] s, char needle, size_t from) pure nothrow @nogc
{
    foreach (i; from .. s.length)
    {
        if (s[i] == needle)
            return cast(ptrdiff_t) i;
    }
    return -1;
}

private char toLowerAsciiChar(char c) pure nothrow @nogc
{
    return (c >= 'A' && c <= 'Z') ? cast(char)(c + ('a' - 'A')) : c;
}

private string asciiToLower(string s) pure nothrow
{
    bool hasUpper = false;
    foreach (char c; s)
    {
        if (c >= 'A' && c <= 'Z')
        {
            hasUpper = true;
            break;
        }
    }
    if (!hasUpper)
        return s;
    char[] out_ = new char[](s.length);
    foreach (i, char c; s)
        out_[i] = toLowerAsciiChar(c);
    return out_;
}

private bool equalsIgnoreCaseAscii(scope const(char)[] a, scope const(char)[] b) pure nothrow @nogc
{
    pragma(inline, false);
    if (a.length != b.length)
        return false;
    foreach (i; 0 .. a.length)
    {
        if (toLowerAsciiChar(a[i]) != toLowerAsciiChar(b[i]))
            return false;
    }
    return true;
}

private bool optEqualsIgnoreCaseAscii(OptString a, OptString b) pure nothrow @nogc
{
    if (!a.present && !b.present)
        return true;
    if (!a.present || !b.present)
        return false;
    return equalsIgnoreCaseAscii(a.value, b.value);
}

private bool optEquals(OptString a, OptString b) pure nothrow @nogc
{
    if (!a.present && !b.present)
        return true;
    if (!a.present || !b.present)
        return false;
    return a.value == b.value;
}

private bool startsWithIgnoreCaseAscii(scope const(char)[] s, scope const(char)[] prefix) pure nothrow @nogc
{
    if (s.length < prefix.length)
        return false;
    return equalsIgnoreCaseAscii(s[0 .. prefix.length], prefix);
}

private bool containsIgnoreCaseAscii(scope const(char)[] haystack, scope const(char)[] needle) pure nothrow @nogc
{
    if (needle.length == 0)
        return true;
    if (haystack.length < needle.length)
        return false;
    const limit = haystack.length - needle.length + 1;
    foreach (i; 0 .. limit)
    {
        if (equalsIgnoreCaseAscii(haystack[i .. i + needle.length], needle))
            return true;
    }
    return false;
}

private pragma(inline, false) int asciiLowerHashCode(scope const(char)[] s) pure nothrow @nogc
{
    int h = 0;
    size_t i = 0;
    while (i < s.length)
    {
        const ubyte b = cast(ubyte) s[i];
        if (b < 0x80)
        {
            h = 31 * h + cast(int) toLowerAsciiChar(cast(char) b);
            i++;
        }
        else
        {
            dchar cp = b;
            size_t width = 1;
            if ((b & 0xE0) == 0xC0 && i + 1 < s.length)
            {
                cp = ((b & 0x1F) << 6) | (s[i + 1] & 0x3F);
                width = 2;
            }
            else if ((b & 0xF0) == 0xE0 && i + 2 < s.length)
            {
                cp = ((b & 0x0F) << 12) | ((s[i + 1] & 0x3F) << 6) | (s[i + 2] & 0x3F);
                width = 3;
            }
            else if ((b & 0xF8) == 0xF0 && i + 3 < s.length)
            {
                cp = ((b & 0x07) << 18) | ((s[i + 1] & 0x3F) << 12) | ((s[i + 2] & 0x3F) << 6) | (s[i + 3] & 0x3F);
                width = 4;
            }
            if (cp <= 0xFFFF)
                h = 31 * h + cast(int) cp;
            else
            {
                const uint u = cast(uint)(cp - 0x10000);
                h = 31 * h + cast(int)(0xD800 + (u >> 10));
                h = 31 * h + cast(int)(0xDC00 + (u & 0x3FF));
            }
            i += width;
        }
    }
    return h;
}

private int guessCookieVersion(scope const(char)[] header) pure nothrow @nogc
{
    if (containsIgnoreCaseAscii(header, "expires="))
        return 0;
    if (containsIgnoreCaseAscii(header, "version="))
        return 1;
    if (containsIgnoreCaseAscii(header, "max-age"))
        return 1;
    if (startsWithIgnoreCaseAscii(header, SET_COOKIE2))
        return 1;
    return 0;
}

private OptString stripOffSurroundingQuote(OptString str) pure nothrow @nogc
{
    if (!str.present)
        return str;
    const s = str.value;
    if (s.length > 2 && ((s[0] == '"' && s[$ - 1] == '"') || (s[0] == '\'' && s[$ - 1] == '\'')))
        return OptString(s[1 .. $ - 1], true);
    return str;
}

private bool nextSemicolonToken(string header, ref size_t pos, out string token) pure nothrow @nogc
{
    while (pos < header.length && header[pos] == ';')
        pos++;
    if (pos >= header.length)
        return false;
    const start = pos;
    while (pos < header.length && header[pos] != ';')
        pos++;
    token = header[start .. pos];
    return true;
}

private pragma(inline, false) HttpCookie parseInternal(string header, bool retainHeader, long nowMillis) pure
{
    size_t pos = 0;
    string namevaluePair;
    if (!nextSemicolonToken(header, pos, namevaluePair))
        throwIllegal("Empty cookie header string");

    const eqIndex = indexOfChar(namevaluePair, '=', 0);
    if (eqIndex == -1)
        throwIllegal("Invalid cookie name-value pair");

    const name = javaTrim(namevaluePair[0 .. cast(size_t) eqIndex]);
    const rawValue = javaTrim(namevaluePair[cast(size_t) eqIndex + 1 .. $]);
    const strippedValue = stripOffSurroundingQuote(OptString(rawValue, true));
    auto cookie = new HttpCookie(name, strippedValue, retainHeader ? OptString(header,
            true) : OptString.init, nowMillis);

    while (nextSemicolonToken(header, pos, namevaluePair))
    {
        const attrEq = indexOfChar(namevaluePair, '=', 0);
        string attrName;
        OptString attrValue;
        if (attrEq != -1)
        {
            attrName = javaTrim(namevaluePair[0 .. cast(size_t) attrEq]);
            attrValue = OptString(javaTrim(namevaluePair[cast(size_t) attrEq + 1 .. $]), true);
        }
        else
        {
            attrName = javaTrim(namevaluePair);
            attrValue = OptString.init;
        }
        assignAttribute(cookie, attrName, attrValue);
    }

    return cookie;
}

private bool hasEmbeddedDot(scope const(char)[] domain) pure nothrow @nogc
{
    ptrdiff_t dot = indexOfChar(domain, '.', 0);
    if (dot == 0)
        dot = indexOfChar(domain, '.', 1);
    return dot != -1 && dot != cast(ptrdiff_t) domain.length - 1;
}

private bool matchesLocalHost(scope const(char)[] domain, scope const(char)[] host, bool isLocal) pure nothrow @nogc
{
    if (isLocal)
        return true;
    return domain.length == host.length + 6 && equalsIgnoreCaseAscii(domain[0 .. host.length], host)
        && equalsIgnoreCaseAscii(domain[host.length .. $], ".local");
}

private bool matchDomainSuffix(scope const(char)[] domain, scope const(char)[] host) pure nothrow @nogc
{
    const ptrdiff_t diff = cast(ptrdiff_t) host.length - cast(ptrdiff_t) domain.length;
    if (diff == 0)
        return equalsIgnoreCaseAscii(host, domain);
    if (diff > 0)
    {
        const h = host[0 .. cast(size_t) diff];
        const d = host[cast(size_t) diff .. $];
        return indexOfChar(h, '.', 0) == -1 && equalsIgnoreCaseAscii(d, domain);
    }
    if (diff == -1)
        return domain.length > 0 && domain[0] == '.' && equalsIgnoreCaseAscii(host, domain[1 .. $]);
    return false;
}

private pragma(inline, false) void assignAttribute(HttpCookie cookie, string attrName, OptString rawAttrValue) pure
{
    const attrValue = stripOffSurroundingQuote(rawAttrValue);

    if (assignMetadataAttribute(cookie, attrName, attrValue))
        return;
    assignPolicyAttribute(cookie, attrName, attrValue);
}

private bool assignMetadataAttribute(HttpCookie cookie, string attrName, OptString attrValue) pure nothrow
{
    if (equalsIgnoreCaseAscii(attrName, "comment"))
    {
        if (!cookie.comment_.present)
            cookie.comment_ = attrValue;
        return true;
    }
    if (equalsIgnoreCaseAscii(attrName, "commenturl"))
    {
        if (!cookie.commentURL_.present)
            cookie.commentURL_ = attrValue;
        return true;
    }
    if (equalsIgnoreCaseAscii(attrName, "domain"))
    {
        if (!cookie.domain_.present)
            cookie.setDomainOpt(attrValue);
        return true;
    }
    if (equalsIgnoreCaseAscii(attrName, "path"))
    {
        if (!cookie.path_.present)
            cookie.path_ = attrValue;
        return true;
    }
    if (equalsIgnoreCaseAscii(attrName, "port"))
    {
        if (!cookie.portlist_.present)
            cookie.portlist_ = attrValue.present ? attrValue : OptString("", true);
        return true;
    }
    return false;
}

private void assignPolicyAttribute(HttpCookie cookie, string attrName, OptString attrValue) pure
{
    if (equalsIgnoreCaseAscii(attrName, "discard"))
    {
        cookie.toDiscard_ = true;
    }
    else if (equalsIgnoreCaseAscii(attrName, "secure"))
    {
        cookie.secure_ = true;
    }
    else if (equalsIgnoreCaseAscii(attrName, "httponly"))
    {
        cookie.httpOnly_ = true;
    }
    else if (equalsIgnoreCaseAscii(attrName, "max-age"))
    {
        long maxage;
        if (!attrValue.present || !tryParseLong(attrValue.value, maxage))
            throwIllegal("Illegal cookie max-age attribute");
        if (cookie.maxAge_ == MAX_AGE_UNSPECIFIED)
            cookie.maxAge_ = maxage;
    }
    else if (equalsIgnoreCaseAscii(attrName, "version"))
    {
        int parsedVersion;
        if (attrValue.present && tryParseInt(attrValue.value, parsedVersion))
            cookie.setVersion(parsedVersion);
    }
    else if (equalsIgnoreCaseAscii(attrName, "expires"))
    {
        if (cookie.maxAge_ == MAX_AGE_UNSPECIFIED)
        {
            const long delta = attrValue.present ? cookie.expiryDate2DeltaSeconds(attrValue.value) : 0;
            cookie.maxAge_ = delta > 0 ? delta : 0;
        }
    }
}

private pragma(inline, false) bool tryParseLong(scope const(char)[] s, out long result) pure nothrow @nogc
{
    if (s.length == 0)
        return false;
    size_t i = 0;
    bool negative = false;
    long limit = -long.max;
    if (s[0] == '-')
    {
        negative = true;
        limit = long.min;
        i = 1;
    }
    else if (s[0] == '+')
    {
        i = 1;
    }
    if (i >= s.length)
        return false;

    const long multmin = limit / 10;
    long acc = 0;
    while (i < s.length)
    {
        const char c = s[i++];
        if (c < '0' || c > '9')
            return false;
        const int digit = c - '0';
        if (acc < multmin)
            return false;
        acc *= 10;
        if (acc < limit + digit)
            return false;
        acc -= digit;
    }
    result = negative ? acc : -acc;
    return true;
}

private bool tryParseInt(scope const(char)[] s, out int result) pure nothrow @nogc
{
    long v;
    if (!tryParseLong(s, v) || v < int.min || v > int.max)
        return false;
    result = cast(int) v;
    return true;
}

// ---------------------------------------------------------------------------
// Netscape / RFC 6265 cookie date parser for OpenJDK's 6 COOKIE_DATE_FORMATS.
// ---------------------------------------------------------------------------

private pragma(inline, false) bool parseCookieDate(scope const(char)[] s, out long epochSec) pure nothrow @nogc
{
    if (parseGmtFormat(s, '-', false, epochSec))
        return true;
    if (parseGmtFormat(s, ' ', false, epochSec))
        return true;
    if (parseOffsetFormat(s, false, epochSec))
        return true;
    if (parseGmtFormat(s, '-', true, epochSec))
        return true;
    if (parseGmtFormat(s, ' ', true, epochSec))
        return true;
    return parseOffsetFormat(s, true, epochSec);
}

private bool parseGmtFormat(scope const(char)[] s, char sep, bool twoDigitYear, out long epochSec) pure nothrow @nogc
{
    pragma(inline, false);
    size_t pos = 0;
    int dow, day, month, year, hour, minute, second;
    if (!parseWeekday(s, pos, dow) || !consumeLiteral(s, pos, ", ") || !parseDigits(s, pos, 1, 2,
            day) || pos >= s.length || s[pos++] != sep || !parseMonth(s, pos, month)
            || pos >= s.length || s[pos++] != sep || !parseYear(s, pos, twoDigitYear, year)
            || pos >= s.length || s[pos++] != ' ' || !parseHms(s, pos, hour, minute, second)
            || !consumeLiteral(s, pos, " GMT"))
        return false;
    return finishCalendarDate(year, month, day, dow, hour, minute, second, 0, epochSec);
}

private bool parseOffsetFormat(scope const(char)[] s, bool twoDigitYear, out long epochSec) pure nothrow @nogc
{
    pragma(inline, false);
    size_t pos = 0;
    int dow, month, day, year, hour, minute, second, offsetSec;
    if (!parseWeekday(s, pos, dow) || pos >= s.length || s[pos++] != ' ' || !parseMonth(s, pos,
            month) || pos >= s.length || s[pos++] != ' ' || !parseDigits(s, pos, 1, 2, day)
            || pos >= s.length || s[pos++] != ' ' || !parseYear(s, pos, twoDigitYear, year)
            || pos >= s.length || s[pos++] != ' ' || !parseHms(s, pos, hour, minute, second)
            || !consumeLiteral(s, pos, " GMT") || !parseRfc822Offset(s, pos, offsetSec))
        return false;
    return finishCalendarDate(year, month, day, dow, hour, minute, second, offsetSec, epochSec);
}

private bool consumeLiteral(scope const(char)[] s, ref size_t pos, scope const(char)[] lit) pure nothrow @nogc
{
    if (pos + lit.length > s.length || s[pos .. pos + lit.length] != lit)
        return false;
    pos += lit.length;
    return true;
}

private pragma(inline, false) bool parseNamedPrefix(scope const(char)[] s, ref size_t pos,
        scope const(string)[] fullNames, out int index) pure nothrow @nogc
{
    if (pos + 3 > s.length)
        return false;
    foreach (i, fn; fullNames)
    {
        if (equalsIgnoreCaseAscii(s[pos .. pos + 3], fn[0 .. 3]))
        {
            if (pos + fn.length <= s.length && equalsIgnoreCaseAscii(s[pos .. pos + fn.length], fn))
                pos += fn.length;
            else
                pos += 3;
            index = cast(int) i;
            return true;
        }
    }
    return false;
}

private bool parseWeekday(scope const(char)[] s, ref size_t pos, out int dow) pure nothrow @nogc
{
    static immutable string[7] names = [
        "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"
    ];
    return parseNamedPrefix(s, pos, names[], dow);
}

private bool parseMonth(scope const(char)[] s, ref size_t pos, out int month) pure nothrow @nogc
{
    static immutable string[12] names = [
        "January", "February", "March", "April", "May", "June", "July", "August", "September",
        "October", "November", "December"
    ];
    int idx;
    if (!parseNamedPrefix(s, pos, names[], idx))
        return false;
    month = idx + 1;
    return true;
}

private bool parseDigits(scope const(char)[] s, ref size_t p, size_t lo, size_t hi, out int v) pure nothrow @nogc
{
    size_t count = 0;
    int acc = 0;
    while (p < s.length && count < hi && s[p] >= '0' && s[p] <= '9')
    {
        acc = acc * 10 + (s[p] - '0');
        p++;
        count++;
    }
    if (count < lo)
        return false;
    v = acc;
    return true;
}

private bool parseYear(scope const(char)[] s, ref size_t pos, bool twoDigitYear, out int year) pure nothrow @nogc
{
    int acc = 0;
    size_t count = 0;
    while (pos < s.length && count < 4 && s[pos] >= '0' && s[pos] <= '9')
    {
        acc = acc * 10 + (s[pos] - '0');
        pos++;
        count++;
    }
    if (count == 0)
        return false;
    if (twoDigitYear)
    {
        const int y = acc % 100;
        year = y < 70 ? y + 2000 : y + 1900;
        return true;
    }
    if (count < 4)
        return false;
    year = acc;
    return true;
}

private bool parseHms(scope const(char)[] s, ref size_t pos, out int h, out int m, out int sec) pure nothrow @nogc
{
    if (!parseDigits(s, pos, 1, 2, h) || pos >= s.length || s[pos++] != ':' || !parseDigits(s, pos,
            1, 2, m) || pos >= s.length || s[pos++] != ':')
        return false;
    return parseDigits(s, pos, 1, 2, sec);
}

private bool parseRfc822Offset(scope const(char)[] s, ref size_t pos, out int offsetSec) pure nothrow @nogc
{
    if (pos + 5 > s.length)
        return false;
    int sign;
    if (s[pos] == '+')
        sign = 1;
    else if (s[pos] == '-')
        sign = -1;
    else
        return false;
    pos++;
    int hh, mm;
    if (!parseDigits(s, pos, 2, 2, hh) || !parseDigits(s, pos, 2, 2, mm))
        return false;
    if (hh > 23 || mm > 59)
        return false;
    offsetSec = sign * (hh * 3600 + mm * 60);
    return true;
}

private int daysInMonth(int year, int month) pure nothrow @nogc
{
    static immutable ubyte[12] lengths = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
    if (month == 2 && ((year % 4 == 0 && year % 100 != 0) || year % 400 == 0))
        return 29;
    return lengths[month - 1];
}

private long daysFromCivil(int year, int month, int day) pure nothrow @nogc
{
    const long y = year - (month <= 2 ? 1 : 0);
    const long era = (y >= 0 ? y : y - 399) / 400;
    const long yoe = y - era * 400;
    const long m = month + (month > 2 ? -3 : 9);
    const long doy = (153 * m + 2) / 5 + day - 1;
    const long doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    return era * 146_097 + doe - 719_468;
}

private pragma(inline, false) bool finishCalendarDate(int year, int month, int day, int expectedDow,
        int hour, int minute, int second, int offsetSec, out long epochSec) pure nothrow @nogc
{
    if (year < 1 || month < 1 || month > 12)
        return false;
    if (day < 1 || day > daysInMonth(year, month))
        return false;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59 || second < 0 || second > 59)
        return false;
    const long days = daysFromCivil(year, month, day);
    long actualDow = (days + 4) % 7;
    if (actualDow < 0)
        actualDow += 7;
    if (cast(int) actualDow != expectedDow)
        return false;
    epochSec = days * 86_400L + hour * 3600L + minute * 60L + second - offsetSec;
    return true;
}
