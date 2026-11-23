/// Temporary stand-ins for `flint.java.lang`'s exception roots, which framework-core owns.
///
/// Boot's exceptions extend Java's `RuntimeException`, `IllegalArgumentException` and `IllegalStateException`
/// (rulebook R8). Until `flint:java` lands, Boot declares the same names here, privately. This file is deleted,
/// and its importers switch to `flint.java.lang`, the day framework-core's module is available.
module flint.boot.internal.lang;

@safe:

/// `java.lang.RuntimeException`.
class RuntimeException : Exception
{
    /// A message and an optional cause.
    this(string message, Throwable cause = null, string file = __FILE__, size_t line = __LINE__) pure nothrow
    {
        super(message, file, line, cause);
        this.message = message;
    }

    private string message;

    /// The cause, as Java's `getCause()`.
    final Throwable getCause() pure nothrow @nogc
    {
        return next;
    }

    /// The message, as Java's `getMessage()`.
    final string getMessage() const pure nothrow @nogc
    {
        return message;
    }
}

/// `java.lang.IllegalArgumentException`.
class IllegalArgumentException : RuntimeException
{
    /// A message and an optional cause.
    this(string message, Throwable cause = null, string file = __FILE__, size_t line = __LINE__) pure nothrow
    {
        super(message, cause, file, line);
    }
}

/// `java.lang.IllegalStateException`.
class IllegalStateException : RuntimeException
{
    /// A message and an optional cause.
    this(string message, Throwable cause = null, string file = __FILE__, size_t line = __LINE__) pure nothrow
    {
        super(message, cause, file, line);
    }
}

/// `java.lang.IndexOutOfBoundsException`.
class IndexOutOfBoundsException : RuntimeException
{
    /// A message.
    this(string message, string file = __FILE__, size_t line = __LINE__) pure nothrow
    {
        super(message, null, file, line);
    }
}
