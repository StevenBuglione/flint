// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module flint.java.net.sockettimeoutexception_test;

import flint.java.io : IOException;
import flint.java.io.interruptedioexception : InterruptedIOException;
import flint.java.net.sockettimeoutexception : SocketTimeoutException;

@safe:

@("SocketTimeoutException is a checked InterruptedIOException with an optional detail message")
unittest
{
    static assert(is(SocketTimeoutException : InterruptedIOException));
    static assert(is(SocketTimeoutException : IOException));

    const auto absent = new SocketTimeoutException();
    assert(absent.getMessage() is null);
    assert(absent.getCause() is null);
    assert(absent.bytesTransferred == 0);
    assert((new SocketTimeoutException(cast(string) null)).getMessage() is null);

    const auto empty = new SocketTimeoutException("");
    assert(empty.getMessage() !is null);
    assert(empty.getMessage().length == 0);

    const line = __LINE__ + 1;
    auto explicit = new SocketTimeoutException("Read timed out");
    assert(explicit.file == __FILE__);
    assert(explicit.line == line);
    assert(explicit.getCause() is null);
    explicit.bytesTransferred = 42;
    assert(explicit.bytesTransferred == 42);

    bool caughtAsInterrupted;
    try
        throw explicit;
    catch (InterruptedIOException caught)
    {
        caughtAsInterrupted = caught is explicit;
        assert(caught.getMessage() == "Read timed out");
        assert(caught.bytesTransferred == 42);
    }
    assert(caughtAsInterrupted);
}

@("Java's cause lifecycle: the no-argument and message constructors keep the cause open")
unittest
{
    auto root = new IOException("root cause");
    auto unnamed = new SocketTimeoutException();
    unnamed.initCause(root);
    assert(unnamed.getCause() is root);

    auto named = new SocketTimeoutException("detail");
    named.initCause(root);
    assert(named.getCause() is root);
}
