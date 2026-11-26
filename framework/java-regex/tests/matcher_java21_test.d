module flint.java.util.regex.matcher_java21_test;

import flint.java.util.regex.pattern : Pattern;
import std.conv : to;
import std.string : split, splitLines;

@safe:

@("Matcher pattern and capture count agree with Java SE 21 before and after matches")
unittest
{
    size_t rows;
    foreach (line; import("matcher.tsv").splitLines())
    {
        auto fields = line.split("\t");
        const int groups = fields[2].to!int;
        auto pattern = Pattern.compile(fields[0]);
        auto matcher = pattern.matcher(fields[1]);
        assert(matcher.pattern() is pattern, line);
        assert(pattern.pattern() == fields[0] && pattern.toString() == fields[0], line);
        assert(matcher.groupCount() == groups, line);
        assert(matcher.matches() == (fields[3] == "true"), line);
        assert(matcher.groupCount() == groups && matcher.pattern() is pattern, line);
        ++rows;
    }
    assert(rows == 20);
}
