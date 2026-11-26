module flint.java.util.regex.pattern_test;

import flint.java.lang : IllegalArgumentException;
import flint.java.util.regex.pattern : Matcher, Pattern, PatternSyntaxException;

@safe:

@("a Pattern is reusable while each Matcher binds its own input")
unittest
{
    auto digits = Pattern.compile("([a-z]+)([0-9]{2})", Pattern.CASE_INSENSITIVE);
    Matcher first = digits.matcher("AbC09");
    Matcher second = digits.matcher("abc9");
    assert(first.pattern() is digits && second.pattern() is digits);
    assert(first.matches() && !second.matches() && first.matches());
    assert(first.groupCount() == 2 && second.groupCount() == 2);
    assert(digits.pattern() == "([a-z]+)([0-9]{2})");
    assert(digits.toString() == digits.pattern());
    assert(digits.flags() == Pattern.CASE_INSENSITIVE);
    assert(Pattern.matches("a.*b", "a--b"));
    assert(!Pattern.matches("a.*b", "a\nb"));
    assert(Pattern.matches("", ""));
}

@("embedded flags affect the Pattern flags outside groups")
unittest
{
    assert(Pattern.compile("a(?i)b").flags() == Pattern.CASE_INSENSITIVE);
    assert(Pattern.compile("(?i:a)b").flags() == 0);
    assert(Pattern.compile("(?-i)a", Pattern.CASE_INSENSITIVE).flags() == 0);
}

@("Pattern rejects unknown flags and reports Java syntax exceptions")
unittest
{
    try
    {
        Pattern.compile("abc", 1 << 9);
        assert(0, "expected invalid flags to throw");
    }
    catch (IllegalArgumentException)
    {
    }

    try
    {
        Pattern.compile("(");
        assert(0, "expected an unclosed group to throw");
    }
    catch (PatternSyntaxException failure)
    {
        assert(failure.getDescription() == "Unclosed group");
        assert(failure.getPattern() == "(");
        assert(failure.getIndex() == 1);
        assert(failure.getMessage() == "Unclosed group near index 1\n(");
    }
}
