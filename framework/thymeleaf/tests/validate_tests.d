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

@("Validate distinguishes an absent array from an empty one") unittest
{
    import std.typecons : Nullable;

    alias Array = Nullable!(const(Any)[]);
    const(Any)[] empty;
    Validate.containsNoNulls(Array(empty), "ignored");
    expectMissing(() => Validate.containsNoNulls(Array.init, "unused"));

    const Any[2] present = [Any.of(false), Any.of("")];
    Validate.containsNoNulls(Array(present[]), "ignored");
    const Any[2] invalid = [Any.of(false), Any.init];
    const badArray = Array(invalid[]);
    expectInvalid(() => Validate.containsNoNulls(badArray, "invalid element"), "invalid element");
}

@("Validate iterates missing and null elements with Java exceptions") unittest
{
    import flint.java.lang : Iterable;
    import std.typecons : Nullable;

    alias Text = Nullable!string;
    Iterable!Text missing;
    expectMissing(() => Validate.containsNoNulls(missing, "unused"));

    auto values = new ArrayList!Text;
    Validate.containsNoNulls(values, "ignored");
    values.add(Text(""));
    Validate.containsNoNulls(values, "ignored");
    values.add(Text.init);
    expectInvalid(() => Validate.containsNoNulls(values, "invalid iterable element"), "invalid iterable element");
}

private void expectMissing(scope void delegate() @safe operation)
{
    import flint.java.lang : NullPointerException;

    try
    {
        operation();
        assert(false, "expected NullPointerException");
    }
    catch (NullPointerException)
    {
    }
}
