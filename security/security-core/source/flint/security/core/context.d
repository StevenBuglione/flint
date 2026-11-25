// Ported from spring-security 7.2.0: core/src/main/java/org/springframework/security/core/context
// Copyright 2004-present the original author or authors.
// Licensed under the Apache License, Version 2.0.
// Modified by the Flint authors.
/*
 * Ported from spring-security 7.2.0, core/src/main/java/org/springframework/security/core/context/{SecurityContext,
 * SecurityContextImpl,SecurityContextHolder,SecurityContextHolderStrategy}.java. The holder keeps its context in a
 * FiberLocal (Java's ThreadLocalSecurityContextHolderStrategy), so each request fiber has its own; the global and
 * inheritable strategies and setStrategyName are not ported (no mutable module state).
 */

/++
`org.springframework.security.core.context`: the current fiber's security context.
+/
module flint.security.core.context;

import flint.engine.reactor : FiberLocal;
import flint.java.lang : IllegalStateException, javaEquals, javaHashCode, valueOf;
import flint.security.core : Authentication;

@safe:

/// The security information of the current execution (Spring Security's `SecurityContext`).
interface SecurityContext
{
    /// The current authentication, or null.
    Authentication getAuthentication();
    /// Set the authentication; null clears it.
    void setAuthentication(Authentication authentication);
}

/// Spring Security's `SecurityContextImpl`.
class SecurityContextImpl : SecurityContext
{
    private Authentication authentication;

    /// An empty context.
    this() pure nothrow @nogc
    {
    }

    /// A context holding `authentication`.
    this(Authentication authentication) pure nothrow @nogc
    {
        this.authentication = authentication;
    }

    /// The authentication, or null.
    Authentication getAuthentication()
    {
        return authentication;
    }

    /// Set the authentication.
    void setAuthentication(Authentication authentication)
    {
        this.authentication = authentication;
    }

    /// Equal authentications.
    override bool opEquals(Object obj)
    {
        auto that = cast(SecurityContextImpl) obj;
        if (that is null)
            return false;
        if (authentication is null || that.authentication is null)
            return authentication is that.authentication;
        return javaEquals(authentication, that.authentication);
    }

    /// The authentication's hash, or -1.
    override size_t toHash()
    {
        return authentication is null ? size_t.max : javaHashCode(authentication);
    }

    /// `SecurityContextImpl [Authentication=...]` or `SecurityContextImpl [Null authentication]`.
    override string toString()
    {
        if (authentication is null)
            return "SecurityContextImpl [Null authentication]";
        return "SecurityContextImpl [Authentication=" ~ valueOf(cast(Object) authentication) ~ "]";
    }
}

/// How the holder stores the context (Spring Security's `SecurityContextHolderStrategy`).
interface SecurityContextHolderStrategy
{
    /// Forget the current context.
    void clearContext();
    /// The current context, created empty when absent.
    SecurityContext getContext();
    /// Replace the current context. Throws `IllegalArgumentException` for null.
    void setContext(SecurityContext context);
    /// A new empty context.
    SecurityContext createEmptyContext();
}

/++
Flint: a context the holder creates only when it is first read (Spring Security 6's deferred context,
`SecurityContextHolderStrategy.setDeferredContext(Supplier)`). The holder stores this placeholder, and `getContext`
replaces it with `materialize()`'s context on the first read, so a request that never reads its context never
builds one (`AnonymousAuthenticationFilter`'s anonymous token). The placeholder itself never leaves the holder; it
holds no per-request state, so one instance may be stored for every request.
+/
abstract class DeferredSecurityContext : SecurityContext
{
    /// The context to use from the first read on (Spring's `Supplier.get`).
    abstract SecurityContext materialize();

    /// Never called: the holder materializes the context before anyone reads it.
    final Authentication getAuthentication()
    {
        throw new IllegalStateException("a deferred security context is read through SecurityContextHolder");
    }

    /// Never called: the holder materializes the context before anyone changes it.
    final void setAuthentication(Authentication)
    {
        throw new IllegalStateException("a deferred security context is changed through SecurityContextHolder");
    }
}

private shared FiberLocal!SecurityContext contextHolder;

// The fiber's context, materializing a deferred one; created empty and stored when absent.
private SecurityContext currentContext()
{
    auto context = contextHolder.get();
    if (auto deferred = cast(DeferredSecurityContext) context)
    {
        context = deferred.materialize();
        if (context is null)
            context = new SecurityContextImpl;
        storeContext(context);
        return context;
    }
    if (context is null)
    {
        context = new SecurityContextImpl;
        storeContext(context);
    }
    return context;
}

private void storeContext(SecurityContext context)
{
    const stored = contextHolder.set(context);
    if (stored.code != 0)
        throw new IllegalStateException("Could not store the security context: " ~ stored.message);
}

private void replaceContext(SecurityContext context)
{
    if (context is null)
        throw new imported!"flint.java.lang".IllegalArgumentException(
                "Only non-null SecurityContext instances are permitted");
    storeContext(context);
}

/// The fiber-local strategy (Java's `ThreadLocalSecurityContextHolderStrategy`).
final class FiberLocalSecurityContextHolderStrategy : SecurityContextHolderStrategy
{
    /// Forget the fiber's context.
    void clearContext()
    {
        contextHolder.remove();
    }

    /// The fiber's context, created and stored when absent; a deferred one is materialized on this first read.
    SecurityContext getContext()
    {
        return currentContext();
    }

    /// Store `context` for the fiber.
    void setContext(SecurityContext context)
    {
        replaceContext(context);
    }

    /// Flint: store `deferred` for the fiber, materialized on the first `getContext` (Spring's
    /// `setDeferredContext`).
    void setDeferredContext(DeferredSecurityContext deferred)
    {
        replaceContext(deferred);
    }

    /// A new `SecurityContextImpl`.
    SecurityContext createEmptyContext()
    {
        return new SecurityContextImpl;
    }
}

/// Associates the security context with the current fiber (Spring Security's `SecurityContextHolder`).
struct SecurityContextHolder
{
    // The static methods use the fiber-local storage directly, without a strategy object per call.

    /// Forget the current context.
    static void clearContext()
    {
        contextHolder.remove();
    }

    /// The current context, never null; a deferred one is materialized on this first read.
    static SecurityContext getContext()
    {
        return currentContext();
    }

    /// Replace the current context.
    static void setContext(SecurityContext context)
    {
        replaceContext(context);
    }

    /// Flint: a context materialized on the first `getContext` (Spring's `setDeferredContext`).
    static void setDeferredContext(DeferredSecurityContext deferred)
    {
        replaceContext(deferred);
    }

    /// Flint: whether the fiber holds a context (deferred or not), without creating or materializing one.
    static bool hasContext()
    {
        return contextHolder.get() !is null;
    }

    /// A new empty context.
    static SecurityContext createEmptyContext()
    {
        return new SecurityContextImpl;
    }

    /// The fiber-local strategy.
    static SecurityContextHolderStrategy getContextHolderStrategy()
    {
        return new FiberLocalSecurityContextHolderStrategy;
    }
}
