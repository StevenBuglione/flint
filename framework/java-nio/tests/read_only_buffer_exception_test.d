// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
// Original Flint test against the Java SE 21 ReadOnlyBufferException API.
module read_only_buffer_exception_test;

import flint.java.nio.readonlybufferexception : ReadOnlyBufferException;
import flint.java.lang : UnsupportedOperationException;

@safe:

@("ReadOnlyBufferException inherits the Java unsupported-operation exception contract")
unittest
{
    auto exception = new ReadOnlyBufferException;
    assert(exception.getMessage() is null);
    assert(exception.getCause() is null);
    auto cause = new UnsupportedOperationException("write");
    assert(exception.initCause(cause) is exception);
    assert(exception.getCause() is cause);

    UnsupportedOperationException caught;
    try
        throw exception;
    catch (UnsupportedOperationException value)
        caught = value;
    assert(cast(ReadOnlyBufferException) caught is exception);
}
