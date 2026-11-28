// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
/** Original specification tests for Java's EOFException. */
module flint.java.io.eof_exception_test;

import flint.java.io : EOFException, IOException;
import flint.java.lang : IllegalStateException;
import std.exception : assertThrown;

@safe:

@("EOFException is a checked IOException with Java's two details")
unittest
{
    assert(is(EOFException : IOException));
    assert((new EOFException()).getMessage() is null);
    assert((new EOFException("")).getMessage() is null);
    assert((new EOFException("end of stream")).getMessage() == "end of stream");
}

@("EOFException's cause stays open for one initCause call")
unittest
{
    auto cause = new IOException("inner");
    auto failure = new EOFException("premature end");
    assert(failure.initCause(cause) is failure);
    assert(failure.getCause() is cause);
    assertThrown!IllegalStateException(failure.initCause(new IOException("again")));
}

@("EOFException thrown by an input failure is caught as IOException")
unittest
{
    try
    {
        throw new EOFException("premature end");
    }
    catch (IOException failure)
    {
        assert(cast(EOFException) failure !is null);
        assert(failure.getMessage() == "premature end");
    }
}
