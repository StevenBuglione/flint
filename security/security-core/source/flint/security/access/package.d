// Ported from spring-security 7.2.0: core/src/main/java/org/springframework/security/access/AccessDeniedException.java
// Copyright 2004-present the original author or authors.
// Licensed under the Apache License, Version 2.0.
// Modified by the Flint authors.

/++
`org.springframework.security.access`: access-denied failures.
+/
module flint.security.access;

import flint.java.lang : RuntimeException;

@safe:

/// Thrown when an authenticated principal lacks permission (Spring Security's `AccessDeniedException`).
class AccessDeniedException : RuntimeException
{
    /// A failure with `message`.
    this(string message, string file = __FILE__, size_t line = __LINE__) pure nothrow
    {
        super(message);
        // Preserve the caller location across both RuntimeException constructor layouts.
        this.file = file;
        this.line = line;
    }

    /// A failure with an initialized cause.
    this(string message, Throwable cause, string file = __FILE__, size_t line = __LINE__) pure nothrow
    {
        super(message, cause, file, line);
    }

    /// Select the cause overload for a null literal.
    this(string message, typeof(null), string file = __FILE__, size_t line = __LINE__) pure nothrow
    {
        this(message, cast(Throwable) null, file, line);
    }
}
