module flint.java.input_mismatch_test;

import flint.java.util : NoSuchElementException;
import flint.java.util.inputmismatchexception : InputMismatchException;

@safe:

@("Scanner input mismatch keeps its class and its inherited cause")
unittest
{
    auto empty = new InputMismatchException("", "scanner.d", 17);
    assert(empty.file == "scanner.d" && empty.line == 17);
    assert(empty.getMessage() is null);
    assert(empty.getCause() is null);
    assert((new InputMismatchException).getMessage() is null);

    auto cause = new Exception("source was replaced");
    try
    {
        auto mismatch = new InputMismatchException("expected an integer");
        assert(mismatch.initCause(cause) is mismatch);
        throw mismatch;
    }
    catch (NoSuchElementException mismatch)
    {
        assert(cast(InputMismatchException) mismatch !is null);
        assert(mismatch.getMessage() == "expected an integer");
        assert(mismatch.getCause() is cause);
        return;
    }
    assert(0, "expected the canonical NoSuchElementException catch");
}
