// Ported from spring-security 7.2.0: web/src/main/java/org/springframework/security/web/header
// Copyright 2004-present the original author or authors.
// Licensed under the Apache License, Version 2.0.
// Modified by the Flint authors.
/*
 * Ported from spring-security 7.2.0, web/src/main/java/org/springframework/security/web/header/{HeaderWriter,
 * HeaderWriterFilter}.java and header/writers/{XContentTypeOptionsHeaderWriter,XXssProtectionHeaderWriter,
 * CacheControlHeadersWriter,HstsHeaderWriter,StaticHeadersWriter}.java and writers/frameoptions/
 * XFrameOptionsHeaderWriter.java. HeaderWriterFilter writes the headers before the rest of the chain (Spring's
 * shouldWriteHeadersEagerly), since the servlet port has no response wrapper yet; the response is the same unless
 * the application sets Cache-Control, Expires or Pragma itself.
 */

/++
`org.springframework.security.web.header`: the security response headers.
+/
module flint.security.web.header;

import flint.engine.aot.fast : FastField;
import flint.jakarta.servlet : FilterChain;
import flint.jakarta.servlet.http : HttpServletRequest, HttpServletResponse;
import flint.security.web : SecurityFilter;

@safe:

// Whether `written` holds a field `name` (header names compare case-insensitively, as containsHeader does).
private bool present(const(FastField)[] written, string name) pure nothrow @nogc
{
    foreach (ref field; written)
    {
        if (field.name.length != name.length)
            continue;
        bool same = true;
        foreach (index, c; name)
        {
            char a = c, b = field.name[index];
            if (a >= 'A' && a <= 'Z')
                a += 32;
            if (b >= 'A' && b <= 'Z')
                b += 32;
            same = same && a == b;
        }
        if (same)
            return true;
    }
    return false;
}

/// Writes headers to a response (Spring Security's `HeaderWriter`).
interface HeaderWriter
{
    /// Write the headers.
    void writeHeaders(HttpServletRequest request, HttpServletResponse response);
}

/// Spring Security's `HeaderWriterFilter`.
class HeaderWriterFilter : SecurityFilter
{
    private HeaderWriter[] headerWriters;

    /// A filter applying `headerWriters` in order.
    this(HeaderWriter[] headerWriters...)
    {
        this.headerWriters = headerWriters.dup;
    }

    override void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain)
    {
        foreach (writer; headerWriters)
            writer.writeHeaders(request, response);
        chain.doFilter(request, response);
    }

    /++
    Flint's fast path (fast-path.md S4): the fields every writer writes on a fresh response, in order. Each writer
    applies its own presence rule to the fields written before it, as `writeHeaders` applies it to the response, and
    shares its names and values with `writeHeaders`. `false` for a writer of another type, whose effect is unknown.
    +/
    package(flint.security) bool fastFields(bool secure, out FastField[] fields)
    {
        foreach (writer; headerWriters)
        {
            if (auto known = cast(XContentTypeOptionsHeaderWriter) writer)
                known.appendFields(secure, fields);
            else if (auto known = cast(XXssProtectionHeaderWriter) writer)
                known.appendFields(secure, fields);
            else if (auto known = cast(CacheControlHeadersWriter) writer)
                known.appendFields(secure, fields);
            else if (auto known = cast(HstsHeaderWriter) writer)
                known.appendFields(secure, fields);
            else if (auto known = cast(XFrameOptionsHeaderWriter) writer)
                known.appendFields(secure, fields);
            else if (auto known = cast(StaticHeadersWriter) writer)
                known.appendFields(secure, fields);
            else
                return false;
        }
        return true;
    }
}

/// `X-Content-Type-Options: nosniff`.
final class XContentTypeOptionsHeaderWriter : HeaderWriter
{
    private enum name = "X-Content-Type-Options";
    private enum value = "nosniff";

    /// Write it unless present.
    void writeHeaders(HttpServletRequest, HttpServletResponse response)
    {
        if (!response.containsHeader(name))
            response.setHeader(name, value);
    }

    package(flint.security) void appendFields(bool, ref FastField[] written)
    {
        if (!present(written, name))
            written ~= FastField(name, value);
    }
}

/// `X-XSS-Protection`: `0` by default (Spring Security 6's `HeaderValue.DISABLED`).
final class XXssProtectionHeaderWriter : HeaderWriter
{
    private enum name = "X-XSS-Protection";

    /// The header values.
    enum HeaderValue : string
    {
        DISABLED = "0", ///
        ENABLED = "1", ///
        ENABLED_MODE_BLOCK = "1; mode=block", ///
    }

    private HeaderValue headerValue = HeaderValue.DISABLED;

    /// Set the value.
    void setHeaderValue(HeaderValue headerValue) pure nothrow @nogc
    {
        this.headerValue = headerValue;
    }

    /// Write it unless present.
    void writeHeaders(HttpServletRequest, HttpServletResponse response)
    {
        if (!response.containsHeader(name))
            response.setHeader(name, headerValue);
    }

    package(flint.security) void appendFields(bool, ref FastField[] written)
    {
        if (!present(written, name))
            written ~= FastField(name, headerValue);
    }
}

/// `Cache-Control: no-cache, no-store, max-age=0, must-revalidate`, `Pragma: no-cache`, `Expires: 0`, unless the
/// response already sets one of them (Spring Security's `CacheControlHeadersWriter`).
final class CacheControlHeadersWriter : HeaderWriter
{
    private static immutable FastField[3] fields = [
        FastField("Cache-Control", "no-cache, no-store, max-age=0, must-revalidate"),
        FastField("Pragma", "no-cache"), FastField("Expires", "0")
    ];

    /// Write them unless any is present.
    void writeHeaders(HttpServletRequest, HttpServletResponse response)
    {
        if (response.getHeader("Cache-Control") !is null || response.getHeader("Expires") !is null
                || response.getHeader("Pragma") !is null)
            return;
        foreach (ref field; fields)
            response.setHeader(field.name, field.value);
    }

    package(flint.security) void appendFields(bool, ref FastField[] written)
    {
        if (present(written, "Cache-Control") || present(written, "Expires") || present(written, "Pragma"))
            return;
        written ~= fields[];
    }
}

/// `Strict-Transport-Security` on secure requests (Spring Security's `HstsHeaderWriter`).
final class HstsHeaderWriter : HeaderWriter
{
    private enum name = "Strict-Transport-Security";

    private long maxAgeInSeconds = 31_536_000;
    private bool includeSubDomains = true;
    private bool preload;

    /// The max age.
    void setMaxAgeInSeconds(long maxAgeInSeconds) pure nothrow @nogc
    {
        this.maxAgeInSeconds = maxAgeInSeconds;
    }

    /// Whether to include subdomains.
    void setIncludeSubDomains(bool includeSubDomains) pure nothrow @nogc
    {
        this.includeSubDomains = includeSubDomains;
    }

    /// Write it on secure requests, unless present.
    void writeHeaders(HttpServletRequest request, HttpServletResponse response)
    {
        if (!request.isSecure() || response.containsHeader(name))
            return;
        response.setHeader(name, value());
    }

    package(flint.security) void appendFields(bool secure, ref FastField[] written)
    {
        if (secure && !present(written, name))
            written ~= FastField(name, value());
    }

    private string value() const
    {
        import flint.java.lang : valueOf;

        return "max-age=" ~ valueOf(maxAgeInSeconds) ~ (includeSubDomains
                ? " ; includeSubDomains" : "") ~ (preload ? " ; preload" : "");
    }
}

/// `X-Frame-Options` (Spring Security's `XFrameOptionsHeaderWriter`).
final class XFrameOptionsHeaderWriter : HeaderWriter
{
    private enum name = "X-Frame-Options";

    /// The policies.
    enum XFrameOptionsMode : string
    {
        DENY = "DENY", ///
        SAMEORIGIN = "SAMEORIGIN", ///
    }

    private XFrameOptionsMode mode;

    /// A writer for `mode` (`DENY` by default).
    this(XFrameOptionsMode mode = XFrameOptionsMode.DENY) pure nothrow @nogc
    {
        this.mode = mode;
    }

    /// Write it unless present.
    void writeHeaders(HttpServletRequest, HttpServletResponse response)
    {
        if (!response.containsHeader(name))
            response.setHeader(name, mode);
    }

    package(flint.security) void appendFields(bool, ref FastField[] written)
    {
        if (!present(written, name))
            written ~= FastField(name, mode);
    }
}

/// Fixed headers (Spring Security's `StaticHeadersWriter`).
final class StaticHeadersWriter : HeaderWriter
{
    private string name;
    private string[] values;

    /// A writer of `name: values`.
    this(string name, string[] values...)
    {
        this.name = name;
        this.values = values.dup;
    }

    /// Add each value unless the header is present.
    void writeHeaders(HttpServletRequest, HttpServletResponse response)
    {
        if (response.containsHeader(name))
            return;
        foreach (value; values)
            response.addHeader(name, value);
    }

    package(flint.security) void appendFields(bool, ref FastField[] written)
    {
        if (present(written, name))
            return;
        foreach (value; values)
            written ~= FastField(name, value);
    }
}
