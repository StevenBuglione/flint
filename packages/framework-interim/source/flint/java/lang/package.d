/++
Interim stand-in for framework-core's `flint.java.lang` (ADR-030, rulebook R8).

It declares only the exceptions the web packages throw, with Java's names and hierarchy. It is deleted the
day framework-core's `flint:java` lands; nothing here is a design of that package.
+/
module flint.java.lang;

@safe:

/// `java.lang.RuntimeException`.
class RuntimeException : Exception
{
    /// Java's `(String message, Throwable cause)` constructor.
    this(string message = null, Throwable cause = null, string file = __FILE__, size_t line = __LINE__)
        pure nothrow @nogc
    {
        super(message, file, line, cause);
    }

    /// Java's `getMessage()`; `null` when no message was given.
    string getMessage() const pure nothrow @nogc
    {
        return msg;
    }

    /// Java's `getCause()`.
    inout(Throwable) getCause() inout pure nothrow @nogc
    {
        return next;
    }
}

/// `java.lang.IllegalArgumentException`.
class IllegalArgumentException : RuntimeException
{
    /// Java's constructors.
    this(string message = null, Throwable cause = null, string file = __FILE__, size_t line = __LINE__)
        pure nothrow @nogc
    {
        super(message, cause, file, line);
    }
}

/// `java.lang.IllegalStateException`.
class IllegalStateException : RuntimeException
{
    /// Java's constructors.
    this(string message = null, Throwable cause = null, string file = __FILE__, size_t line = __LINE__)
        pure nothrow @nogc
    {
        super(message, cause, file, line);
    }
}

/// `java.lang.UnsupportedOperationException`.
class UnsupportedOperationException : RuntimeException
{
    /// Java's constructors.
    this(string message = null, Throwable cause = null, string file = __FILE__, size_t line = __LINE__)
        pure nothrow @nogc
    {
        super(message, cause, file, line);
    }
}

/// `java.lang.NumberFormatException`.
class NumberFormatException : IllegalArgumentException
{
    /// Java's constructors.
    this(string message = null, Throwable cause = null, string file = __FILE__, size_t line = __LINE__)
        pure nothrow @nogc
    {
        super(message, cause, file, line);
    }
}
