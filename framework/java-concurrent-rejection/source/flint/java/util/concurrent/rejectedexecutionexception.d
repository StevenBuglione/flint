// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
/// Java SE 21 RejectedExecutionException from the public contract.
module flint.java.util.concurrent.rejectedexecutionexception;

import flint.java.lang : RuntimeException, javaToString;

@safe:

/// A scheduler could not accept a task.
class RejectedExecutionException : RuntimeException
{
    this() pure nothrow
    {
        super();
    }

    /// Empty detail is absent (R26).
    this(string message) pure nothrow
    {
        super(normalize(message));
    }

    /// Set the cause, including an explicit null. Empty detail is absent (R26).
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
