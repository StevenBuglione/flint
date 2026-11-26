module uuid_java21_test;

import flint.java.util.uuid : UUID;
import std.conv : to;
import std.string : split, splitLines;

@safe:

@("UUID matches Java SE 21 signed words, bit fields, and canonical text")
unittest
{
    size_t rows;
    foreach (line; import("uuid-java21.tsv").splitLines())
    {
        auto fields = line.split("\t");
        const long most = fields[0].to!long;
        const long least = fields[1].to!long;
        auto value = new UUID(most, least);
        assert(value.getMostSignificantBits() == most, line);
        assert(value.getLeastSignificantBits() == least, line);
        assert(value.version_() == fields[2].to!int, line);
        assert(value.variant() == fields[3].to!int, line);
        assert(value.toString() == fields[4], line);
        ++rows;
    }
    assert(rows == 305);
}
