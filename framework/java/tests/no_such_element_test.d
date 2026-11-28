module flint.java.no_such_element_test;

import flint.java.lang : RuntimeException;
import flint.java.util.nosuchelementexception : NoSuchElementException;

@safe:

@("NoSuchElementException is a RuntimeException with Java's constructors")
unittest
{
    auto empty = new NoSuchElementException;
    assert(empty.getMessage() is null);
    assert(cast(RuntimeException) empty !is null);

    assert(new NoSuchElementException("done").getMessage() == "done");

    auto cause = new RuntimeException("cause");
    auto withCause = new NoSuchElementException(null, cause);
    assert(withCause.getCause() is cause);
}
