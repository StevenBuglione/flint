module executionexception_provider;

import flint.java.lang : IllegalArgumentException, IllegalStateException, RuntimeException, javaToString;

@safe:

// A provider-equivalent failure: the same cause handling as ExecutionException without the Java leaf.
private class StationException : Exception
{
    private Throwable cause;
    private bool causeInitialized;

    protected this()
    {
        this(cast(string) null);
    }

    protected this(string message)
    {
        super(message.length == 0 ? null : message);
    }

    this(string message, Throwable cause)
    {
        super(message.length == 0 ? null : message);
        this.cause = cause;
        causeInitialized = true;
    }

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

int main(string[] args)
{
    auto cause = new RuntimeException(args.length > 0 ? args[0] : "failed");
    try
    {
        if (args.length > 1)
            throw new StationException(args[1], cause);
        throw new StationException(cause);
    }
    catch (StationException failure)
    {
        return failure.getCause() is cause && failure.getMessage().length != 0 ? 0 : 1;
    }
}
