module property_resolution_exception_tests;

import flint.core : NestedRuntimeException;
import flint.data.core : PropertyResolutionException;
import flint.java.lang : IllegalArgumentException, IllegalStateException;

@safe:

@("Property resolution retains its nested cause")
unittest
{
    auto root = new IllegalArgumentException("unknown property");
    auto cause = new IllegalStateException("bad descriptor", root);
    NestedRuntimeException failure = new PropertyResolutionException("path resolution failed", cause);

    assert(failure.getMessage() == "path resolution failed");
    assert(failure.getCause() is cause);
    assert(failure.getRootCause() is root);
}

@("Property resolution supports a null detail message and an absent cause")
unittest
{
    auto failure = new PropertyResolutionException(null);
    assert(failure.getMessage() is null && failure.getCause() is null);
    assert(failure.getMostSpecificCause() is failure);
}
