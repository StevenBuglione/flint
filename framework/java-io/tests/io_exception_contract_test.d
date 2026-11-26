// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
/** Original specification tests for the existing Java I/O exception constructors. */
module flint.java.io.io_exception_contract_test;

import flint.java.io : FileNotFoundException, IOException;

@safe:

@("IOException preserves the constructor message and cause")
unittest
{
    static assert(is(IOException : Exception));

    const failure = new IOException;
    assert(failure.getMessage() is null);
    assert(failure.getCause() is null);

    const emptyMessage = new IOException("");
    assert(emptyMessage.getMessage() !is null && emptyMessage.getMessage().length == 0);
    assert(emptyMessage.getCause() is null);

    const explicitMessage = new IOException("outer");
    assert(explicitMessage.getMessage() == "outer");
    assert(explicitMessage.getCause() is null);

    auto cause = new IOException("inner");
    const withCause = new IOException("outer", cause);
    assert(withCause.getMessage() == "outer");
    assert(withCause.getCause() is cause);

    const noMessage = new IOException(null, cause);
    assert(noMessage.getMessage() is null);
    assert(noMessage.getCause() is cause);
}

@("FileNotFoundException retains its IOException type and detail message")
unittest
{
    static assert(is(FileNotFoundException : IOException));

    const failure = new FileNotFoundException;
    assert(failure.getMessage() is null);
    assert(failure.getCause() is null);

    const missing = new FileNotFoundException("missing");
    assert(missing.getMessage() == "missing");
    assert(missing.getCause() is null);
}
