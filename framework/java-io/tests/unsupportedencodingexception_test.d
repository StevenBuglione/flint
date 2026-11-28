module flint.java.io.unsupportedencodingexception_test;

import flint.java.io : IOException;
import flint.java.io.unsupportedencodingexception : UnsupportedEncodingException;
import flint.java.lang : IllegalStateException;
import std.exception : assertThrown;

@safe:

@("UnsupportedEncodingException preserves the checked IOException type and detail message")
unittest
{
    assert((new UnsupportedEncodingException()).getMessage() is null);
    assert((new UnsupportedEncodingException("")).getMessage() is null);
    try
        throw new UnsupportedEncodingException("not-a-real-charset");
    catch (IOException failure)
    {
        assert(cast(UnsupportedEncodingException) failure !is null);
        assert(failure.getMessage() == "not-a-real-charset");
    }
}

@("UnsupportedEncodingException's cause stays open for one initCause call")
unittest
{
    auto cause = new IOException("inner");
    auto failure = new UnsupportedEncodingException("not-a-real-charset");
    assert(failure.initCause(cause) is failure);
    assert(failure.getCause() is cause);
    assertThrown!IllegalStateException(failure.initCause(new IOException("again")));
}
