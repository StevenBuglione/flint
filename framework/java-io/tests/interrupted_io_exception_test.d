// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
/** Original specification tests for Java's interrupted I/O exception. */
module flint.java.io.interrupted_io_exception_test;

import flint.java.io : IOException;
import flint.java.io.interruptedioexception : InterruptedIOException;

@safe:

@("InterruptedIOException preserves its I/O type, message and initial byte count")
unittest
{
    static assert(is(InterruptedIOException : IOException));

    const absent = new InterruptedIOException;
    assert(absent.getMessage() is null && absent.getCause() is null);
    assert(absent.bytesTransferred == 0);

    const nullMessage = new InterruptedIOException(null);
    assert(nullMessage.getMessage() is null);

    const empty = new InterruptedIOException("");
    assert(empty.getMessage() !is null && empty.getMessage().length == 0);

    auto interrupted = new InterruptedIOException("interrupted");
    assert(interrupted.getMessage() == "interrupted");
    assert(interrupted.getCause() is null && interrupted.bytesTransferred == 0);
    interrupted.bytesTransferred = -7;
    assert(interrupted.bytesTransferred == -7);
}
