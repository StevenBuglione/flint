/// Original Java SE 21 cases for NegativeArraySizeException.
module flint.java.negative_array_size_test;

import flint.java.lang : RuntimeException;
import flint.java.lang.negativearraysizeexception : NegativeArraySizeException;

@safe:

@("negative array size keeps the Java unchecked hierarchy and the supplied detail")
unittest
{
    static assert(is(NegativeArraySizeException : RuntimeException));

    assert((new NegativeArraySizeException()).getMessage() is null);
    assert((new NegativeArraySizeException(null)).getMessage() is null);

    auto error = new NegativeArraySizeException("-1");
    assert(error.getMessage() == "-1");
    assert(error.getCause() is null);
    assert(typeid(error) is typeid(NegativeArraySizeException));
    assert(typeid(error).name == "flint.java.lang.negativearraysizeexception.NegativeArraySizeException");
}

@("a thrown negative array size is caught as RuntimeException with its own runtime type")
unittest
{
    bool caught;
    try
        throw new NegativeArraySizeException("-1");
    catch (RuntimeException error)
    {
        caught = true;
        assert(typeid(error) is typeid(NegativeArraySizeException));
        assert(error.getMessage() == "-1");
    }
    assert(caught);
}
