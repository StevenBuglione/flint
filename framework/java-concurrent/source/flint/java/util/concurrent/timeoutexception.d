/** Java SE 21 TimeoutException, implemented from the API specification. */
module flint.java.util.concurrent.timeoutexception;

@safe:

/// A timed operation expired before it could return its result (R1, R8).
class TimeoutException : Exception
{
    /// Creates a timeout with an optional detail message.
    this(string message = null, string file = __FILE__, size_t line = __LINE__) pure nothrow @nogc
    {
        super(message, file, line);
    }

    /// Returns the detail message, which may be null.
    string getMessage() const pure nothrow @nogc
    {
        return msg;
    }
}
