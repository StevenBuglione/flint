// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
/// Java SE 21 ExecutionException, implemented from the public contract.
module flint.java.util.concurrent.executionexception;

import flint.java.lang : IllegalArgumentException, IllegalStateException, RuntimeException, javaToString;

@safe:

/// A task failed before it could return a value.
class ExecutionException : Exception
{
    private Throwable cause;
    private bool causeInitialized;

    /// Construct a failure with a cause that may be initialized later.
    protected this()
    {
        this(cast(string) null);
    }

    /// Construct a failure with a detail message and an unset cause.
    protected this(string message)
    {
        super(message);
    }

    /// Construct a failure with a message and an explicit cause.
    this(string message, Throwable cause)
    {
        super(message);
        this.cause = cause;
        causeInitialized = true;
    }

    /// Use the cause's description as the detail message.
    this(Throwable cause)
    {
        this(cause is null ? null : describeCause(cause), cause);
    }

    string getMessage() const pure nothrow @nogc
    {
        return msg;
    }

    inout(Throwable) getCause() inout @nogc
    {
        synchronized (this)
            return cause;
    }

    /// Set the cause once on an instance constructed without a cause argument.
    Throwable initCause(Throwable replacement)
    {
        bool initialized;
        synchronized (this)
        {
            initialized = causeInitialized;
            if (!initialized && replacement !is this)
            {
                cause = replacement;
                causeInitialized = true;
                return this;
            }
        }
        if (initialized)
            throw new IllegalStateException("Can't overwrite cause with " ~ (replacement is null
                    ? "a null" : describeCause(replacement)), this);
        throw new IllegalArgumentException("Self-causation not permitted", this);
    }

    private static string describeCause(Throwable cause)
    {
        if (auto runtime = cast(RuntimeException) cause)
            return runtime.toString();
        return javaToString(cause);
    }
}
