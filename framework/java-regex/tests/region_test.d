/++
Flint tests: Java's region and bounds controls against JDK 21. `golden/regions.tsv` is written by
`golden/GoldenRegex.java` from the pinned Temurin oracle; every row must agree.
+/
module flint.java.util.regex.region_test;

import flint.java.lang : IndexOutOfBoundsException;
import flint.java.util.regex.pattern : Matcher, Pattern;
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

private Matcher regionMatcher(Pattern pattern, string input, int start, int end, bool anchoring, bool transparent)
{
    return pattern.matcher(input).region(start, end).useAnchoringBounds(anchoring).useTransparentBounds(transparent);
}

@("Matcher.region, anchoring and transparency agree with Java SE 21")
unittest
{
    size_t rows;
    foreach (line; import("regions.tsv").splitLines())
    {
        if (line.length == 0)
            continue;
        auto row = fields(line);
        auto pattern = Pattern.compile(row[0], row[1].to!int);
        const input = row[2];
        const start = row[3].to!int;
        const end = row[4].to!int;
        const anchoring = row[5] == "1";
        const transparent = row[6] == "1";

        auto whole = regionMatcher(pattern, input, start, end, anchoring, transparent);
        assert(whole.regionStart() == start && whole.regionEnd() == end, line);
        assert(whole.matches() == (row[7] == "true"), line);

        auto prefix = regionMatcher(pattern, input, start, end, anchoring, transparent);
        assert(prefix.lookingAt() == (row[8] == "true"), line);

        auto finder = regionMatcher(pattern, input, start, end, anchoring, transparent);
        string sequence;
        while (finder.find())
        {
            if (sequence.length)
                sequence ~= ';';
            const group = finder.group();
            sequence ~= finder.start().to!string ~ "," ~ finder.end().to!string ~ "," ~ (group.isNull ? "" : group.get);
        }
        if (sequence.length == 0)
            sequence = "none";
        assert(sequence == row[9], line ~ " => " ~ sequence);
        ++rows;
    }
    assert(rows == 40);
}

@("region validation, the full-input reset and the bounds flags survive a reset")
unittest
{
    auto matcher = Pattern.compile("b").matcher("abc");
    matcher.region(2, 2);
    assert(matcher.regionStart() == 2 && matcher.regionEnd() == 2);
    matcher.useAnchoringBounds(false).useTransparentBounds(true);
    assert(!matcher.hasAnchoringBounds() && matcher.hasTransparentBounds());
    matcher.reset();
    assert(matcher.regionStart() == 0 && matcher.regionEnd() == 3, "reset restores the whole input");
    assert(!matcher.hasAnchoringBounds() && matcher.hasTransparentBounds(), "reset keeps the bounds flags");

    matcher.useAnchoringBounds(true).useTransparentBounds(false);
    matcher.reset("xy");
    assert(matcher.regionStart() == 0 && matcher.regionEnd() == 2);

    bool threw;
    try
    {
        matcher.region(-1, 2);
    }
    catch (IndexOutOfBoundsException)
        threw = true;
    assert(threw, "a negative start is rejected");
    threw = false;
    try
    {
        matcher.region(0, 3);
    }
    catch (IndexOutOfBoundsException)
        threw = true;
    assert(threw, "an end past the input is rejected");
    threw = false;
    try
    {
        matcher.region(2, 1);
    }
    catch (IndexOutOfBoundsException)
        threw = true;
    assert(threw, "a start past the end is rejected");
}
