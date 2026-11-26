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

@("the internal Pattern helper matches the entire input without a Matcher allocation")
unittest
{
    import core.memory : GC;

    struct Case
    {
        string expression;
        string text;
        bool expected;
    }

    foreach (example; [
        Case("pet", "pet", true), Case("pet", "carpet", false), Case("^pet$", "pet\n", false),
        Case("^pet$", "pet", true), Case("^$", "", true), Case("pet", "", false),
    ])
    {
        auto pattern = Pattern.compile(example.expression);
        assert(pattern.matcher(example.text).matches() == example.expected);

        const Pattern compiled = pattern;
        char[6] buffer;
        scope input = buffer[0 .. example.text.length];
        input[] = example.text[];
        const before = GC.stats().allocatedInCurrentThread;
        const matched = compiled.matches(input);
        assert(GC.stats().allocatedInCurrentThread == before);
        assert(matched == example.expected);
    }
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
