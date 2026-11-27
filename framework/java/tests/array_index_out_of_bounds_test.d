module flint.java.array_index_out_of_bounds_test;

import flint.java.lang : IndexOutOfBoundsException, RuntimeException;
import flint.java.lang.arrayindexoutofboundsexception : ArrayIndexOutOfBoundsException;

@safe:

@("ArrayIndexOutOfBoundsException keeps Java's constructors and hierarchy")
unittest
{
    auto empty = new ArrayIndexOutOfBoundsException;
    assert(empty.getMessage() is null);
    assert(cast(IndexOutOfBoundsException) empty !is null);
    assert(cast(RuntimeException) empty !is null);

    auto message = new ArrayIndexOutOfBoundsException("boom");
    assert(message.getMessage() == "boom");

    auto byIndex = new ArrayIndexOutOfBoundsException(5);
    assert(byIndex.getMessage() == "Array index out of range: 5");
    assert(new ArrayIndexOutOfBoundsException(-1).getMessage() == "Array index out of range: -1");
    assert(new ArrayIndexOutOfBoundsException(int.max).getMessage() == "Array index out of range: 2147483647");
}

@("forArrayIndex gives the JVM's implicit array-access detail")
unittest
{
    assert(ArrayIndexOutOfBoundsException.forArrayIndex(5, 3).getMessage()
            == "Index 5 out of bounds for length 3");
    assert(ArrayIndexOutOfBoundsException.forArrayIndex(0, 0).getMessage()
            == "Index 0 out of bounds for length 0");
    assert(ArrayIndexOutOfBoundsException.forArrayIndex(-1, 7).getMessage()
            == "Index -1 out of bounds for length 7");
}

@("The exception can be caught through IndexOutOfBoundsException")
unittest
{
    try
    {
        throw ArrayIndexOutOfBoundsException.forArrayIndex(2, 2);
    }
    catch (IndexOutOfBoundsException caught)
    {
        assert(caught.getMessage() == "Index 2 out of bounds for length 2");
    }
}
