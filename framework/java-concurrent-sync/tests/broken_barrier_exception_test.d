module broken_barrier_exception_test;

import flint.java.lang : javaToString;
import flint.java.util.concurrent.brokenbarrierexception : BrokenBarrierException;

@safe:

@("BrokenBarrierException treats empty detail as absent and preserves nonempty detail")
unittest
{
    static assert(is(BrokenBarrierException : Exception));
    assert((new BrokenBarrierException).getMessage() is null);
    assert((new BrokenBarrierException(null)).getMessage() is null);

    auto empty = new BrokenBarrierException("");
    assert(empty.getMessage() is null);
    assert(javaToString(empty) == javaToString(new BrokenBarrierException));
    const text = "detail";
    assert((new BrokenBarrierException(text[0 .. 0])).getMessage() is null);

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
