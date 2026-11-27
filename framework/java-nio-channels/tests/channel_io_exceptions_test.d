// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
// Original Flint tests for the 5 checked (IOException-derived) Java SE 21 java.nio.channels exceptions.
module channel_io_exceptions_test;

import flint.java.io : IOException;
import flint.java.lang : IllegalArgumentException, IllegalStateException, RuntimeException;
import flint.java.nio.channels.asynchronouscloseexception : AsynchronousCloseException;
import flint.java.nio.channels.closedbyinterruptexception : ClosedByInterruptException;
import flint.java.nio.channels.closedchannelexception : ClosedChannelException;
import flint.java.nio.channels.filelockinterruptionexception : FileLockInterruptionException;
import flint.java.nio.channels.interruptedbytimeoutexception : InterruptedByTimeoutException;

@safe:

// Java's no-argument constructor leaves the message null and the cause uninitialized, so exactly one initCause
// succeeds, a second throws IllegalStateException, and a self-cause throws IllegalArgumentException.
private void verifyCauseLifecycle(E)()
{
    auto ex = new E;
    assert(ex.getMessage() is null);
    assert(ex.getCause() is null);

    auto selfCause = new E;
    bool selfRejected;
    try
        selfCause.initCause(selfCause);
    catch (IllegalArgumentException rejected)
    {
        assert(rejected.getMessage() == "Self-causation not permitted");
        assert(rejected.getCause() is selfCause);
        selfRejected = true;
    }
    assert(selfRejected);
    assert(selfCause.getCause() is null);

    auto root = new RuntimeException("root");
    assert(ex.initCause(root) is ex);
    assert(ex.getCause() is root);

    bool secondRejected;
    try
        ex.initCause(new RuntimeException("second"));
    catch (IllegalStateException rejected)
    {
        assert(rejected.getCause() is ex);
        secondRejected = true;
    }
    assert(secondRejected);
    assert(ex.getCause() is root);

    // An explicit null cause also initializes it.
    auto nullCaused = new E;
    assert(nullCaused.initCause(null) is nullCaused);
    assert(nullCaused.getCause() is null);
    bool afterNullRejected;
    try
        nullCaused.initCause(root);
    catch (IllegalStateException)
        afterNullRejected = true;
    assert(afterNullRejected);
}

private void verifyCaughtAs(E, Base)()
{
    auto ex = new E;
    Base caught;
    try
        throw ex;
    catch (Base value)
        caught = value;
    assert(cast(E) caught is ex);
}

@("ClosedChannelException and FileLockInterruptionException are checked IOExceptions with Java's cause lifecycle")
unittest
{
    verifyCauseLifecycle!ClosedChannelException();
    verifyCauseLifecycle!FileLockInterruptionException();
    verifyCaughtAs!(ClosedChannelException, IOException)();
    verifyCaughtAs!(FileLockInterruptionException, IOException)();
    static assert(!is(ClosedChannelException : RuntimeException));
    static assert(!is(FileLockInterruptionException : ClosedChannelException));
}

@("AsynchronousCloseException and ClosedByInterruptException keep Java's ClosedChannelException chain")
unittest
{
    verifyCauseLifecycle!AsynchronousCloseException();
    verifyCauseLifecycle!ClosedByInterruptException();
    verifyCaughtAs!(AsynchronousCloseException, ClosedChannelException)();
    verifyCaughtAs!(AsynchronousCloseException, IOException)();
    verifyCaughtAs!(ClosedByInterruptException, AsynchronousCloseException)();
    verifyCaughtAs!(ClosedByInterruptException, ClosedChannelException)();
    verifyCaughtAs!(ClosedByInterruptException, IOException)();

    // A plain close is not an asynchronous close.
    IOException closed = new ClosedChannelException;
    assert(cast(AsynchronousCloseException) closed is null);
    IOException asyncClosed = new AsynchronousCloseException;
    assert(cast(ClosedByInterruptException) asyncClosed is null);
}

@("InterruptedByTimeoutException is a checked IOException outside the closed-channel chain")
unittest
{
    verifyCauseLifecycle!InterruptedByTimeoutException();
    verifyCaughtAs!(InterruptedByTimeoutException, IOException)();
    static assert(!is(InterruptedByTimeoutException : ClosedChannelException));
    static assert(!is(InterruptedByTimeoutException : RuntimeException));
}
