// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
/// Java SE 21 CancellationException, implemented from the public contract.
module flint.java.util.concurrent.cancellationexception;

import flint.java.lang : IllegalStateException;

@safe:

/// A task was cancelled before it completed normally.
class CancellationException : IllegalStateException
{
    /// Construct a cancellation with no detail message (R26).
    this() pure nothrow
    {
        super();
    }

    /// Construct a cancellation with a detail message. Empty detail is absent (R26).
    this(string message) pure nothrow
    {
        super(normalize(message));
    }

    private static string normalize(string message) pure nothrow @nogc
    {
        return message.length == 0 ? null : message;
    }
}
