/++
Interim stand-in for framework-core's `flint.java.util.Optional` (rulebook R5): the methods the web
packages and their tests call. Deleted when `flint:java` lands.
+/
module flint.java.util;

@safe:

/// `java.util.NoSuchElementException`.
class NoSuchElementException : imported!"flint.java.lang".RuntimeException
{
    ///
    this(string message = null, string file = __FILE__, size_t line = __LINE__) pure nothrow @nogc
    {
        super(message, null, file, line);
    }
}

/// `java.util.Optional<T>`.
struct Optional(T)
{
    private T value;
    private bool present;

    /// A present value.
    static Optional of(T value)
    {
        Optional result;
        result.value = value;
        result.present = true;
        return result;
    }

    /// The empty optional.
    static Optional empty() pure nothrow @nogc
    {
        return Optional.init;
    }

    /// Whether a value is present.
    bool isPresent() const pure nothrow @nogc
    {
        return present;
    }

    /// Whether no value is present.
    bool isEmpty() const pure nothrow @nogc
    {
        return !present;
    }

    /// The value. Throws: `NoSuchElementException` when empty.
    inout(T) get() inout
    {
        if (!present)
            throw new NoSuchElementException("No value present");
        return value;
    }

    /// The value, or `other`.
    inout(T) orElse(inout(T) other) inout
    {
        return present ? value : other;
    }
}
