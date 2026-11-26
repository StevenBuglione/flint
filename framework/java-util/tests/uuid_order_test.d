module uuid_order_test;

import flint.java.lang : Comparable, NullPointerException;
import flint.java.util.uuid : UUID;
import std.conv : to;
import std.exception : assertThrown;
import std.string : split, splitLines;

@safe:

@("UUID comparison and hashing match Java SE 21")
unittest
{
    size_t rows;
    foreach (line; import("uuid-java21-order.tsv").splitLines())
    {
        auto fields = line.split("\t");
        auto left = new UUID(fields[0].to!long, fields[1].to!long);
        auto right = new UUID(fields[2].to!long, fields[3].to!long);
        const int order = fields[4].to!int;
        const bool equal = fields[5] == "true";
        Comparable!UUID comparable = left;
        assert(comparable.compareTo(right) == order, line);
        assert((left < right) == (order < 0), line);
        assert(left.equals(right) == equal, line);
        assert((left == right) == equal, line);
        assert(left.hashCode() == fields[6].to!int, line);
        ++rows;
    }
    assert(rows == 100);
}

@("UUID equality follows values through Object and associative arrays")
unittest
{
    auto original = new UUID(-11L, 110L);
    auto equalValue = new UUID(-11L, 110L);
    Object second = equalValue;
    assert(original.opEquals(second));
    assert(!original.equals(null));
    assert(!original.equals(new Object));
    assertThrown!NullPointerException(original.compareTo(null));

    int[UUID] values;
    values[original] = 29;
    assert(values[equalValue] == 29);
}
