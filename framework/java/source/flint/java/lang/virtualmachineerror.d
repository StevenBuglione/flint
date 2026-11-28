// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
/++
Java's `java.lang.VirtualMachineError` and `java.lang.InternalError`, implemented from the public contract.

Java's `Error`s that application code catches map to D `Exception`s (rule R8), because D's `Error` skips cleanup.
`VirtualMachineError` extends `Error_` and `InternalError` extends it, so a port that throws `InternalError`
(for example `java.util.zip.ZipError`) keeps Java's hierarchy and catch points.
+/
module flint.java.lang.virtualmachineerror;

import flint.engine.aot.name : typeNameOf;
import flint.java.lang.error : Error_;
import flint.java.lang.runtimeexception : CanonicalRuntimeName;

@safe:

/++
Java's abstract `VirtualMachineError`: thrown when the JVM is broken or has run out of resources.

It has no members of its own beyond the four constructors; a concrete subclass such as `InternalError` supplies
the instances. Mapped to a catchable D `Exception` through `Error_` (R8).
+/
abstract class VirtualMachineError : Error_
{
    /// No message and no cause.
    this() pure nothrow
    {
        super();
    }

    /// `message`, with no cause.
    this(string message, string file = __FILE__, size_t line = __LINE__) pure nothrow
    {
        super(message, file, line);
    }

    /// `message` and a `cause`.
    this(string message, Throwable cause, string file = __FILE__, size_t line = __LINE__) pure nothrow
    {
        super(message, cause, file, line);
    }

    /// Java's `VirtualMachineError(Throwable cause)`: the message is `cause.toString()`, or null.
    this(Throwable cause, string file = __FILE__, size_t line = __LINE__)
    {
        super(cause, file, line);
    }

    mixin CanonicalRuntimeName;
}

/++
Java's `InternalError`: an internal VM error that the runtime reports instead of crashing.

For example `java.util.zip.ZipError` extends it. Inherits message and cause handling from `Error_`.
+/
class InternalError : VirtualMachineError
{
    /// No message and no cause.
    this() pure nothrow
    {
        super();
    }

    /// `message`, with no cause.
    this(string message, string file = __FILE__, size_t line = __LINE__) pure nothrow
    {
        super(message, file, line);
    }

    /// `message` and a `cause`.
    this(string message, Throwable cause, string file = __FILE__, size_t line = __LINE__) pure nothrow
    {
        super(message, cause, file, line);
    }

    /// Java's `InternalError(Throwable cause)`: the message is `cause.toString()`, or null.
    this(Throwable cause, string file = __FILE__, size_t line = __LINE__)
    {
        super(cause, file, line);
    }

    mixin CanonicalRuntimeName;
}
