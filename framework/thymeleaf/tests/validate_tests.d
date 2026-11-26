module validate_tests;

import flint.engine.aot.any : Any;
import flint.java.lang : IllegalArgumentException;
import flint.java.util : ArrayList, Collection;
import flint.thymeleaf.util : Validate;

@safe:

@("Validate condition and null guards keep the call-site message") unittest
{
    Validate.isTrue(true, "ignored");
    Validate.notNull(Any.of(false), "ignored");
    Validate.notNull(Any.of(""), "ignored");
    expectInvalid(() => Validate.isTrue(false, "condition failed"), "condition failed");
    expectInvalid(() => Validate.notNull(Any.init, "missing value"), "missing value");
}

@("Validate checks collection and array size independently of their elements") unittest
{
    Collection!Any collection;
    expectInvalid(() => Validate.notEmpty(collection, "missing collection"), "missing collection");
    collection = new ArrayList!Any;
    expectInvalid(() => Validate.notEmpty(collection, "empty collection"), "empty collection");
    collection.add(Any.init);
    Validate.notEmpty(collection, "a null element still counts");

    const(Any)[] elements;
    expectInvalid(() => Validate.notEmpty(elements, "missing array"), "missing array");
    const Any[1] present = [Any.init];
    const(Any)[] empty = present[0 .. 0];
    expectInvalid(() => Validate.notEmpty(empty, "empty array"), "empty array");
    Validate.notEmpty(present[], "a null element still counts");
}

private void expectInvalid(scope void delegate() @safe operation, string message)
{
    try
    {
        operation();
        assert(false, "expected IllegalArgumentException");
    }
    catch (IllegalArgumentException error)
    {
        assert(error.getMessage() == message);
    }
}
