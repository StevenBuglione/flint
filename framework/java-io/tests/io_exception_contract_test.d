// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
/** Original specification tests for the existing Java I/O exception constructors. */
module flint.java.io.io_exception_contract_test;

import flint.java.io : FileNotFoundException, IOException;
import flint.java.lang : IllegalArgumentException, IllegalStateException;
import std.exception : assertThrown;

@safe:

@("IOException preserves the constructor message and cause")
unittest
{
    static assert(is(IOException : Exception));

    const failure = new IOException;
    assert(failure.getMessage() is null);
    assert(failure.getCause() is null);

    const emptyMessage = new IOException("");
    assert(emptyMessage.getMessage() is null);
    assert(emptyMessage.getCause() is null);

    const explicitMessage = new IOException("outer");
    assert(explicitMessage.getMessage() == "outer");
    assert(explicitMessage.getCause() is null);

    auto cause = new IOException("inner");
    const withCause = new IOException("outer", cause);
    assert(withCause.getMessage() == "outer");
    assert(withCause.getCause() is cause);

    const noMessage = new IOException(null, cause);
    assert(noMessage.getMessage() is null);
    assert(noMessage.getCause() is cause);
}

@("IOException.initCause sets the cause once, as Java's Throwable does")
unittest
{
    auto cause = new IOException("inner");
    auto failure = new IOException("outer");
    assert(failure.getCause() is null);
    assert(failure.initCause(cause) is failure);
    assert(failure.getCause() is cause);
    try
    {
        failure.initCause(new IOException("again"));
        assert(false);
    }
    catch (IllegalStateException failureMessage)
    {
        const message = failureMessage.getMessage();
        enum prefix = "Can't overwrite cause with ";
        assert(message.length > prefix.length && message[0 .. prefix.length] == prefix);
    }

    auto self = new IOException("self");
    assertThrown!IllegalArgumentException(self.initCause(self));

    auto initialized = new IOException("outer", cause);
    assertThrown!IllegalStateException(initialized.initCause(new IOException("again")));

    auto nullCause = new IOException;
    assert(nullCause.initCause(null) is nullCause);
    assert(nullCause.getCause() is null);
    assertThrown!IllegalStateException(nullCause.initCause(cause));
}

@("FileNotFoundException retains its IOException type and detail message")
unittest
{
    static assert(is(FileNotFoundException : IOException));

    const failure = new FileNotFoundException;
    assert(failure.getMessage() is null);
    assert(failure.getCause() is null);

    const missing = new FileNotFoundException("missing");
    assert(missing.getMessage() == "missing");
    assert(missing.getCause() is null);
}

@("FileNotFoundException's cause stays open for one initCause call")
unittest
{
    auto cause = new IOException("inner");
    auto missing = new FileNotFoundException("missing");
    assert(missing.initCause(cause) is missing);
    assert(missing.getCause() is cause);
    assertThrown!IllegalStateException(missing.initCause(cause));
}

@("IOException's cause constructor derives the detail from cause.toString")
unittest
{
    auto cause = new IOException("inner");
    auto wrapped = new IOException(cause);
    assert(wrapped.getMessage() == "flint.java.io.IOException: inner");
    assert(wrapped.getCause() is cause);
    assertThrown!IllegalStateException(wrapped.initCause(new IOException("again")));

    auto plain = new FileNotFoundException("missing");
    const wrappedPlain = new IOException(plain);
    assert(wrappedPlain.getMessage() == "flint.java.io.FileNotFoundException: missing");
    assert(wrappedPlain.getCause() is plain);
}

@("IOException's cause constructor with an absent cause leaves initCause open (R8)")
unittest
{
    auto wrapped = new IOException(cast(Throwable) null);
    assert(wrapped.getMessage() is null);
    assert(wrapped.getCause() is null);

    auto cause = new IOException("later");
    assert(wrapped.initCause(cause) is wrapped);
    assert(wrapped.getCause() is cause);
}
