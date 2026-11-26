module flint.java.io.unsupportedencodingexception_test;

import flint.java.io : IOException;
import flint.java.io.unsupportedencodingexception : UnsupportedEncodingException;

@safe:

@("UnsupportedEncodingException preserves the checked IOException type and detail message")
unittest
{
    assert((new UnsupportedEncodingException()).getMessage() is null);
    assert((new UnsupportedEncodingException("")).getMessage() !is null);
    try
        throw new UnsupportedEncodingException("not-a-real-charset");
    catch (IOException failure)
    {
        assert(cast(UnsupportedEncodingException) failure !is null);
        assert(failure.getMessage() == "not-a-real-charset");
    }
}
