/++
Flint tests: Java's replacement and named-capture surface against JDK 21. `golden/replace.tsv`, `named.tsv`
and `quote.tsv` are written by `golden/GoldenRegex.java` from the pinned Temurin oracle; every row must agree,
and a Java rejection (`error`) must throw the same broad exception class here.
+/
module flint.java.util.regex.search_replace_test;

import flint.java.lang : IllegalArgumentException, IndexOutOfBoundsException, IllegalStateException,
    NullPointerException;
import flint.java.util.function_ : Function;
import flint.java.util.regex.matchresult : MatchResult;
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

@("Matcher.replaceAll and replaceFirst agree with Java SE 21")
unittest
{
    size_t rows;
    foreach (line; import("replace.tsv").splitLines())
    {
        if (line.length == 0)
            continue;
        auto row = fields(line);
        auto pattern = Pattern.compile(row[0]);
        const expectedAll = row[3];
        const expectedFirst = row[4];
        string all, first;
        bool threwAll, threwFirst;
        try
            all = pattern.matcher(row[1]).replaceAll(row[2]);
        catch (IllegalArgumentException)
            threwAll = true;
        catch (IndexOutOfBoundsException)
            threwAll = true;
        try
            first = pattern.matcher(row[1]).replaceFirst(row[2]);
        catch (IllegalArgumentException)
            threwFirst = true;
        catch (IndexOutOfBoundsException)
            threwFirst = true;
        if (expectedAll == "error")
            assert(threwAll, line);
        else
            assert(!threwAll && all == expectedAll, line ~ " => " ~ all);
        if (expectedFirst == "error")
            assert(threwFirst, line);
        else
            assert(!threwFirst && first == expectedFirst, line ~ " => " ~ first);
        ++rows;
    }
    assert(rows == 31);
}

private Function!(MatchResult, string) replacerFor(string kind)
{
    switch (kind)
    {
    case "wrap":
        return Function!(MatchResult, string).of((MatchResult r) => "[" ~ r.group.get ~ "]");
    case "span":
        return Function!(MatchResult, string).of(
                (MatchResult r) => r.start.to!string ~ "," ~ r.end.to!string ~ "=" ~ r.group.get);
    case "null":
        return Function!(MatchResult, string).of((MatchResult r) { return cast(string) null; });
    default:
        throw new IllegalArgumentException(kind);
    }
}

@("Matcher.replaceAll and replaceFirst over a replacer function agree with Java SE 21")
unittest
{
    size_t rows;
    foreach (line; import("replace_function.tsv").splitLines())
    {
        if (line.length == 0)
            continue;
        auto row = fields(line);
        auto replacer = replacerFor(row[2]);
        string all, first;
        bool threwAll, threwFirst;
        try
            all = Pattern.compile(row[0]).matcher(row[1]).replaceAll(replacer);
        catch (NullPointerException)
            threwAll = true;
        try
            first = Pattern.compile(row[0]).matcher(row[1]).replaceFirst(replacer);
        catch (NullPointerException)
            threwFirst = true;
        if (row[3] == "npe")
            assert(threwAll, line);
        else
            assert(!threwAll && all == row[3], line ~ " => " ~ all);
        if (row[4] == "npe")
            assert(threwFirst, line);
        else
            assert(!threwFirst && first == row[4], line ~ " => " ~ first);
        ++rows;
    }
    assert(rows == 13);
}

@("Matcher and MatchResult named capture access agrees with Java SE 21")
unittest
{
    size_t rows;
    foreach (line; import("named.tsv").splitLines())
    {
        if (line.length == 0)
            continue;
        auto row = fields(line);
        auto matcher = Pattern.compile(row[0]).matcher(row[1]);
        matcher.find();
        string group, start, end;
        try
        {
            auto text = matcher.group(row[2]);
            group = text.isNull ? "null" : text.get;
            start = matcher.start(row[2]).to!string;
            end = matcher.end(row[2]).to!string;
        }
        catch (IllegalArgumentException)
            group = start = end = "error";
        catch (IllegalStateException)
            group = start = end = "error";
        assert(group == row[3], line);
        assert(start == row[4] && end == row[5], line);
        ++rows;
    }
    assert(rows == 6);
}

@("Matcher.quoteReplacement escapes dollar and backslash as Java does")
unittest
{
    size_t rows;
    foreach (line; import("quote.tsv").splitLines())
    {
        if (line.length == 0)
            continue;
        auto row = fields(line);
        assert(Matcher.quoteReplacement(row[0]) == row[1], line);
        ++rows;
    }
    assert(rows == 8);
}
