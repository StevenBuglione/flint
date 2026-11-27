/*
 * Copyright (c) 1995, 2023, Oracle and/or its affiliates. All rights reserved.
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

/* Ported from openjdk 21.0.13:
 *   src/java.base/share/classes/java/net/URL.java
 *   src/java.base/share/classes/java/net/URLStreamHandler.java
 *   src/java.base/share/classes/sun/net/util/IPAddressUtil.java
 *   src/java.base/share/classes/sun/net/www/protocol/{http,https,ftp,jar,mailto}/Handler.java
 *   src/java.base/unix/classes/sun/net/www/protocol/file/Handler.java
 * Modified by the Flint authors: parsing-only URL subset with R5 Nullable!string optional
 * components, R26 null-slice handling, and D-NET-1 non-DNS equality and hashing.
 */

/// Java SE parsing-only `java.net.URL`.
module flint.java.net.url;

import flint.engine.aot.text : decimal, decodeUtf8, utf8;
import flint.java.lang.javaobject : JavaObject;
import flint.java.net.internal.ipv6literal : validIpv6;
import flint.java.net.malformedurlexception : MalformedURLException;
import std.typecons : Nullable;

@safe:

private enum ProtocolKind : ubyte
{
    none,
    http,
    https,
    ftp,
    file,
    jar,
    mailto,
    jmod,
    jrt,
}

private struct OptString
{
    string value;
    bool present;

    Nullable!string toNullable() const pure nothrow @nogc
    {
        return present ? Nullable!string(value) : Nullable!string.init;
    }

    static OptString fromNullable(Nullable!string s) pure nothrow @nogc
    {
        return s.isNull ? OptString.init : OptString(s.get, true);
    }

    static OptString fromSlice(string s) pure nothrow @nogc
    {
        return s is null ? OptString.init : OptString(s, true);
    }
}

private pragma(inline, false) void throwMalformed(string message) pure
{
    throw new MalformedURLException(message);
}

/// Parsing-only representation of a Uniform Resource Locator (`java.net.URL`).
final class URL
{
    mixin JavaObject;

    private string protocol_;
    private OptString host_;
    private int port_ = -1;
    private string file_;
    private OptString query_;
    private OptString authority_;
    private string path_;
    private OptString userInfo_;
    private OptString ref_;
    private ProtocolKind kind_;
    private int hashCode_ = -1;

    /// Constructs a `URL` by parsing `spec`.
    this(string spec) pure
    {
        this(null, spec);
    }

    /// Constructs a `URL` by parsing `spec` relative to `context`.
    this(URL context, string spec) pure
    {
        parseFromContext(context, spec);
    }

    /// Constructs a `URL` from `protocol`, `host`, and `file` using the protocol's default port.
    this(string protocol, string host, string file) pure
    {
        this(protocol, OptString.fromSlice(host), -1, file);
    }

    /// Constructs a `URL` from `protocol`, nullable `host`, and `file` using the default port.
    this(string protocol, Nullable!string host, string file) pure
    {
        this(protocol, OptString.fromNullable(host), -1, file);
    }

    /// Constructs a `URL` from `protocol`, `host`, `port`, and `file`.
    this(string protocol, string host, int port, string file) pure
    {
        this(protocol, OptString.fromSlice(host), port, file);
    }

    /// Constructs a `URL` from `protocol`, nullable `host`, `port`, and `file`.
    this(string protocol, Nullable!string host, int port, string file) pure
    {
        this(protocol, OptString.fromNullable(host), port, file);
    }

    private this(string protocol, OptString hostOpt, int port, string file) pure
    {
        protocol = lowerCaseAscii(protocol);
        protocol_ = protocol;

        if (hostOpt.present)
        {
            string h = hostOpt.value;
            if (indexOfChar(h, ':') >= 0 && (h.length == 0 || h[0] != '['))
                h = "[" ~ h ~ "]";
            host_ = OptString(h, true);

            if (port < -1)
                throwMalformed("Invalid port number :" ~ signedDecimal(port));
            port_ = port;
            authority_ = port == -1 ? OptString(h, true) : OptString(h ~ ":" ~ signedDecimal(port), true);
        }

        const hashIdx = indexOfChar(file, '#');
        if (hashIdx >= 0)
        {
            ref_ = OptString(file[hashIdx + 1 .. $], true);
            file = file[0 .. hashIdx];
        }
        const qIdx = lastIndexOfChar(file, '?');
        if (qIdx >= 0)
        {
            query_ = OptString(file[qIdx + 1 .. $], true);
            path_ = file[0 .. qIdx];
            file_ = path_ ~ "?" ~ query_.value;
        }
        else
        {
            path_ = file;
            file_ = path_;
        }

        kind_ = protocolKindFor(protocol_);
        if (kind_ == ProtocolKind.none)
            throwMalformed("unknown protocol: " ~ protocol_);

        if (host_.present)
        {
            const err = checkExternalForm(userInfo_, host_);
            if (err !is null)
                throwMalformed(err);
        }

        if (kind_ == ProtocolKind.jar && startsWithIgnoreCase(file, "jar:"))
            throwMalformed("Nested JAR URLs are not supported");
    }

    /// Gets the protocol name of this `URL`.
    string getProtocol() const pure nothrow @nogc
    {
        return protocol_;
    }

    /// Gets the authority part of this `URL`, or null if absent.
    Nullable!string getAuthority() const pure nothrow @nogc
    {
        return authority_.toNullable();
    }

    /// Gets the userInfo part of this `URL`, or null if absent.
    Nullable!string getUserInfo() const pure nothrow @nogc
    {
        return userInfo_.toNullable();
    }

    /// Gets the host name of this `URL`, or null if constructed with a null host.
    Nullable!string getHost() const pure nothrow @nogc
    {
        return host_.toNullable();
    }

    /// Gets the port number of this `URL`, or `-1` if not set.
    int getPort() const pure nothrow @nogc
    {
        return port_;
    }

    /// Gets the default port number of the protocol associated with this `URL`, or `-1`.
    int getDefaultPort() const pure nothrow @nogc
    {
        return defaultPortFor(kind_);
    }

    /// Gets the path part of this `URL`, or an empty string if absent.
    string getPath() const pure nothrow @nogc
    {
        return path_;
    }

    /// Gets the query part of this `URL`, or null if absent.
    Nullable!string getQuery() const pure nothrow @nogc
    {
        return query_.toNullable();
    }

    /// Gets the file name (`path` plus optional `?query`) of this `URL`.
    string getFile() const pure nothrow @nogc
    {
        return file_;
    }

    /// Gets the anchor/fragment of this `URL`, or null if absent.
    Nullable!string getRef() const pure nothrow @nogc
    {
        return ref_.toNullable();
    }

    /// Constructs the external string representation of this `URL`.
    string toExternalForm() const pure nothrow
    {
        return buildExternalForm(protocol_, authority_, path_, query_, ref_);
    }

    /// Returns `toExternalForm()`.
    override string toString() const pure nothrow
    {
        return toExternalForm();
    }

    /// Compares two URLs excluding the fragment component without DNS resolution (D-NET-1).
    bool sameFile(const URL other) const pure nothrow
    {
        if (other is null)
            return false;
        if (this is other)
            return true;

        if (kind_ == ProtocolKind.jar)
            return sameJarFile(this, other);

        return sameGenericFile(this, other);
    }

    /// Compares this URL for equality with `obj` without DNS resolution (D-NET-1).
    bool equals(Object obj) const pure nothrow
    {
        auto u2 = cast(const URL) obj;
        if (u2 is null)
            return false;
        if (this is u2)
            return true;
        if (!optEquals(ref_, u2.ref_))
            return false;
        if (!sameFile(u2))
            return false;
        if (kind_ == ProtocolKind.ftp && !optEquals(userInfo_, u2.userInfo_))
            return false;
        return true;
    }

    /// Computes and caches a non-DNS hash code consistent with `equals` (D-NET-1).
    int hashCode() pure nothrow
    {
        if (hashCode_ != -1)
            return hashCode_;

        hashCode_ = computeHashCode(this);
        return hashCode_;
    }

    private void parseFromContext(URL context, string spec) pure
    {
        const original = spec;
        size_t start;
        size_t limit = trimBounds(spec, start);

        if (limit - start >= 4 && startsWithIgnoreCase(spec[start .. limit], "url:"))
            start += 4;

        string newProtocol = extractLeadingProtocol(spec, start, limit);
        const isRelative = applyContextInheritance(context, newProtocol);

        if (protocol_.length == 0)
            throwMalformed("no protocol: " ~ original);

        if (kind_ == ProtocolKind.none)
        {
            kind_ = protocolKindFor(protocol_);
            if (kind_ == ProtocolKind.none)
                throwMalformed("unknown protocol: " ~ protocol_);
        }

        const hashIdx = indexOfCharFrom(spec, '#', start);
        const origLimit = limit;
        if (hashIdx >= 0 && hashIdx < limit)
        {
            ref_ = OptString(spec[hashIdx + 1 .. limit], true);
            limit = hashIdx;
        }

        if (isRelative && start == limit)
        {
            query_ = context.query_;
            if (!ref_.present)
                ref_ = context.ref_;
        }

        dispatchParse(spec, start, limit, hashIdx, origLimit);
    }

    private bool applyContextInheritance(URL context, ref string newProtocol) pure nothrow @nogc
    {
        protocol_ = newProtocol;
        if (context is null)
            return false;
        if (newProtocol.length > 0 && !asciiEqualsIgnoreCase(newProtocol, context.protocol_))
            return false;
        if (context.path_.length > 0 && context.path_[0] == '/')
            newProtocol = null;
        if (newProtocol.length > 0)
            return false;

        protocol_ = context.protocol_;
        kind_ = context.kind_;
        authority_ = context.authority_;
        userInfo_ = context.userInfo_;
        host_ = context.host_;
        port_ = context.port_;
        file_ = context.file_;
        path_ = context.path_;
        return true;
    }

    private void dispatchParse(string spec, size_t start, size_t limit, ptrdiff_t hashIdx, size_t origLimit) pure
    {
        final switch (kind_)
        {
        case ProtocolKind.jar:
            parseJarUrl(spec, start, limit, hashIdx, origLimit);
            break;
        case ProtocolKind.mailto:
            parseMailtoUrl(spec, start, limit);
            break;
        case ProtocolKind.http:
        case ProtocolKind.https:
        case ProtocolKind.ftp:
        case ProtocolKind.file:
        case ProtocolKind.jmod:
        case ProtocolKind.jrt:
            parseHierarchicalUrl(spec, start, limit);
            break;
        case ProtocolKind.none:
            throwMalformed("unknown protocol: " ~ protocol_);
            break;
        }
    }

    private void parseHierarchicalUrl(string spec, size_t start, size_t limit) pure
    {
        OptString authority = authority_;
        OptString userInfo = userInfo_;
        OptString host = host_;
        int port = port_;
        string path = path_;
        bool hasPath = path_.length > 0;
        OptString query = query_;
        bool queryOnly;

        if (start < limit)
        {
            const qStart = indexOfChar(spec[0 .. limit], '?');
            queryOnly = qStart >= 0 && cast(size_t) qStart == start;
            if (qStart >= 0)
            {
                const qPos = cast(size_t) qStart;
                query = OptString(spec[qPos + 1 .. limit], true);
                limit = qPos;
                spec = spec[0 .. qPos];
            }
        }

        const isUncName = (start + 4 <= limit) && spec[start .. start + 4] == "////";
        if (!isUncName && start + 2 <= limit && spec[start] == '/' && spec[start + 1] == '/')
            start = parseAuthorityPart(spec, start + 2, limit, authority, userInfo, host, port, path, hasPath);

        if (!host.present)
            host = OptString("", true);

        path = resolveHierarchicalPath(spec, start, limit, authority.present, queryOnly, path, hasPath);

        applyValidatedFields(host, port, authority, userInfo, path, query, ref_);
    }

    private void parseJarUrl(string spec, size_t start, size_t limit, ptrdiff_t hashIdx, size_t origLimit) pure
    {
        string file;
        OptString refOpt;
        const refOnly = hashIdx >= 0 && cast(size_t) hashIdx == start;
        if (hashIdx >= 0 && hashIdx < cast(ptrdiff_t) origLimit)
        {
            refOpt = OptString(spec[hashIdx + 1 .. origLimit], true);
            if (refOnly)
                file = file_;
        }

        const absoluteSpec = spec.length >= 4 && startsWithIgnoreCase(spec, "jar:");
        const specPart = spec[start .. limit];
        if (startsWithIgnoreCase(specPart, "jar:"))
            throwMalformed("Nested JAR URLs are not supported");

        if (absoluteSpec)
        {
            const bangSlash = indexOfBangSlash(specPart);
            if (bangSlash < 0)
                throwMalformed("no !/ in spec");
            const innerSpec = specPart[0 .. bangSlash - 1];
            try
            {
                cast(void) new URL(innerSpec);
            }
            catch (MalformedURLException e)
            {
                throwMalformed("invalid url: " ~ specPart ~ " (" ~ e.getMessage() ~ ")");
            }
            file = specPart;
        }
        else if (!refOnly)
        {
            string ctxFile = file_;
            if (specPart.length > 0 && specPart[0] == '/')
            {
                const bangSlash = indexOfBangSlash(ctxFile);
                if (bangSlash < 0)
                    throwMalformed("malformed context url:" ~ toExternalForm() ~ ": no !/");
                ctxFile = ctxFile[0 .. bangSlash];
            }
            else
            {
                const lastSlash = lastIndexOfChar(ctxFile, '/');
                if (lastSlash < 0)
                    throwMalformed("malformed context url:" ~ toExternalForm());
                else if (cast(size_t) lastSlash + 1 < ctxFile.length)
                    ctxFile = ctxFile[0 .. lastSlash + 1];
            }
            file = ctxFile ~ specPart;
            const bangSlash = indexOfBangSlash(file);
            if (bangSlash >= 0)
                file = canonicalizeJarString(file, cast(size_t) bangSlash);
        }

        applyLegacySetUrl(OptString("", true), -1, file, refOpt);
    }

    private void parseMailtoUrl(string spec, size_t start, size_t limit) pure
    {
        const file = start < limit ? spec[start .. limit] : "";
        bool nonBlank;
        foreach (c; file)
        {
            if (c > ' ')
            {
                nonBlank = true;
                break;
            }
        }
        if (!nonBlank)
            throwMalformed("No email address");
        applyLegacySetUrl(OptString("", true), port_, file, OptString.init);
    }

    private void applyLegacySetUrl(OptString host, int port, string file, OptString refOpt) pure
    {
        OptString authority;
        OptString userInfo;
        if (host.present && host.value.length > 0)
        {
            authority = port == -1 ? host : OptString(host.value ~ ":" ~ signedDecimal(port), true);
            const at = lastIndexOfChar(host.value, '@');
            if (at >= 0)
            {
                userInfo = OptString(host.value[0 .. at], true);
                host = OptString(host.value[at + 1 .. $], true);
            }
        }
        string path = file;
        OptString query;
        const q = lastIndexOfChar(file, '?');
        if (q >= 0)
        {
            query = OptString(file[q + 1 .. $], true);
            path = file[0 .. q];
        }
        applyValidatedFields(host, port, authority, userInfo, path, query, refOpt);
    }

    private void applyValidatedFields(OptString host, int port, OptString authority,
            OptString userInfo, string path, OptString query, OptString refOpt) pure
    {
        if (host.present)
        {
            const err = checkHost(host.value);
            if (err !is null)
                throwMalformed(err);
        }
        if (userInfo.present)
        {
            const err = checkUserInfo(userInfo.value);
            if (err !is null)
                throwMalformed(err);
        }
        if (authority.present)
        {
            const err = checkAuth(authority.value);
            if (err !is null)
                throwMalformed(err);
        }

        host_ = host;
        port_ = port;
        authority_ = authority;
        userInfo_ = userInfo;
        path_ = path;
        query_ = query;
        file_ = query.present ? (path ~ "?" ~ query.value) : path;
        ref_ = refOpt;
        hashCode_ = -1;
    }
}

private ProtocolKind protocolKindFor(scope const(char)[] protocol) pure nothrow @nogc
{
    switch (protocol)
    {
    case "http":
        return ProtocolKind.http;
    case "https":
        return ProtocolKind.https;
    case "ftp":
        return ProtocolKind.ftp;
    case "file":
        return ProtocolKind.file;
    case "jar":
        return ProtocolKind.jar;
    case "mailto":
        return ProtocolKind.mailto;
    case "jmod":
        return ProtocolKind.jmod;
    case "jrt":
        return ProtocolKind.jrt;
    default:
        return ProtocolKind.none;
    }
}

private int defaultPortFor(ProtocolKind kind) pure nothrow @nogc
{
    switch (kind)
    {
    case ProtocolKind.http:
        return 80;
    case ProtocolKind.https:
        return 443;
    case ProtocolKind.ftp:
        return 21;
    default:
        return -1;
    }
}

private bool sameGenericFile(const URL u1, const URL u2) pure nothrow @nogc
{
    if (!asciiEqualsIgnoreCase(u1.protocol_, u2.protocol_))
        return false;
    if (u1.file_ != u2.file_)
        return false;
    const p1 = u1.port_ != -1 ? u1.port_ : defaultPortFor(u1.kind_);
    const p2 = u2.port_ != -1 ? u2.port_ : defaultPortFor(u2.kind_);
    if (p1 != p2)
        return false;
    return hostsEqual(u1, u2);
}

private bool sameJarFile(const URL u1, const URL u2) pure nothrow
{
    if (u1.kind_ != ProtocolKind.jar || u2.kind_ != ProtocolKind.jar)
        return false;

    const sep1 = indexOfStr(u1.file_, "!/");
    const sep2 = indexOfStr(u2.file_, "!/");
    if (sep1 < 0 || sep2 < 0)
        return sameGenericFile(u1, u2);

    if (u1.file_[sep1 + 2 .. $] != u2.file_[sep2 + 2 .. $])
        return false;

    const inner1 = u1.file_[0 .. sep1];
    const inner2 = u2.file_[0 .. sep2];
    if (inner1 == inner2)
        return true;

    try
    {
        auto e1 = new URL(inner1);
        auto e2 = new URL(inner2);
        return sameGenericFile(e1, e2);
    }
    catch (Exception)
    {
        return sameGenericFile(u1, u2);
    }
}

private bool hostsEqual(const URL u1, const URL u2) pure nothrow @nogc
{
    if (u1.kind_ == ProtocolKind.file)
    {
        const s1 = u1.host_.present ? u1.host_.value : "";
        const s2 = u2.host_.present ? u2.host_.value : "";
        if (asciiEqualsIgnoreCase(s1, "localhost") && s2.length == 0)
            return true;
        if (asciiEqualsIgnoreCase(s2, "localhost") && s1.length == 0)
            return true;
    }
    if (!u1.host_.present && !u2.host_.present)
        return true;
    if (!u1.host_.present || !u2.host_.present)
        return false;
    return asciiEqualsIgnoreCase(u1.host_.value, u2.host_.value);
}

private int computeHashCode(const URL u) pure nothrow
{
    if (u.kind_ == ProtocolKind.jar)
    {
        int h = javaStringHash(u.protocol_, false);
        const sep = indexOfStr(u.file_, "!/");
        if (sep < 0)
            return h + javaStringHash(u.file_, false);
        const inner = u.file_[0 .. sep];
        try
        {
            auto enclosed = new URL(inner);
            h += computeHashCode(enclosed);
        }
        catch (Exception)
        {
            h += javaStringHash(inner, false);
        }
        h += javaStringHash(u.file_[sep + 2 .. $], false);
        return h;
    }

    int h = javaStringHash(u.protocol_, false);
    if (u.host_.present)
    {
        const normalizedEmpty = u.kind_ == ProtocolKind.file && asciiEqualsIgnoreCase(u.host_.value, "localhost");
        if (!normalizedEmpty)
            h += javaStringHash(u.host_.value, true);
    }
    h += javaStringHash(u.file_, false);
    h += u.port_ == -1 ? defaultPortFor(u.kind_) : u.port_;
    if (u.ref_.present)
        h += javaStringHash(u.ref_.value, false);
    return h;
}

private int javaStringHash(scope const(char)[] text, bool lowerAscii) pure nothrow @nogc
{
    int h = 0;
    size_t i = 0;
    while (i < text.length)
    {
        const b = text[i];
        if (b < 0x80)
        {
            char c = b;
            if (lowerAscii && c >= 'A' && c <= 'Z')
                c = cast(char)(c + ('a' - 'A'));
            h = 31 * h + cast(int) c;
            ++i;
            continue;
        }
        const cp = decodeUtf8(text, i);
        if (cp <= 0xFFFF)
        {
            h = 31 * h + cast(int) cp;
        }
        else
        {
            const adjusted = cp - 0x10000;
            const hi = cast(int)(0xD800 + (adjusted >> 10));
            const lo = cast(int)(0xDC00 + (adjusted & 0x3FF));
            h = 31 * h + hi;
            h = 31 * h + lo;
        }
    }
    return h;
}

private bool optEquals(const OptString a, const OptString b) pure nothrow @nogc
{
    return a.present == b.present && (!a.present || a.value == b.value);
}

private int parseJavaPort(string slice) pure
{
    if (slice.length == 0)
        throwMalformed(`Error at index 0 in: ""`);

    size_t i;
    bool negative;
    int limit = -int.max;
    const first = slice[0];
    if (first < '0')
    {
        if (first == '-')
        {
            negative = true;
            limit = int.min;
        }
        else if (first != '+')
        {
            throwMalformed(`Error at index 0 in: "` ~ slice ~ `"`);
        }
        if (slice.length == 1)
            throwMalformed(`Error at index 0 in: "` ~ slice ~ `"`);
        i = 1;
    }

    const multmin = limit / 10;
    int result = 0;
    while (i < slice.length)
    {
        const c = slice[i];
        if (c < '0' || c > '9')
            throwMalformed("Error at index " ~ decimal(cast(ulong) i) ~ ` in: "` ~ slice ~ `"`);
        const digit = cast(int)(c - '0');
        if (result < multmin)
            throwMalformed("Error at index " ~ decimal(cast(ulong) i) ~ ` in: "` ~ slice ~ `"`);
        result *= 10;
        if (result < limit + digit)
            throwMalformed("Error at index " ~ decimal(cast(ulong) i) ~ ` in: "` ~ slice ~ `"`);
        result -= digit;
        ++i;
    }
    return negative ? result : -result;
}

private string signedDecimal(int value) pure nothrow
{
    if (value < 0)
    {
        const mag = cast(ulong)(-(cast(long) value));
        return "-" ~ decimal(mag);
    }
    return decimal(cast(ulong) value);
}

private bool isValidProtocol(scope const(char)[] protocol) pure nothrow @nogc
{
    if (protocol.length == 0)
        return false;
    if (!isAsciiLetter(protocol[0]))
        return false;
    foreach (c; protocol[1 .. $])
    {
        if (!isAsciiLetter(c) && (c < '0' || c > '9') && c != '.' && c != '+' && c != '-')
            return false;
    }
    return true;
}

private bool isAsciiLetter(char c) pure nothrow @nogc
{
    const lower = c | 0x20;
    return lower >= 'a' && lower <= 'z';
}

private char[] buildExternalForm(string protocol, const OptString authority, string path,
        const OptString query, const OptString refOpt) pure nothrow
{
    const hasAuth = authority.present && authority.value.length > 0;
    size_t total = protocol.length + 1 + path.length;
    if (hasAuth)
        total += 2 + authority.value.length;
    if (query.present)
        total += 1 + query.value.length;
    if (refOpt.present)
        total += 1 + refOpt.value.length;

    auto buf = new char[total];
    size_t pos;
    buf[pos .. pos + protocol.length] = protocol;
    pos += protocol.length;
    buf[pos++] = ':';
    if (hasAuth)
    {
        buf[pos++] = '/';
        buf[pos++] = '/';
        buf[pos .. pos + authority.value.length] = authority.value;
        pos += authority.value.length;
    }
    if (path.length > 0)
    {
        buf[pos .. pos + path.length] = path;
        pos += path.length;
    }
    if (query.present)
    {
        buf[pos++] = '?';
        buf[pos .. pos + query.value.length] = query.value;
        pos += query.value.length;
    }
    if (refOpt.present)
    {
        buf[pos++] = '#';
        buf[pos .. pos + refOpt.value.length] = refOpt.value;
        pos += refOpt.value.length;
    }
    return buf;
}

private char[] lowerCaseAsciiBuf(string s) pure nothrow
{
    auto buf = new char[s.length];
    foreach (i, c; s)
        buf[i] = (c >= 'A' && c <= 'Z') ? cast(char)(c + ('a' - 'A')) : c;
    return buf;
}

private string lowerCaseAscii(string s) pure nothrow
{
    bool hasUpper;
    foreach (c; s)
    {
        if (c >= 'A' && c <= 'Z')
        {
            hasUpper = true;
            break;
        }
    }
    if (!hasUpper)
        return s;
    return lowerCaseAsciiBuf(s);
}

private bool asciiEqualsIgnoreCase(scope const(char)[] a, scope const(char)[] b) pure nothrow @nogc
{
    if (a.length != b.length)
        return false;
    foreach (i, c; a)
    {
        char ca = (c >= 'A' && c <= 'Z') ? cast(char)(c + 32) : c;
        char cb = (b[i] >= 'A' && b[i] <= 'Z') ? cast(char)(b[i] + 32) : b[i];
        if (ca != cb)
            return false;
    }
    return true;
}

private bool startsWithIgnoreCase(scope const(char)[] text, scope const(char)[] prefix) pure nothrow @nogc
{
    return text.length >= prefix.length && asciiEqualsIgnoreCase(text[0 .. prefix.length], prefix);
}

private ptrdiff_t indexOfChar(scope const(char)[] text, char needle) pure nothrow @nogc
{
    foreach (i, c; text)
        if (c == needle)
            return cast(ptrdiff_t) i;
    return -1;
}

private ptrdiff_t indexOfCharFrom(scope const(char)[] text, char needle, size_t start) pure nothrow @nogc
{
    foreach (i; start .. text.length)
        if (text[i] == needle)
            return cast(ptrdiff_t) i;
    return -1;
}

private ptrdiff_t lastIndexOfChar(scope const(char)[] text, char needle) pure nothrow @nogc
{
    foreach_reverse (i, c; text)
        if (c == needle)
            return cast(ptrdiff_t) i;
    return -1;
}

private ptrdiff_t lastIndexOfCharBefore(scope const(char)[] text, char needle, size_t maxIdx) pure nothrow @nogc
{
    const len = text.length;
    if (len == 0)
        return -1;
    const end = maxIdx < len ? maxIdx : len - 1;
    for (size_t i = end + 1; i > 0; --i)
        if (text[i - 1] == needle)
            return cast(ptrdiff_t)(i - 1);
    return -1;
}

private ptrdiff_t indexOfStr(scope const(char)[] text, scope const(char)[] needle, size_t start = 0) pure nothrow @nogc
{
    if (needle.length == 0)
        return start <= text.length ? cast(ptrdiff_t) start : -1;
    if (start > text.length || text.length - start < needle.length)
        return -1;
    const last = text.length - needle.length;
    foreach (i; start .. last + 1)
        if (text[i .. i + needle.length] == needle)
            return cast(ptrdiff_t) i;
    return -1;
}

private ptrdiff_t indexOfBangSlash(scope const(char)[] spec) pure nothrow @nogc
{
    const len = spec.length;
    if (len < 2)
        return -1;
    ptrdiff_t idx = cast(ptrdiff_t) len - 1;
    while (idx >= 0)
    {
        idx = lastIndexOfCharBefore(spec, '!', cast(size_t) idx);
        if (idx < 0)
            return -1;
        if (cast(size_t) idx + 1 < len && spec[idx + 1] == '/')
            return idx + 1;
        --idx;
    }
    return -1;
}

private size_t trimBounds(scope const(char)[] spec, out size_t start) pure nothrow @nogc
{
    size_t limit = spec.length;
    while (limit > 0 && spec[limit - 1] <= ' ')
        --limit;
    start = 0;
    while (start < limit && spec[start] <= ' ')
        ++start;
    return limit;
}

private string extractLeadingProtocol(string spec, ref size_t start, size_t limit) pure nothrow
{
    if (start < spec.length && spec[start] == '#')
        return null;
    for (size_t i = start; i < limit && spec[i] != '/'; ++i)
    {
        if (spec[i] == ':')
        {
            const candidate = lowerCaseAscii(spec[start .. i]);
            if (isValidProtocol(candidate))
            {
                start = i + 1;
                return candidate;
            }
            break;
        }
    }
    return null;
}

private size_t parseAuthorityPart(string spec, size_t start, size_t limit, ref OptString authority,
        ref OptString userInfo, ref OptString host, ref int port, ref string path, ref bool hasPath) pure
{
    size_t end = limit;
    const slash = indexOfCharFrom(spec, '/', start);
    if (slash >= 0 && cast(size_t) slash <= limit)
    {
        end = cast(size_t) slash;
    }
    else
    {
        const q = indexOfCharFrom(spec, '?', start);
        if (q >= 0 && cast(size_t) q <= limit)
            end = cast(size_t) q;
    }

    const authText = spec[start .. end];
    authority = OptString(authText, true);
    splitUserInfoAndHost(authText, userInfo, host);
    parseHostAndPort(authText, host, port);

    if (port < -1)
        throwMalformed("Invalid port number :" ~ signedDecimal(port));

    if (authText.length > 0)
    {
        path = "";
        hasPath = true;
    }
    return end;
}

private void splitUserInfoAndHost(string authText, out OptString userInfo, out OptString host) pure nothrow @nogc
{
    const atIdx = indexOfChar(authText, '@');
    if (atIdx < 0)
    {
        userInfo = OptString.init;
        host = OptString(authText, true);
        return;
    }
    if (atIdx != lastIndexOfChar(authText, '@'))
    {
        userInfo = OptString.init;
        host = OptString.init;
        return;
    }
    userInfo = OptString(authText[0 .. atIdx], true);
    host = OptString(authText[atIdx + 1 .. $], true);
}

private void parseHostAndPort(string authText, ref OptString host, ref int port) pure
{
    if (!host.present)
    {
        host = OptString("", true);
        return;
    }
    if (host.value.length > 0 && host.value[0] == '[')
    {
        parseBracketedHostAndPort(authText, host, port);
        return;
    }
    const colonIdx = indexOfChar(host.value, ':');
    port = -1;
    if (colonIdx >= 0)
    {
        if (host.value.length > cast(size_t) colonIdx + 1)
            port = parseJavaPort(host.value[colonIdx + 1 .. $]);
        host = OptString(host.value[0 .. colonIdx], true);
    }
}

private void parseBracketedHostAndPort(string authText, ref OptString host, ref int port) pure
{
    const nhost = host.value;
    const closeIdx = indexOfChar(nhost, ']');
    if (closeIdx <= 2)
        throwMalformed("Invalid authority field: " ~ authText);

    const hostBracket = nhost[0 .. closeIdx + 1];
    host = OptString(hostBracket, true);
    if (!validIpv6(nhost[1 .. closeIdx]))
        throwMalformed("Invalid host: " ~ hostBracket);

    port = -1;
    if (nhost.length > cast(size_t) closeIdx + 1)
    {
        if (nhost[closeIdx + 1] != ':')
            throwMalformed("Invalid authority field: " ~ authText);
        if (nhost.length > cast(size_t) closeIdx + 2)
            port = parseJavaPort(nhost[closeIdx + 2 .. $]);
    }
}

private string resolveHierarchicalPath(string spec, size_t start, size_t limit, bool hasAuthority,
        bool queryOnly, string path, bool hasPath) pure nothrow
{
    bool isRelPath;
    if (start < limit)
    {
        const specStr = spec[start .. limit];
        if (spec[start] == '/')
        {
            path = specStr;
        }
        else if (path.length > 0)
        {
            isRelPath = true;
            const lastSlash = lastIndexOfChar(path, '/');
            path = (lastSlash < 0 && hasAuthority) ? ("/" ~ specStr) : (path[0 .. lastSlash + 1] ~ specStr);
        }
        else
        {
            path = hasAuthority ? ("/" ~ specStr) : specStr;
        }
    }
    else if (queryOnly && hasPath)
    {
        const lastSlash = lastIndexOfChar(path, '/');
        path = lastSlash < 0 ? "/" : path[0 .. lastSlash + 1];
    }
    return isRelPath ? canonicalizeRelPath(path) : path;
}

private string canonicalizeRelPath(string path) pure nothrow
{
    ptrdiff_t i;
    while ((i = indexOfStr(path, "/./")) >= 0)
        path = path[0 .. i] ~ path[i + 2 .. $];

    size_t scanPos = 0;
    while ((i = indexOfStr(path, "/../", scanPos)) >= 0)
    {
        ptrdiff_t prev = i > 0 ? lastIndexOfCharBefore(path, '/', cast(size_t)(i - 1)) : -1;
        if (i > 0 && prev >= 0 && indexOfStr(path, "/../", cast(size_t) prev) != 0)
        {
            path = path[0 .. prev] ~ path[i + 3 .. $];
            scanPos = 0;
        }
        else
        {
            scanPos = cast(size_t) i + 3;
        }
    }

    while (path.length >= 3 && path[$ - 3 .. $] == "/..")
    {
        i = indexOfStr(path, "/..");
        const prev = i > 0 ? lastIndexOfCharBefore(path, '/', cast(size_t)(i - 1)) : -1;
        if (prev >= 0)
            path = path[0 .. prev + 1];
        else
            break;
    }

    if (path.length > 2 && path[0 .. 2] == "./")
        path = path[2 .. $];

    if (path.length >= 2 && path[$ - 2 .. $] == "/.")
        path = path[0 .. $ - 1];

    return path;
}

private string canonicalizeJarString(string file, size_t off) pure nothrow
{
    if (off >= file.length || (indexOfStr(file, "./", off) < 0 && file[$ - 1] != '.'))
        return file;
    string after = file[off .. $];
    ptrdiff_t i;
    while ((i = indexOfStr(after, "/../")) >= 0)
    {
        const prev = i > 0 ? lastIndexOfCharBefore(after, '/', cast(size_t)(i - 1)) : -1;
        if (prev >= 0)
            after = after[0 .. prev] ~ after[i + 3 .. $];
        else
            after = after[i + 3 .. $];
    }
    while ((i = indexOfStr(after, "/./")) >= 0)
        after = after[0 .. i] ~ after[i + 2 .. $];
    while (after.length >= 3 && after[$ - 3 .. $] == "/..")
    {
        i = indexOfStr(after, "/..");
        const prev = i > 0 ? lastIndexOfCharBefore(after, '/', cast(size_t)(i - 1)) : -1;
        if (prev >= 0)
            after = after[0 .. prev + 1];
        else
            after = after[0 .. i];
    }
    if (after.length >= 2 && after[$ - 2 .. $] == "/.")
        after = after[0 .. $ - 1];
    return file[0 .. off] ~ after;
}

// OpenJDK sun.net.util.IPAddressUtil masks (earlyURLParsing = true).
private enum ulong L_IPV6_DELIMS = 0x0UL;
private enum ulong H_IPV6_DELIMS = 0x28000000UL;
private enum ulong L_AUTH_DELIMS = 0x400000000000000UL;
private enum ulong H_AUTH_DELIMS = 0x28000001UL;
private enum ulong L_COLON = 0x400000000000000UL;
private enum ulong H_COLON = 0x0UL;
private enum ulong L_SLASH = 0x800000000000UL;
private enum ulong H_SLASH = 0x0UL;
private enum ulong L_BACKSLASH = 0x0UL;
private enum ulong H_BACKSLASH = 0x10000000UL;
private enum ulong L_NON_PRINTABLE = 0xffffffffUL;
private enum ulong H_NON_PRINTABLE = 0x8000000000000000UL;
private enum ulong L_EXCLUDE = 0x84008008ffffffffUL;
private enum ulong H_EXCLUDE = 0x8000000038000001UL;
private enum ulong L_EXCLUDED_DELIMS = 0x5000000500000000UL;
private enum ulong H_EXCLUDED_DELIMS = 0x0UL;
private enum ulong L_UNWISE = 0x0UL;
private enum ulong H_UNWISE = 0x3800000178000000UL;
private enum ulong L_FRAGMENT = 0x0000000800000000UL;
private enum ulong H_FRAGMENT = 0x0UL;
private enum ulong L_QUERY = 0x8000000000000000UL;
private enum ulong H_QUERY = 0x0UL;

private enum ulong L_USERINFO_MASK = L_EXCLUDE & ~L_COLON;
private enum ulong H_USERINFO_MASK = H_EXCLUDE & ~H_COLON;
private enum ulong L_HOSTNAME_MASK = L_NON_PRINTABLE | L_SLASH | L_UNWISE | L_EXCLUDED_DELIMS;
private enum ulong H_HOSTNAME_MASK = H_NON_PRINTABLE | H_SLASH | H_UNWISE | H_EXCLUDED_DELIMS;
private enum ulong L_SCOPE_MASK = L_NON_PRINTABLE | L_IPV6_DELIMS | L_SLASH | L_BACKSLASH | L_FRAGMENT | L_QUERY;
private enum ulong H_SCOPE_MASK = H_NON_PRINTABLE | H_IPV6_DELIMS | H_SLASH | H_BACKSLASH | H_FRAGMENT | H_QUERY;

private static immutable ushort[17] OTHERS_BMP = [
    8263, 8264, 8265, 8448, 8449, 8453, 8454, 10_868, 65_109, 65_110, 65_119, 65_131, 65_283,
    65_295, 65_306, 65_311, 65_312
];

private bool matchMask(dchar c, ulong lowMask, ulong highMask) pure nothrow @nogc
{
    if (c < 64)
        return ((1UL << c) & lowMask) != 0;
    if (c < 128)
        return ((1UL << (c - 64)) & highMask) != 0;
    return false;
}

private bool isOtherHostChar(dchar c) pure nothrow @nogc
{
    if (c < 8263 || c > 65_312)
        return false;
    foreach (entry; OTHERS_BMP)
        if (entry == c)
            return true;
    return false;
}

private dchar scanMask(scope const(char)[] s, ulong lowMask, ulong highMask, bool checkOthers) pure nothrow @nogc
{
    size_t i = 0;
    while (i < s.length)
    {
        const b = s[i];
        dchar c;
        if (b < 0x80)
        {
            c = b;
            ++i;
        }
        else
        {
            c = decodeUtf8(s, i);
        }
        if (matchMask(c, lowMask, highMask) || (checkOthers && isOtherHostChar(c)))
            return c;
    }
    return dchar.max;
}

private string describeChar(dchar c) pure nothrow
{
    if (c < 32 || c == 127)
    {
        if (c == '\n')
            return "LF";
        if (c == '\r')
            return "CR";
        return "control char (code=" ~ decimal(cast(ulong) c) ~ ")";
    }
    if (c == '\\')
        return "'\\'";
    const encoded = utf8(c);
    return "'" ~ (encoded !is null ? encoded : "?") ~ "'";
}

private string checkUserInfo(string str) pure nothrow
{
    const bad = scanMask(str, L_USERINFO_MASK, H_USERINFO_MASK, false);
    if (bad != dchar.max)
        return "Illegal character found in user-info: " ~ describeChar(bad);
    return null;
}

private string checkHost(string str) pure nothrow
{
    if (str.length >= 2 && str[0] == '[' && str[$ - 1] == ']')
    {
        const inner = str[1 .. $ - 1];
        if (validIpv6(inner))
        {
            const pct = indexOfChar(inner, '%');
            if (pct >= 0)
            {
                const bad = scanMask(inner[pct .. $], L_SCOPE_MASK, H_SCOPE_MASK, false);
                if (bad != dchar.max)
                    return "Illegal character found in IPv6 scoped address: " ~ describeChar(bad);
            }
            return null;
        }
        return "Unrecognized IPv6 address format";
    }

    const bad = scanMask(str, L_EXCLUDE | L_HOSTNAME_MASK, H_EXCLUDE | H_HOSTNAME_MASK, true);
    if (bad != dchar.max)
        return "Illegal character found in host: " ~ describeChar(bad);
    return null;
}

private string checkAuth(string str) pure nothrow
{
    const bad = scanMask(str, L_EXCLUDE & ~L_AUTH_DELIMS, H_EXCLUDE & ~H_AUTH_DELIMS, false);
    if (bad != dchar.max)
        return "Illegal character found in authority: " ~ describeChar(bad);
    return null;
}

private string checkExternalForm(const OptString userInfo, const OptString host) pure nothrow
{
    if (userInfo.present)
    {
        const err = checkUserInfo(userInfo.value);
        if (err !is null)
            return err;
    }
    if (host.present)
        return checkHost(host.value);
    return null;
}
