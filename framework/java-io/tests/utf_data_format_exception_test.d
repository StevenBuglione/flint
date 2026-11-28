// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
/** Original specification tests for Java's UTFDataFormatException. */
module flint.java.io.utf_data_format_exception_test;

import flint.java.io : IOException, UTFDataFormatException;
import flint.java.lang : IllegalStateException;
import std.exception : assertThrown;

@safe:

@("UTFDataFormatException is a checked IOException with Java's two details")
unittest
{
    assert(is(UTFDataFormatException : IOException));
    assert((new UTFDataFormatException()).getMessage() is null);
    assert((new UTFDataFormatException("malformed input")).getMessage() == "malformed input");
}

@("UTFDataFormatException's cause stays open for one initCause call")
unittest
{
    auto cause = new IOException("inner");
    auto noMessage = new UTFDataFormatException;
    assert(noMessage.getCause() is null);
    assert(noMessage.initCause(cause) is noMessage);
    assert(noMessage.getCause() is cause);
    assertThrown!IllegalStateException(noMessage.initCause(cause));

    auto withMessage = new UTFDataFormatException("malformed input");
    assert(withMessage.getCause() is null);
    assert(withMessage.initCause(cause) is withMessage);
    assertThrown!IllegalStateException(withMessage.initCause(cause));
}
