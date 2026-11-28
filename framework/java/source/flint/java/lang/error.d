// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
/++
Java's `java.lang.Error` and `java.lang.AssertionError`.

Java's `Error`s that application code catches map to D `Exception`s (rule R8), because D's `Error` skips cleanup.
`AssertionError` therefore extends this `Error_` rather than D's.
+/
module flint.java.lang.error;

import flint.engine.aot.name : CanonicalName, typeNameOf;
import flint.java.lang.runtimeexception : CanonicalRuntimeName, javaToString;

@safe:

/++
Java's `Error` (`Error_`, R19): the root of the throwables an application normally does not catch.

Mapped to a D `Exception` (R8). The cause is kept separately and read with `getCause`, as `RuntimeException` does.
+/
@CanonicalName("flint.java.lang.Error_")
class Error_ : Exception
{
    private Throwable cause_;

    /// No message and no cause.
    this() pure nothrow
    {
        super(null);
    }

    /// `message`, with no cause.
    this(string message, string file = __FILE__, size_t line = __LINE__) pure nothrow
    {
        super(message, file, line);
    }

    /// `message` and a `cause`.
    this(string message, Throwable cause, string file = __FILE__, size_t line = __LINE__) pure nothrow
    {
        super(message, file, line);
        cause_ = cause;
    }

    /// Java's `Error(Throwable cause)`: the message is `cause.toString()`, or null.
    this(Throwable cause, string file = __FILE__, size_t line = __LINE__)
    {
        super(cause is null ? null : javaToString(cause), file, line);
        cause_ = cause;
    }

    /// The detail message; null when there is none.
    string getMessage() const pure nothrow @nogc
    {
        return msg;
    }

    /// The cause; null when unknown.
    inout(Throwable) getCause() inout pure nothrow @nogc
    {
        return cause_;
    }

    /// Java's `Throwable.toString()`: the class name, then `: message` when there is one.
    override string toString() const
    {
        return msg is null ? runtimeName : runtimeName ~ ": " ~ msg;
    }

    /// The class name this error reports; see `RuntimeException.runtimeName`.
    protected string runtimeName() const pure nothrow @nogc
    {
        alias Declared = typeof(cast() this);
        const actual = typeid(this);
        return actual is typeid(Declared) ? typeNameOf!Declared : actual.name;
    }
}

/++
Java's `AssertionError`.

Java's constructors take an `Object`, a primitive or a message-and-cause pair; this port keeps the
message-and-cause pair the framework uses, with the detail Java produces for a message.
+/
@CanonicalName("flint.java.lang.AssertionError")
class AssertionError : Error_
{
    /// `message`, and optionally a `cause`.
    this(string message = null, Throwable cause = null, string file = __FILE__, size_t line = __LINE__) pure nothrow
    {
        super(message, cause, file, line);
    }

    mixin CanonicalRuntimeName;
}
