// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
// Original Flint test against the Java SE 21 BufferUnderflowException API.
module buffer_underflow_exception_test;

import flint.java.nio.bufferunderflowexception : BufferUnderflowException;
import flint.java.lang : RuntimeException;

@safe:

@("BufferUnderflowException inherits the Java runtime exception contract")
unittest
{
    auto exception = new BufferUnderflowException;
    assert(exception.getMessage() is null);
    assert(exception.getCause() is null);
    auto cause = new RuntimeException("read");
    assert(exception.initCause(cause) is exception);
    assert(exception.getCause() is cause);

    RuntimeException caught;
    try
        throw exception;
    catch (RuntimeException value)
        caught = value;
    assert(cast(BufferUnderflowException) caught is exception);
}
