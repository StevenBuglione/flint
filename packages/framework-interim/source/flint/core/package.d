/++
Interim conformance copy of spring-core's `flint.core.NestedRuntimeException` (framework-core owns it;
deleted when `flint:core` lands).
+/
module flint.core;

import flint.java.lang : RuntimeException;

@safe:

/// `org.springframework.core.NestedRuntimeException`.
abstract class NestedRuntimeException : RuntimeException
{
    ///
    this(string message, Throwable cause = null, string file = __FILE__, size_t line = __LINE__) pure nothrow @nogc
    {
        super(message, cause, file, line);
    }

    /// The innermost cause, or `null` when there is none.
    final Throwable getRootCause() pure nothrow @nogc
    {
        Throwable rootCause = null;
        Throwable cause = next;
        while (cause !is null && cause !is rootCause)
        {
            rootCause = cause;
            cause = cause.next;
        }
        return rootCause;
    }

    /// The root cause, or this exception.
    final Throwable getMostSpecificCause() pure nothrow @nogc
    {
        auto rootCause = getRootCause();
        return rootCause !is null ? rootCause : this;
    }
}
