// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
/** Original specification tests for wrapping Java I/O failures. */
module flint.java.io.unchecked_io_exception_contract_test;

import flint.java.io : IOException, UncheckedIOException;
import flint.java.lang : NullPointerException, RuntimeException;
import std.exception : assertThrown;

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

    const emptyMessage = new UncheckedIOException("", cause);
    assert(emptyMessage.getMessage() is null);
    assert(emptyMessage.getCause() is cause);

    const withoutExplicitMessage = new UncheckedIOException(cause);
    assert(withoutExplicitMessage.getMessage() == "flint.java.io.IOException: inner");
    assert(withoutExplicitMessage.getCause() is cause);
}

@("UncheckedIOException rejects a null checked cause when constructed")
unittest
{
    IOException missing;
    assertThrown!NullPointerException(new UncheckedIOException(missing));
    assertThrown!NullPointerException(new UncheckedIOException("outer", missing));
}

@("UncheckedIOException exposes the same checked cause through its typed and parent accessors")
unittest
{
    auto cause = new IOException("inner");
    auto failure = new UncheckedIOException(cause);
    IOException checked = failure.getCause();
    assert(checked is cause);

    const UncheckedIOException readOnly = failure;
    const IOException readOnlyCause = readOnly.getCause();
    assert(readOnlyCause is cause);

    RuntimeException base = failure;
    assert(base.getCause() is cause);
}
