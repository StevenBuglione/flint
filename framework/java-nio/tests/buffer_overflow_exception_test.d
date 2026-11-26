// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
// Original Flint test against the Java SE 21 BufferOverflowException API.
module buffer_overflow_exception_test;

import flint.java.nio.bufferoverflowexception : BufferOverflowException;
import flint.java.lang : RuntimeException;

@safe:

@("BufferOverflowException inherits the Java runtime exception contract")
unittest
{
    auto exception = new BufferOverflowException;
    assert(exception.getMessage() is null);
    assert(exception.getCause() is null);
    auto cause = new RuntimeException("write");
    assert(exception.initCause(cause) is exception);
    assert(exception.getCause() is cause);

    RuntimeException caught;
    try
        throw exception;
    catch (RuntimeException value)
        caught = value;
    assert(cast(BufferOverflowException) caught is exception);
}
