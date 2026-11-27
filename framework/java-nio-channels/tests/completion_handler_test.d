// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
// Original Flint tests for the Java SE 21 CompletionHandler contract.
module completion_handler_test;

import flint.java.io : IOException;
import flint.java.nio.channels.completionhandler : CompletionHandler;

@safe:

private final class RecordingHandler(V, A) : CompletionHandler!(V, A)
{
    V lastResult;
    A lastAttachment;
    Throwable lastError;
    int completedCount;
    int failedCount;

    override void completed(V result, A attachment)
    {
        lastResult = result;
        lastAttachment = attachment;
        completedCount++;
    }

    override void failed(Throwable exc, A attachment)
    {
        lastError = exc;
        lastAttachment = attachment;
        failedCount++;
    }
}

@("CompletionHandler dispatches completed and failed for value and reference type arguments")
unittest
{
    auto intImpl = new RecordingHandler!(int, string);
    CompletionHandler!(int, string) intHandler = intImpl;

    intHandler.completed(42, "req-1");
    assert(intImpl.completedCount == 1 && intImpl.failedCount == 0);
    assert(intImpl.lastResult == 42 && intImpl.lastAttachment == "req-1");

    auto err = new IOException("closed");
    intHandler.failed(err, "req-2");
    assert(intImpl.completedCount == 1 && intImpl.failedCount == 1);
    assert(intImpl.lastError is err && intImpl.lastAttachment == "req-2");

    auto refImpl = new RecordingHandler!(Object, Object);
    CompletionHandler!(Object, Object) refHandler = refImpl;
    auto token = new Object;
    refHandler.completed(token, null);
    assert(refImpl.lastResult is token && refImpl.lastAttachment is null);
    refHandler.failed(null, token);
    assert(refImpl.lastError is null && refImpl.lastAttachment is token);
}
