module flint.java.toomanylisteners_test;

import flint.java.util.toomanylistenersexception : TooManyListenersException;

@safe:

@("Too many listeners keeps the detail message exactly")
unittest
{
    assert((new TooManyListenersException).getMessage() is null);

    auto empty = new TooManyListenersException("", "bean.d", 9);
    assert(empty.file == "bean.d" && empty.line == 9);
    assert(empty.getMessage() == "");

    assert((new TooManyListenersException("already listening")).getMessage() == "already listening");
}

@("Too many listeners keeps its class through the checked catch")
unittest
{
    Exception failure = new TooManyListenersException("second listener");
    try
    {
        throw failure;
    }
    catch (TooManyListenersException caught)
    {
        assert(caught is failure);
        assert(caught.getMessage() == "second listener");
        return;
    }
    assert(0, "expected the TooManyListenersException catch");
}
