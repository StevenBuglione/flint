// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
// Original Flint test against the Java SE 21 InvalidMarkException API.
module invalid_mark_exception_test;

import flint.java.nio.invalidmarkexception : InvalidMarkException;
import flint.java.lang : IllegalStateException;

@safe:

@("InvalidMarkException inherits the Java illegal-state exception contract")
unittest
{
    auto exception = new InvalidMarkException;
    assert(exception.getMessage() is null);
    assert(exception.getCause() is null);
    auto cause = new IllegalStateException("reset");
    assert(exception.initCause(cause) is exception);
    assert(exception.getCause() is cause);

    IllegalStateException caught;
    try
        throw exception;
    catch (IllegalStateException value)
        caught = value;
    assert(cast(InvalidMarkException) caught is exception);
}
