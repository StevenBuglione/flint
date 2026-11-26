module flint.java.enumeration_test;

import flint.java.lang : UnsupportedOperationException;
import flint.java.util : Iterator, NoSuchElementException;
import flint.java.util.enumeration : Enumeration;

@safe:

private final class IntEnumeration : Enumeration!int
{
    private int cursor;
    int availabilityChecks;

    mixin Enumeration!int.Defaults;

    bool hasMoreElements()
    {
        ++availabilityChecks;
        return cursor < 2;
    }

    int nextElement()
    {
        if (cursor == 2)
            throw new NoSuchElementException("empty");
        return ++cursor;
    }
}

@("Enumeration asIterator traverses the remaining values through the existing enumeration")
unittest
{
    import std.exception : collectException;

    auto values = new IntEnumeration;
    Enumeration!int enumeration = values;
    assert(enumeration.nextElement() == 1);

    Iterator!int iterator = enumeration.asIterator();
    assert(values.availabilityChecks == 0);
    assert(iterator.hasNext());
    assert(values.availabilityChecks == 1);
    auto unsupported = collectException!UnsupportedOperationException(iterator.remove());
    assert(unsupported !is null && unsupported.getMessage() == "remove");

    assert(iterator.next() == 2);
    assert(values.availabilityChecks == 1);
    assert(!iterator.hasNext());
    auto exhausted = collectException!NoSuchElementException(iterator.next());
    assert(exhausted !is null && exhausted.getMessage() == "empty");
}
