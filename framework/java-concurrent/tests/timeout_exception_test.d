/** Original Flint tests for the Java SE 21 TimeoutException contract. */
module timeout_exception_test;

import flint.java.util.concurrent.timeoutexception : TimeoutException;

@safe:

@("TimeoutException supports an absent or explicit message")
unittest
{
    assert((new TimeoutException).getMessage() is null);
    assert((new TimeoutException("waiting for worker")).getMessage() == "waiting for worker");
}

@("a timeout can be caught by type through the general Exception boundary")
unittest
{
    Exception failure = new TimeoutException("deadline expired");
    try
    {
        throw failure;
    }
    catch (TimeoutException caught)
    {
        assert(caught is failure);
        assert(caught.getMessage() == "deadline expired");
        return;
    }
    assert(false, "typed timeout handler did not run");
}
