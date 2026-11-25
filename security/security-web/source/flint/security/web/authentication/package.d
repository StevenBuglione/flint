// Ported from spring-security 7.2.0: web/src/main/java/org/springframework/security/web/authentication
// Copyright 2004-present the original author or authors.
// Licensed under the Apache License, Version 2.0.
// Modified by the Flint authors.
/*
 * Ported from spring-security 7.2.0, web/src/main/java/org/springframework/security/web/authentication/{
 * AnonymousAuthenticationFilter,Http403ForbiddenEntryPoint}.java.
 */

/++
`org.springframework.security.web.authentication`: anonymous authentication and the default entry point.
+/
module flint.security.web.authentication;

import flint.engine.aot.any : Any;
import flint.jakarta.servlet : FilterChain;
import flint.jakarta.servlet.http : HttpServletRequest, HttpServletResponse;
import flint.security.authentication : AnonymousAuthenticationToken;
import flint.security.core : Authentication, AuthenticationException, AuthorityUtils, GrantedAuthority;
import flint.security.core.context : DeferredSecurityContext, SecurityContext, SecurityContextHolder;
import flint.security.web : AuthenticationEntryPoint, SecurityFilter;

@safe:

/// Sets an anonymous authentication when there is none (Spring Security's `AnonymousAuthenticationFilter`).
class AnonymousAuthenticationFilter : SecurityFilter
{
    private string key;
    private Any principal;
    private GrantedAuthority[] authorities;
    private AnonymousByDefault deferred;

    /// A filter with principal `anonymousUser` and authority `ROLE_ANONYMOUS`.
    this(string key)
    {
        this(key, Any.of("anonymousUser"), AuthorityUtils.createAuthorityList("ROLE_ANONYMOUS"));
    }

    /// A filter with `principal` and `authorities`.
    this(string key, Any principal, GrantedAuthority[] authorities)
    {
        this.key = key;
        this.principal = principal;
        this.authorities = authorities;
        deferred = new AnonymousByDefault(this);
    }

    override void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain)
    {
        populate();
        chain.doFilter(request, response);
    }

    /++
    The anonymous token, unless the context holds an authentication; Flint's fast path runs it too (S4). As in
    Spring Security 6 (`defaultWithAnonymous` over the deferred context), the token is made when the context is
    first read: a fiber without a context gets a deferred one, which `SecurityContextHolder.getContext` turns into a
    context holding the token, so a request that never reads its context builds neither. A context already there is
    completed now, as Spring's supplier would complete it on its first read.
    +/
    package(flint.security) void populate()
    {
        if (!SecurityContextHolder.hasContext())
        {
            SecurityContextHolder.setDeferredContext(deferred);
            return;
        }
        auto context = SecurityContextHolder.getContext();
        if (context.getAuthentication() is null)
            context.setAuthentication(anonymousToken());
    }

    private Authentication anonymousToken()
    {
        return new AnonymousAuthenticationToken(key, principal, authorities);
    }
}

// The filter's deferred context: an empty context holding the anonymous token, made on the first read. One per
// filter, read-only, so every request stores the same instance.
private final class AnonymousByDefault : DeferredSecurityContext
{
    private AnonymousAuthenticationFilter filter;

    this(AnonymousAuthenticationFilter filter) pure nothrow @nogc
    {
        this.filter = filter;
    }

    override SecurityContext materialize()
    {
        auto context = SecurityContextHolder.createEmptyContext();
        context.setAuthentication(filter.anonymousToken());
        return context;
    }
}

/// Answers `403 Forbidden` (Spring Security's `Http403ForbiddenEntryPoint`, the default without a login method).
class Http403ForbiddenEntryPoint : AuthenticationEntryPoint
{
    /// `sendError(403, "Access Denied")`.
    void commence(HttpServletRequest, HttpServletResponse response, AuthenticationException)
    {
        response.sendError(HttpServletResponse.SC_FORBIDDEN, "Access Denied");
    }
}
