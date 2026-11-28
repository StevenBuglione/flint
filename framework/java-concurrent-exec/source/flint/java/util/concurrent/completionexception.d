// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
/// Java SE 21 CompletionException, implemented from the public contract.
module flint.java.util.concurrent.completionexception;

import flint.java.lang : RuntimeException, javaToString;

@safe:

/// A completion stage failed before it could produce a value.
class CompletionException : RuntimeException
{
    /// Construct a completion failure with a cause that may be initialized later.
    protected this() pure nothrow
    {
        super();
    }

    /// Construct a completion failure with an unset cause. Empty detail is absent (R26).
    protected this(string message) pure nothrow
    {
        super(normalize(message));
    }

    /// Construct a completion failure with an explicit cause. Empty detail is absent (R26).
    this(string message, Throwable cause)
    {
        if (cause is null)
        {
            // The message-only parent constructor leaves the cause open.
            super(normalize(message));
            super.initCause(null);
        }
        else
        {
            super(normalize(message), cause);
        }
    }

    /// Use the cause's description as the detail message.
    this(Throwable cause)
    {
        this(cause is null ? null : describe(cause), cause);
    }

    private static string normalize(string message) pure nothrow @nogc
    {
        return message.length == 0 ? null : message;
    }

    private static string describe(Throwable cause)
    {
        if (auto runtime = cast(RuntimeException) cause)
            return runtime.toString();
        return javaToString(cause);
    }
}
