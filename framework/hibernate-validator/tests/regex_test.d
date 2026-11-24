/++
Flint tests: the run-time regular expression engine against java.util.regex. `golden/regex.tsv` holds JDK 21's
`Pattern.compile(regex, flags).matcher(input).matches()` for each case, or "error" for a pattern it rejects
(`golden/GoldenRegex.java` writes it). Every case must agree, except the features listed in `unsupported`, which
must fail with RegexUnsupportedException rather than give a wrong answer.
+/
module flint.hibernate.validator.regex_test;

import flint.hibernate.validator.internal.regex : Regex, RegexSyntaxException,
    RegexUnsupportedException, compileRegex;

@safe:

// Patterns whose features the engine does not have yet; JDK accepts them.
private static immutable string[] unsupported = [
    "é", // with UNICODE_CASE | CASE_INSENSITIVE
    "(?U)\\w", // UNICODE_CHARACTER_CLASS
    "\\N{LATIN SMALL LETTER A}", // named characters
];

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
            import std.conv : to;

            result ~= cast(char) field[i + 1 .. i + 5].to!uint(16);
            i += 4;
            break;
        default:
            result ~= c;
        }
    }
    return result;
}

private string[] split(string line) pure
{
    string[] fields;
    size_t start;
    foreach (i, c; line)
        if (c == '\t')
        {
            fields ~= line[start .. i];
            start = i + 1;
        }
    return fields ~ line[start .. $];
}

@("java.util.regex parity: every golden case agrees with JDK 21")
unittest
{
    import std.conv : to;

    size_t checked, gaps;
    string failures;
    Regex compiled;
    string compiledKey;
    string compileOutcome; // null when it compiled, else "error" or "unsupported: ..."
    foreach (line; split(import("regex.tsv")[0 .. $ - 1], '\n'))
    {
        const fields = split(line);
        assert(fields.length == 4, line);
        const regex = unescape(fields[0]);
        const key = fields[0] ~ "\t" ~ fields[1];
        if (key != compiledKey)
        {
            compiledKey = key;
            compileOutcome = null;
            try
                compiled = compileRegex(regex, fields[1].to!int);
            catch (RegexSyntaxException)
                compileOutcome = "error";
            catch (RegexUnsupportedException e)
                compileOutcome = "unsupported: " ~ e.msg;
        }
        if (compileOutcome.length > 11 && compileOutcome[0 .. 11] == "unsupported")
        {
            bool known;
            foreach (gap; unsupported)
                known = known || gap == regex;
            if (known)
            {
                ++gaps;
                continue;
            }
        }
        const actual = compileOutcome !is null ? compileOutcome : compiled.matches(unescape(fields[2]))
            ? "true" : "false";
        ++checked;
        if (actual != fields[3])
            failures ~= "  " ~ fields[0] ~ " (flags " ~ fields[1] ~ ") on \"" ~ fields[2] ~ "\": JDK "
                ~ fields[3] ~ ", Flint " ~ actual ~ "\n";
    }
    assert(failures.length == 0, "regex cases that differ from JDK 21:\n" ~ failures);
    assert(checked > 340 && gaps <= 5, checked.to!string ~ " checked, " ~ gaps.to!string ~ " gaps");
}

private string[] split(string text, char separator) pure
{
    string[] parts;
    size_t start;
    foreach (i, c; text)
        if (c == separator)
        {
            parts ~= text[start .. i];
            start = i + 1;
        }
    return parts ~ text[start .. $];
}

@("a catastrophic pattern stops at the step budget instead of hanging")
unittest
{
    import flint.hibernate.validator.internal.regex : RegexBudgetException;

    const regex = compileRegex("(a+)+b");
    char[] input = new char[40];
    input[] = 'a';
    try
    {
        regex.matches(input);
        assert(false, "expected RegexBudgetException");
    }
    catch (RegexBudgetException)
    {
    }
}

@("long inputs match without deep recursion")
unittest
{
    const regex = compileRegex("(?:[a-z]+ ?)*");
    char[] input = new char[200_000];
    foreach (i, ref c; input)
        c = i % 7 == 6 ? ' ' : 'a';
    assert(regex.matches(input));
}

@("@Pattern runs java.util.regex expressions: look-ahead, back-references, counted repetition and flags")
unittest
{
    import flint.hibernate.validator.validator_test_support : isValidFor;
    import flint.jakarta.validation.constraints : Pattern;

    const password = Pattern(regexp: "^(?=.*\\d)(?=.*[a-z])(?=.*[A-Z]).{8,}$");
    assert(isValidFor(password, "Passw0rdX") && !isValidFor(password, "password1"));
    const doubled = Pattern(regexp: "(\\w)\\1+");
    assert(isValidFor(doubled, "aaa") && !isValidFor(doubled, "ab"));
    const digits = Pattern(regexp: "[0-9]{1,160}");
    assert(isValidFor(digits, "0123456789") && !isValidFor(digits, ""));
    const insensitive = Pattern(regexp: "abc", flags: [Pattern.Flag.CASE_INSENSITIVE]);
    assert(isValidFor(insensitive, "ABC") && !isValidFor(Pattern(regexp: "abc"), "ABC"));
    const lines = Pattern(regexp: "^a$\\n^b$", flags: [Pattern.Flag.MULTILINE]);
    assert(isValidFor(lines, "a\nb"));
}

@("matches past the inline buffers: long text, many groups, deep backtracking")
unittest
{
    // 256 code points fit on the stack, 257 do not; 'é' takes two bytes.
    foreach (n; [255, 256, 257, 600])
    {
        string text;
        foreach (i; 0 .. n)
            text ~= i % 2 ? "é" : "a";
        assert(compileRegex("(?:aé)*a?").matches(text));
        assert(!compileRegex("(?:aé)*b").matches(text));
    }
    // 20 groups need 42 capture slots, more than the 32 on the stack.
    string groups, input;
    foreach (i; 0 .. 20)
    {
        groups ~= "(x)";
        input ~= "x";
    }
    assert(compileRegex(groups ~ "\\1").matches(input ~ "x"));
    assert(!compileRegex(groups ~ "\\1").matches(input ~ "y"));
    // Choice points past the 64 inline frames, then backtracking through all of them.
    string as;
    foreach (i; 0 .. 200)
        as ~= "a";
    assert(compileRegex("a*a*b").matches(as ~ "b"));
    assert(!compileRegex("a*a*b").matches(as));
    assert(compileRegex("(a)*(a)*").matches(as));
}

@("character classes answer ASCII from their table and the rest from their terms")
unittest
{
    const letters = compileRegex("[\\p{L}]+");
    assert(letters.matches("Ada") && letters.matches("Zoë") && !letters.matches("Ada1"));
    const negated = compileRegex("[^a-c&&[^x]]+");
    assert(negated.matches("dxyé") && !negated.matches("dab"));
    const insensitive = compileRegex("[a-c]+", 0x02);
    assert(insensitive.matches("aBc") && !insensitive.matches("abd"));
}

@("a greedy loop over one character gives characters back one at a time")
unittest
{
    assert(compileRegex("a*ab").matches("aaab") && !compileRegex("a*ab").matches("b"));
    assert(compileRegex("[a-c]*cc").matches("abcbcc") && !compileRegex("[a-c]*cc").matches("abcbc"));
    assert(compileRegex("x.*y.*z").matches("x--y--y--z") && !compileRegex("x.*y").matches("x\ny"));
    assert(compileRegex("(?i)a*A").matches("aAaA") && compileRegex("é*éa").matches("éééa"));
    assert(compileRegex("(a*)b\\1").matches("aabaa") && !compileRegex("(a*)b\\1").matches("aaba"));
}
