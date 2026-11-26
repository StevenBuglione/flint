// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
/** Original specification tests for wrapping Java I/O failures. */
module flint.java.io.unchecked_io_exception_contract_test;

import flint.java.io : IOException, UncheckedIOException;
import flint.java.lang : RuntimeException;

@safe:

@("UncheckedIOException wraps the same checked failure as a RuntimeException")
unittest
{
    auto cause = new IOException("inner");
    RuntimeException failure = new UncheckedIOException("outer", cause);
    assert(failure.getMessage() == "outer");
    assert(failure.getCause() is cause);

    const withoutMessage = new UncheckedIOException(null, cause);
    assert(withoutMessage.getMessage() is null);
    assert(withoutMessage.getCause() is cause);

    const withoutExplicitMessage = new UncheckedIOException(cause);
    assert(withoutExplicitMessage.getMessage() == "flint.java.io.IOException: inner");
    assert(withoutExplicitMessage.getCause() is cause);
}
