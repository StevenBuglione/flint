// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
/** Original specification tests for Java's EOFException. */
module flint.java.io.eof_exception_test;

import flint.java.io : EOFException, IOException;

@safe:

@("EOFException is a checked IOException with Java's two details")
unittest
{
    assert(is(EOFException : IOException));
    assert((new EOFException()).getMessage() is null);
    assert((new EOFException("")).getMessage() !is null);
    assert((new EOFException("end of stream")).getMessage() == "end of stream");
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
