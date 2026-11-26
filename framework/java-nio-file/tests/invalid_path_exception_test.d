module invalid_path_exception_test;

import flint.java.lang : IllegalArgumentException;
import flint.java.nio.file : InvalidPathException;

@safe:

private void expect(T)(scope void delegate() @safe action)
{
    try
        action();
    catch (T exception)
    {
        assert(typeid(exception) is typeid(T));
        return;
    }
    assert(false, "Expected the requested exception");
}

private final class OverriddenReason : InvalidPathException
{
    string explanation = "initial";

    this()
    {
        super("file", "base", 2);
    }

    override string getReason() const pure nothrow @nogc
    {
        return explanation;
    }
}

@("InvalidPathException preserves path details and treats null strings as empty under R26")
unittest
{
    static assert(is(InvalidPathException : IllegalArgumentException));

    auto indexed = new InvalidPathException("a😀:b", "invalid separator", 3);
    assert(indexed.getInput() == "a😀:b");
    assert(indexed.getReason() == "invalid separator");
    assert(indexed.getIndex() == 3);
    assert(indexed.getMessage() == "invalid separator at index 3: a😀:b");

    auto empty = new InvalidPathException("", "");
    assert(empty.getInput() !is null && empty.getInput().length == 0);
    assert(empty.getReason() !is null && empty.getReason().length == 0);
    assert(empty.getIndex() == -1);
    assert(empty.getMessage() == ": ");

    auto unknown = new InvalidPathException("x", "r", -1);
    assert(unknown.getMessage() == "r: x");
    auto pastEnd = new InvalidPathException("x", "r", 25);
    assert(pastEnd.getIndex() == 25 && pastEnd.getMessage() == "r at index 25: x");

    auto missingInput = new InvalidPathException(null, "r");
    assert(missingInput.getInput() !is null && missingInput.getInput() == "");
    assert(missingInput.getMessage() == "r: ");
    auto missingReason = new InvalidPathException("x", null, 0);
    assert(missingReason.getReason() !is null && missingReason.getReason() == "");
    assert(missingReason.getMessage() == " at index 0: x");
    expect!IllegalArgumentException(() { new InvalidPathException(null, "r", -2); });
    expect!IllegalArgumentException(() { new InvalidPathException("x", "r", -2); });
}

@("InvalidPathException caches its constructor message under D-JDK-3")
unittest
{
    auto subclass = new OverriddenReason;
    assert(subclass.getReason() == "initial");
    subclass.explanation = "updated";
    assert(subclass.getReason() == "updated");
    assert(subclass.getMessage() == "base at index 2: file");
}
