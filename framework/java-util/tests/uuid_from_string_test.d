module uuid_from_string_test;

import flint.java.lang : IllegalArgumentException, NumberFormatException;
import flint.java.util.uuid : UUID;
import std.string : split, splitLines;

@safe:

// Java SE 21's outcome for one input: the canonical text, or the exception type and detail message.
private string outcome(string input)
{
    try
        return "OK " ~ UUID.fromString(input).toString();
    catch (NumberFormatException e)
        return "NFE " ~ e.msg;
    catch (IllegalArgumentException e)
        return "IAE " ~ e.msg;
}

@("UUID.fromString matches Java SE 21, including the shortened fields and the parser's messages")
unittest
{
    size_t rows;
    foreach (line; import("uuid-fromstring-java21.tsv").splitLines())
    {
        const fields = line.split("\t");
        assert(fields.length == 3, line);
        const expected = fields[1] ~ " " ~ fields[2];
        const actual = outcome(fields[0]);
        assert(actual == expected, line ~ ": " ~ actual);
        ++rows;
    }
    assert(rows == 124);
}

@("A null UUID string is Java's empty string (R26)")
unittest
{
    try
    {
        UUID.fromString(null);
        assert(false);
    }
    catch (IllegalArgumentException e)
        assert(e.msg == "Invalid UUID string: ", e.msg);
}
