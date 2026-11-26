module broken_barrier_exception_test;

import flint.java.util.concurrent.brokenbarrierexception : BrokenBarrierException;

@safe:

@("BrokenBarrierException retains absent, empty and explicit messages")
unittest
{
    static assert(is(BrokenBarrierException : Exception));
    assert((new BrokenBarrierException).getMessage() is null);
    assert((new BrokenBarrierException(null)).getMessage() is null);

    const empty = (new BrokenBarrierException("")).getMessage();
    assert(empty.length == 0 && empty !is null);

    Exception broken = new BrokenBarrierException("barrier reset");
    try
    {
        throw broken;
    }
    catch (BrokenBarrierException caught)
    {
        assert(caught is broken);
        assert(caught.getMessage() == "barrier reset");
        assert(caught.next is null);
        return;
    }
    assert(false, "typed barrier handler did not run");
}
