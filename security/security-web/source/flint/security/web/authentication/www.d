// Ported from spring-security 7.2.0: web/src/main/java/org/springframework/security/web/authentication/www
// Copyright 2004-present the original author or authors.
// Licensed under the Apache License, Version 2.0.
// Modified by the Flint authors.
/*
 * Ported from spring-security 7.2.0, web/src/main/java/org/springframework/security/web/authentication/www/{
 * BasicAuthenticationFilter,BasicAuthenticationEntryPoint,BasicAuthenticationConverter}.java. Remember-me services
 * are not ported; credentials are decoded as UTF-8 (Spring's default charset).
 */

/++
`org.springframework.security.web.authentication.www`: HTTP Basic authentication.
+/
module flint.security.web.authentication.www;

import flint.engine.aot.any : Any;
import flint.jakarta.servlet : FilterChain;
import flint.jakarta.servlet.http : HttpServletRequest, HttpServletResponse;
import flint.java.lang : IllegalArgumentException;
import flint.security.authentication : AuthenticationManager, BadCredentialsException,
    UsernamePasswordAuthenticationToken;
import flint.security.core : AuthenticationException;
import flint.security.core.context : SecurityContextHolder, SecurityContextImpl;
import flint.security.web : AuthenticationEntryPoint, SecurityFilter;
import flint.security.web.context : SecurityContextRepository;
import std.typecons : Nullable;

@safe:

/// Answers `401` with `WWW-Authenticate: Basic realm="..."` (Spring Security's `BasicAuthenticationEntryPoint`).
class BasicAuthenticationEntryPoint : AuthenticationEntryPoint
{
    private Nullable!string realmName;

    /// Set the realm.
    void setRealmName(Nullable!string realmName) pure nothrow @nogc
    {
        this.realmName = realmName;
    }

    /// The realm.
    Nullable!string getRealmName() const pure nothrow @nogc
    {
        return realmName;
    }

    /// `WWW-Authenticate: Basic realm="<realm>"` and `sendError(401, "Unauthorized")`.
    void commence(HttpServletRequest request, HttpServletResponse response, AuthenticationException authException)
    {
        const realm = realmName.isNull ? "null" : realmName.get;
        response.setHeader("WWW-Authenticate", "Basic realm=\"" ~ realm ~ "\"");
        response.sendError(HttpServletResponse.SC_UNAUTHORIZED, "Unauthorized");
    }
}

/// Reads `Authorization: Basic <base64(user:password)>` (Spring Security's `BasicAuthenticationConverter`).
struct BasicAuthenticationConverter
{
    /// The unauthenticated token, or null without a Basic header. Throws `BadCredentialsException` for a malformed
    /// one.
    static UsernamePasswordAuthenticationToken convert(HttpServletRequest request)
    {
        auto header = request.getHeader("Authorization");
        if (header is null)
            return null;
        header = trim(header);
        if (header.length < 5 || !equalsIgnoreCase(header[0 .. 5], "basic"))
            return null;
        if (header.length == 5)
            throw new BadCredentialsException("Empty basic authentication token");
        const encoded = trim(header[6 .. $]);
        string token;
        if (!decodeBase64(encoded, token))
            throw new BadCredentialsException("Failed to decode basic authentication token");
        foreach (i, c; token)
            if (c == ':')
                return UsernamePasswordAuthenticationToken.unauthenticated(Any.of(token[0 .. i]),
                        Any.of(token[i + 1 .. $]));
        throw new BadCredentialsException("Invalid basic authentication token");
    }

    /++
    Java's `Base64.getDecoder().decode` (RFC 4648 basic alphabet), clean-room from the Java SE specification:
    padding is optional, but a padded final unit needs its full padding; any character outside the alphabet,
    padding before the end, or a final unit of one character fails. Not std.base64, whose object drags Phobos's
    exception, curl and socket objects into every executable (playbook S-9).
    +/
    private static bool decodeBase64(string encoded, out string decoded) pure nothrow
    {
        auto bytes = new char[encoded.length / 4 * 3 + 3];
        size_t length;
        uint bits;
        int count;
        size_t i;
        for (; i < encoded.length; i++)
        {
            const value = base64Value(encoded[i]);
            if (value < 0)
                break;
            bits = bits << 6 | value;
            if (++count == 4)
            {
                bytes[length++] = cast(char)(bits >> 16);
                bytes[length++] = cast(char)(bits >> 8);
                bytes[length++] = cast(char) bits;
                bits = 0;
                count = 0;
            }
        }
        if (count == 1)
            return false;
        // The rest may only be the final unit's padding: two '=' after two characters, one after three.
        const padding = encoded.length - i;
        if (padding != 0 && (count == 0 || padding != 4 - count))
            return false;
        foreach (c; encoded[i .. $])
            if (c != '=')
                return false;
        if (count == 2)
            bytes[length++] = cast(char)(bits >> 4);
        else if (count == 3)
        {
            bytes[length++] = cast(char)(bits >> 10);
            bytes[length++] = cast(char)(bits >> 2);
        }
        decoded = bytes[0 .. length].idup;
        return true;
    }

    private static int base64Value(char c) pure nothrow @nogc
    {
        if (c >= 'A' && c <= 'Z')
            return c - 'A';
        if (c >= 'a' && c <= 'z')
            return c - 'a' + 26;
        if (c >= '0' && c <= '9')
            return c - '0' + 52;
        return c == '+' ? 62 : c == '/' ? 63 : -1;
    }

    private static string trim(string text) pure nothrow @nogc
    {
        size_t start, end = text.length;
        while (start < end && (text[start] == ' ' || text[start] == '\t'))
            start++;
        while (end > start && (text[end - 1] == ' ' || text[end - 1] == '\t'))
            end--;
        return text[start .. end];
    }

    private static bool equalsIgnoreCase(string a, string b) pure nothrow @nogc
    {
        if (a.length != b.length)
            return false;
        foreach (i, c; a)
            if ((c | 0x20) != (b[i] | 0x20))
                return false;
        return true;
    }
}

/++
Spring Security's `BasicAuthenticationFilter`: authenticates the Basic credentials of a request through the
authentication manager; a failure clears the context and starts authentication at the entry point.
+/
class BasicAuthenticationFilter : SecurityFilter
{
    private AuthenticationManager authenticationManager;
    private AuthenticationEntryPoint authenticationEntryPoint;
    private SecurityContextRepository securityContextRepository;

    /// A filter authenticating with `authenticationManager` and failing at `authenticationEntryPoint`.
    this(AuthenticationManager authenticationManager, AuthenticationEntryPoint authenticationEntryPoint)
    {
        if (authenticationManager is null)
            throw new IllegalArgumentException("An AuthenticationManager is required");
        if (authenticationEntryPoint is null)
            throw new IllegalArgumentException("An AuthenticationEntryPoint is required");
        this.authenticationManager = authenticationManager;
        this.authenticationEntryPoint = authenticationEntryPoint;
    }

    /// Where the authenticated context is saved.
    void setSecurityContextRepository(SecurityContextRepository repository) pure nothrow @nogc
    {
        securityContextRepository = repository;
    }

    override void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain)
    {
        try
        {
            auto token = BasicAuthenticationConverter.convert(request);
            if (token !is null && authenticationIsRequired(token.getName()))
            {
                auto result = authenticationManager.authenticate(token);
                auto context = new SecurityContextImpl(result);
                SecurityContextHolder.setContext(context);
                if (securityContextRepository !is null)
                    securityContextRepository.saveContext(context, request, response);
            }
        }
        catch (AuthenticationException e)
        {
            SecurityContextHolder.clearContext();
            authenticationEntryPoint.commence(request, response, e);
            return;
        }
        chain.doFilter(request, response);
    }

    /// Whether the current authentication is absent, unauthenticated, anonymous or for another user.
    private static bool authenticationIsRequired(string username)
    {
        import flint.security.authentication : AnonymousAuthenticationToken;

        auto existing = SecurityContextHolder.getContext().getAuthentication();
        if (existing is null || !existing.isAuthenticated())
            return true;
        if (cast(AnonymousAuthenticationToken) existing !is null)
            return true;
        return existing.getName() != username;
    }
}

@("BasicAuthenticationConverter decodes Java's basic Base64: padded or not; rejects bad alphabet and padding")
unittest
{
    string token;
    assert(BasicAuthenticationConverter.decodeBase64("dXNlcjpwYXNz", token) && token == "user:pass");
    assert(BasicAuthenticationConverter.decodeBase64("YTpi", token) && token == "a:b");
    assert(BasicAuthenticationConverter.decodeBase64("YTpiYw==", token) && token == "a:bc");
    assert(BasicAuthenticationConverter.decodeBase64("YTpiYw", token) && token == "a:bc", "padding is optional");
    assert(BasicAuthenticationConverter.decodeBase64("YTpiYzE=", token) && token == "a:bc1");
    assert(BasicAuthenticationConverter.decodeBase64("", token) && token == "");
    assert(!BasicAuthenticationConverter.decodeBase64("YTpi*", token), "outside the alphabet");
    assert(!BasicAuthenticationConverter.decodeBase64("YTpiYw=", token), "partial padding");
    assert(!BasicAuthenticationConverter.decodeBase64("YT=pYw==", token), "padding before the end");
    assert(!BasicAuthenticationConverter.decodeBase64("YTpiY", token), "a dangling sixth bit group");
    assert(!BasicAuthenticationConverter.decodeBase64("YTpi====", token), "padding after a full unit");
}
