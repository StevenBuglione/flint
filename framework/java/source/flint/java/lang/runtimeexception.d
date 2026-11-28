// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
/++
Java's unchecked exception root, `java.lang.RuntimeException`, and the two exceptions its cause lifecycle throws.

`IllegalStateException` and `IllegalArgumentException` live in this leaf with `RuntimeException` because
`RuntimeException.initCause` throws them: a separate leaf for either would import this one and be imported by it,
a circular import. The package module `flint.java.lang` re-exports every name here.

Ports `java.lang.RuntimeException`, `java.lang.IllegalStateException` and `java.lang.IllegalArgumentException`
from OpenJDK 21.0.13 (R8). Modified by the Flint authors.
+/
module flint.java.lang.runtimeexception;

import flint.engine.aot.name : CanonicalName, typeNameOf;

@safe:

/// A trace that records nothing: set before throwing, druntime captures no stack trace.
private final class NoTrace : Throwable.TraceInfo
{
    override int opApply(scope int delegate(ref const(char[])) dg) const
    {
        return 0;
    }

    override int opApply(scope int delegate(ref size_t, ref const(char[])) dg) const
    {
        return 0;
    }

    override string toString() const
    {
        return "";
    }
}

/++
Java's `RuntimeException`: the root of the unchecked exceptions Spring throws.

D's `Throwable.next` chains collateral exceptions; Java's cause is kept separately and read with `getCause`.
+/
@CanonicalName("flint.java.lang.RuntimeException")
class RuntimeException : Exception
{
    private Throwable cause_;
    private bool causeSet;

    /// No message and no cause.
    this() pure nothrow
    {
        super(null);
    }

    /// `message`, with a cause that can still be initialized.
    this(string message, string file = __FILE__, size_t line = __LINE__) pure nothrow
    {
        super(message, file, line);
    }

    /// `message` and an initialized `cause`, including an explicit null.
    this(string message, Throwable cause, string file = __FILE__, size_t line = __LINE__) pure nothrow
    {
        this(message, file, line);
        cause_ = cause;
        causeSet = true;
    }

    /// Select the cause overload when the caller supplies a null literal.
    this(string message, typeof(null), string file = __FILE__, size_t line = __LINE__) pure nothrow
    {
        this(message, cast(Throwable) null, file, line);
    }

    /// Java's `RuntimeException(Throwable cause)`: the message is `cause.toString()`, or null.
    this(Throwable cause, string file = __FILE__, size_t line = __LINE__)
    {
        super(cause is null ? null : javaToString(cause), file, line);
        cause_ = cause;
        causeSet = true;
    }

    /++
    Java's protected four-argument constructor. With `writableStackTrace` false, throwing captures no stack
    trace: the framework's control-flow exceptions use it. Suppression is always enabled in D.
    +/
    protected this(string message, Throwable cause, bool enableSuppression, bool writableStackTrace,
            string file = __FILE__, size_t line = __LINE__) pure nothrow
    {
        this(message, cause, file, line);
        // druntime captures a trace only while `info` is null (rt.deh._d_createTrace).
        if (!writableStackTrace)
            info = new NoTrace;
    }

    /// The detail message; null when there is none.
    string getMessage() const pure nothrow @nogc
    {
        return msg;
    }

    /// `getMessage()`; subclasses may localize.
    string getLocalizedMessage() const pure nothrow @nogc
    {
        return getMessage();
    }

    /// The cause; null when unknown.
    inout(Throwable) getCause() inout pure nothrow @nogc
    {
        return cause_;
    }

    /// Set the cause once, as Java allows. Throws `IllegalStateException` when it was already set and
    /// `IllegalArgumentException` for a self-cause.
    RuntimeException initCause(Throwable cause)
    {
        if (causeSet)
            throw new IllegalStateException("Can't overwrite cause with " ~ (cause is null ? "a null" : javaToString(
                    cause)));
        if (cause is this)
            throw new IllegalArgumentException("Self-causation not permitted");
        cause_ = cause;
        causeSet = true;
        return this;
    }

    /// Java's `Throwable.toString()`: the class name, then `: message` when there is one.
    override string toString() const
    {
        return javaToString(this);
    }

    /// The class name this exception reports: its `@CanonicalName` when the runtime type is exactly this type,
    /// else its raw `typeid` name, so a port that moved into a leaf keeps its public name and a subclass keeps
    /// its own.
    protected string runtimeName() const pure nothrow @nogc
    {
        alias Declared = typeof(cast() this);
        const actual = typeid(this);
        return actual is typeid(Declared) ? typeNameOf!Declared : actual.name;
    }
}

/++
The `@CanonicalName` name of the declaring type when the runtime type is exactly that type, else the runtime type's
raw name. A moved class mixes in `CanonicalRuntimeName` to override `runtimeName`; a subclass that does not mix it
keeps its own `typeid` name through the inherited method.
+/
package(flint) mixin template CanonicalRuntimeName()
{
    /// The class name this exception reports; see `RuntimeException.runtimeName`.
    protected override string runtimeName() const pure nothrow @nogc
    {
        alias Declared = typeof(cast() this);
        const actual = typeid(this);
        return actual is typeid(Declared) ? typeNameOf!Declared : actual.name;
    }
}

/// Java's `Throwable.toString()` for any throwable: its class name, then `: message` when there is one.
string javaToString(const Throwable t) pure nothrow
{
    string message = t.msg;
    string name;
    if (auto runtime = cast(const RuntimeException) t)
    {
        message = runtime.getLocalizedMessage();
        name = runtime.runtimeName();
    }
    else
        name = typeid(t).name;
    return message is null ? name : name ~ ": " ~ message;
}

/// Declares the five Java constructors of an exception class that forwards to its superclass.
package(flint) mixin template JavaExceptionConstructors()
{
    /// No message and no cause.
    this() pure nothrow
    {
        super();
    }

    /// `message`, with a cause that can still be initialized.
    this(string message, string file = __FILE__, size_t line = __LINE__) pure nothrow
    {
        super(message, file, line);
    }

    /// `message` and an initialized `cause`.
    this(string message, Throwable cause, string file = __FILE__, size_t line = __LINE__) pure nothrow
    {
        super(message, cause, file, line);
    }

    /// Select the cause overload when the caller supplies a null literal.
    this(string message, typeof(null), string file = __FILE__, size_t line = __LINE__) pure nothrow
    {
        this(message, cast(Throwable) null, file, line);
    }

    /// The message is `cause.toString()`.
    this(Throwable cause, string file = __FILE__, size_t line = __LINE__)
    {
        super(cause, file, line);
    }

    /// See `RuntimeException`'s four-argument constructor.
    protected this(string message, Throwable cause, bool enableSuppression, bool writableStackTrace,
            string file = __FILE__, size_t line = __LINE__) pure nothrow
    {
        super(message, cause, enableSuppression, writableStackTrace, file, line);
    }
}

/// Thrown when a method is invoked at an illegal or inappropriate time.
@CanonicalName("flint.java.lang.IllegalStateException")
class IllegalStateException : RuntimeException
{
    mixin JavaExceptionConstructors;
    mixin CanonicalRuntimeName;
}

/// Thrown when a method receives an illegal or inappropriate argument.
@CanonicalName("flint.java.lang.IllegalArgumentException")
class IllegalArgumentException : RuntimeException
{
    mixin JavaExceptionConstructors;
    mixin CanonicalRuntimeName;
}
