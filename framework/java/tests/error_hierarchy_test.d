module flint.java.error_hierarchy_test;

import flint.java.lang : AssertionError, Error_;
import flint.java.lang.virtualmachineerror : InternalError, VirtualMachineError;

@safe:

unittest
{
    static assert(__traits(isAbstractClass, VirtualMachineError));
    static assert(is(InternalError : VirtualMachineError));
    static assert(is(VirtualMachineError : Error_));
}

unittest
{
    auto plain = new InternalError;
    assert(plain.getMessage() is null);
    assert(plain.getCause() is null);
    assert(plain.toString() == "flint.java.lang.virtualmachineerror.InternalError");

    auto messaged = new InternalError("boom");
    assert(messaged.getMessage() == "boom");
    assert(messaged.toString() == "flint.java.lang.virtualmachineerror.InternalError: boom");

    auto cause = new AssertionError("cause");
    auto withCause = new InternalError("boom", cause);
    assert(withCause.getCause() is cause);

    auto causeOnly = new InternalError(cause);
    assert(causeOnly.getCause() is cause);
    assert(causeOnly.getMessage() !is null);
}

unittest
{
    bool caught;
    try
        throw new InternalError("fault");
    catch (VirtualMachineError failure)
        caught = failure.getMessage() == "fault";
    assert(caught);

    caught = false;
    try
        throw new InternalError("fault");
    catch (Error_ failure)
        caught = failure.getMessage() == "fault";
    assert(caught);
}
