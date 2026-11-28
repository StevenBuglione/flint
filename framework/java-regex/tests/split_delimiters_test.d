/++
Flint tests: Java's `Pattern.splitWithDelimiters` against JDK 21. `golden/splitdelim.tsv` is written by
`golden/GoldenRegex.java` from the pinned Temurin oracle; every row must agree.
+/
module flint.java.util.regex.split_delimiters_test;

import flint.java.util.regex.pattern : Pattern;
import std.conv : to;
import std.string : splitLines;

@safe:

private string unescape(string field) pure
{
    string result;
    for (size_t i; i < field.length; ++i)
    {
        if (field[i] != '\\' || i + 1 >= field.length)
        {
            result ~= field[i];
            continue;
        }
        const c = field[++i];
        switch (c)
        {
        case 't':
            result ~= '\t';
            break;
        case 'n':
            result ~= '\n';
            break;
        case 'r':
            result ~= '\r';
            break;
        case 'u':
            uint code;
            foreach (digit; field[i + 1 .. i + 5])
                code = (code << 4) | (digit <= '9' ? digit - '0' : (digit | 32) - 'a' + 10);
            result ~= cast(char) code;
            i += 4;
            break;
        default:
            result ~= c;
        }
    }
    return result;
}

private string[] fields(string line) pure
{
    string[] result;
    size_t start;
    foreach (i, c; line)
    {
        if (c == '\t')
        {
            result ~= unescape(line[start .. i]);
            start = i + 1;
        }
    }
    result ~= unescape(line[start .. $]);
    return result;
}

@("Pattern.splitWithDelimiters agrees with Java SE 21")
unittest
{
    size_t rows;
    foreach (line; import("splitdelim.tsv").splitLines())
    {
        if (line.length == 0)
            continue;
        auto row = fields(line);
        auto pattern = Pattern.compile(row[0]);
        auto actual = pattern.splitWithDelimiters(row[1], row[2].to!int);
        assert(actual.length.to!string == row[3], line ~ " => count " ~ actual.length.to!string);
        foreach (i; 0 .. actual.length)
        {
            assert(i + 4 < row.length, line ~ " => too many entries");
            assert(actual[i] == row[i + 4], line ~ " => [" ~ i.to!string ~ "] " ~ actual[i]);
        }
        ++rows;
    }
    assert(rows == 22);
}
