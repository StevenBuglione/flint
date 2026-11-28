// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
/++
Java SE 21 `java.lang.InterruptedException`, implemented from the public contract.

A checked exception in Java; in D it is an `Exception` and the `throws` clauses are dropped (deviation D-8),
as for the other checked Java exceptions. The constructors, the detail message and the cause follow Java.
+/
module flint.java.lang.interruptedexception;

import flint.engine.aot.name : CanonicalName, typeNameOf;

@safe:

/// Thrown when a thread is interrupted while it is waiting, sleeping or otherwise occupied.
@CanonicalName("flint.java.lang.InterruptedException")
class InterruptedException : Exception
{
    private Throwable cause_;

    /// `message`, and optionally a `cause`; Java's `()`, `(String)` and `(String, Throwable)` constructors.
    this(string message = null, Throwable cause = null, string file = __FILE__, size_t line = __LINE__) pure nothrow
    {
        super(message, file, line);
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

    /// The class name this exception reports; see `RuntimeException.runtimeName`.
    protected string runtimeName() const pure nothrow @nogc
    {
        alias Declared = typeof(cast() this);
        const actual = typeid(this);
        return actual is typeid(Declared) ? typeNameOf!Declared : actual.name;
    }
}
