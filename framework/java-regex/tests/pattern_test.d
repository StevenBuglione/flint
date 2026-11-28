module flint.java.util.regex.pattern_test;

import flint.java.lang : IllegalArgumentException;
import flint.java.util.function_ : Predicate;
import flint.java.util.regex.pattern : Matcher, Pattern, PatternSyntaxException;

@safe:

version (Windows)
{
    private enum eol = "\r\n";
}
else
{
    private enum eol = "\n";
}

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
        int flags;
    }

    foreach (example; [
        Case("pet", "pet", true), Case("pet", "carpet", false), Case("^pet$", "pet\n", false),
        Case("^pet$", "pet", true), Case("^$", "", true), Case("pet", "", false),
        Case("a.b", "a.b", true, Pattern.LITERAL), Case("a.b", "axb", false, Pattern.LITERAL),
    ])
    {
        auto pattern = Pattern.compile(example.expression, example.flags);
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
        assert(failure.getDescription().get == "Unclosed group");
        assert(failure.getPattern().get == "(");
        assert(failure.getIndex() == 1);
        assert(failure.getMessage() == "Unclosed group near index 1" ~ eol ~ "(");
    }
}

@("LITERAL matches the expression verbatim and never creates capturing groups")
unittest
{
    const expression = "[abc\\Q\\E]#$";
    auto compiled = Pattern.compile(expression, Pattern.LITERAL);
    assert(compiled.pattern() == expression && compiled.flags() == Pattern.LITERAL);
    auto match = compiled.matcher(expression);
    assert(match.matches() && match.groupCount() == 0);
    assert(!compiled.matcher("abc").matches());
    assert(Pattern.compile("a.b", Pattern.LITERAL).matcher("a.b").matches());
    assert(!Pattern.compile("a.b", Pattern.LITERAL).matcher("axb").matches());
    assert(!Pattern.compile("(?i)A", Pattern.LITERAL).matcher("(?i)a").matches());
    assert(Pattern.compile("", Pattern.LITERAL).matcher("").matches());
    assert(!Pattern.compile("", Pattern.LITERAL).matcher("x").matches());
    assert(Pattern.compile("a\0b", Pattern.LITERAL).matcher("a\0b").matches());
}

@("LITERAL preserves flags and uses only applicable matching options")
unittest
{
    enum literal = Pattern.LITERAL;
    enum ignored = Pattern.COMMENTS | Pattern.MULTILINE | Pattern.DOTALL | Pattern.UNIX_LINES;
    auto pattern = Pattern.compile(" x#\n^A$", literal | ignored);
    assert(pattern.flags() == (literal | ignored));
    assert(pattern.matcher(" x#\n^A$").matches());
    pattern = Pattern.compile("aä😀", literal | Pattern.CASE_INSENSITIVE);
    assert(pattern.matcher("Aä😀").matches());
    assert(!pattern.matcher("AÄ😀").matches());
    assert(!Pattern.compile("å", literal | Pattern.CANON_EQ).matcher("a\u030a").matches());
    pattern = Pattern.compile("\\w", literal | Pattern.UNICODE_CHARACTER_CLASS);
    assert(pattern.flags() == (literal | Pattern.UNICODE_CHARACTER_CLASS | Pattern.UNICODE_CASE));
    assert(pattern.matcher("\\w").matches());
}

@("PatternSyntaxException keeps absent and empty text distinct")
unittest
{
    import std.typecons : Nullable;

    auto exception = new PatternSyntaxException(Nullable!string.init, Nullable!string(""), -2);
    assert(exception.getDescription().isNull);
    assert(!exception.getPattern().isNull && exception.getPattern().get == "");
    assert(exception.getIndex() == -2);
    assert(exception.getMessage() == "null" ~ eol);

    exception = new PatternSyntaxException("", "\t😀x", 2);
    assert(!exception.getDescription().isNull);
    assert(exception.getPattern().get == "\t😀x");
    assert(exception.getMessage() == " near index 2" ~ eol ~ "\t😀x" ~ eol ~ "\t ^");

    exception = new PatternSyntaxException(Nullable!string("bad"), Nullable!string.init, 0);
    assert(exception.getPattern().isNull);
    assert(exception.getMessage() == "bad near index 0" ~ eol ~ "null");

    exception = new PatternSyntaxException("bad", "x", int.max);
    assert(exception.getMessage() == "bad near index 2147483647" ~ eol ~ "x");
}

@("Matcher captures distinguish an unmatched group from an empty group and use UTF-16 offsets")
unittest
{
    import core.memory : GC;
    import flint.java.util.regex.matchresult : MatchResult;

    auto matcher = Pattern.compile("(😀)(a)?()").matcher("😀");
    MatchResult result = matcher;
    assert(!matcher.hasMatch());
    assert(matcher.matches() && matcher.hasMatch());
    assert(result.groupCount() == 3);
    assert(result.start() == 0 && result.end() == 2 && result.group().get == "😀");
    assert(result.start(1) == 0 && result.end(1) == 2 && result.group(1).get == "😀");
    assert(result.start(2) == -1 && result.end(2) == -1 && result.group(2).isNull);
    assert(result.start(3) == 2 && result.end(3) == 2 && !result.group(3).isNull && result.group(3).get == "");

    const before = GC.stats().allocatedInCurrentThread;
    assert(matcher.matches());
    assert(GC.stats().allocatedInCurrentThread == before);
}

@("Matcher rejects capture access before a successful whole-input match")
unittest
{
    import flint.java.lang : IllegalStateException, IndexOutOfBoundsException;
    import std.exception : assertThrown;

    auto matcher = Pattern.compile("(a)").matcher("b");
    assertThrown!IllegalStateException(matcher.start(99));
    assert(!matcher.matches() && !matcher.hasMatch());
    assertThrown!IllegalStateException(matcher.group());
    matcher = Pattern.compile("a").matcher("a");
    assert(matcher.matches() && matcher.hasMatch());
    assert(matcher.group().get == "a");
    assertThrown!IndexOutOfBoundsException(matcher.end(-1));
    assertThrown!IndexOutOfBoundsException(matcher.group(1));
}

@("Matcher lookingAt records a prefix match and a later failure invalidates its captures")
unittest
{
    import flint.java.lang : IllegalStateException;
    import std.exception : assertThrown;

    auto matcher = Pattern.compile("(😀)(a)?").matcher("😀tail");
    assert(matcher.lookingAt() && matcher.hasMatch());
    assert(matcher.start() == 0 && matcher.end() == 2 && matcher.group(1).get == "😀");
    assert(matcher.group(2).isNull);
    assert(!matcher.matches() && !matcher.hasMatch());
    assertThrown!IllegalStateException(matcher.start());
    assert(matcher.lookingAt());
    assert(!matcher.reset("x😀").lookingAt());
    assert(!matcher.hasMatch());
    auto zero = Pattern.compile("()").matcher("word");
    assert(zero.lookingAt() && zero.end() == 0 && !zero.group(1).isNull && zero.group(1).get == "");
}

@("Matcher reset retains the pattern and clears captures before the next match")
unittest
{
    import core.memory : GC;
    import flint.java.lang : IllegalStateException;
    import std.exception : assertThrown;

    auto compiled = Pattern.compile("(😀)(a)?");
    auto matcher = compiled.matcher("😀tail");
    assert(matcher.lookingAt());
    assert(matcher.reset() is matcher && !matcher.hasMatch() && matcher.pattern() is compiled);
    assertThrown!IllegalStateException(matcher.group());
    assert(matcher.lookingAt());
    const before = GC.stats().allocatedInCurrentThread;
    assert(matcher.reset("😀a") is matcher && !matcher.hasMatch());
    assert(matcher.matches() && matcher.group(2).get == "a" && matcher.end(2) == 3);
    assert(GC.stats().allocatedInCurrentThread == before);
    auto empty = Pattern.compile("()").matcher("x");
    assert(empty.reset(null).matches() && empty.end() == 0);
}

@("Matcher snapshots keep both the captured text and offsets after later matches")
unittest
{
    import flint.java.lang : IllegalStateException;
    import std.exception : assertThrown;

    auto matcher = Pattern.compile("(😀)(a)?()").matcher("😀a");
    auto absent = matcher.toMatchResult();
    assert(absent.groupCount() == 3 && cast(Matcher) absent is null);
    assertThrown!IllegalStateException(absent.start(99));
    assert(matcher.matches());
    auto first = matcher.toMatchResult();
    assert(cast(Matcher) first is null);
    assert(matcher.reset("😀tail").lookingAt() && matcher.group(2).isNull);
    assert(first.group().get == "😀a" && first.start() == 0 && first.end() == 3);
    assert(first.group(2).get == "a" && first.start(2) == 2 && first.end(2) == 3);
    assert(!first.group(3).isNull && first.group(3).get == "" && first.end(3) == 3);
    auto second = matcher.toMatchResult();
    assert(!matcher.reset("fail").matches());
    assertThrown!IllegalStateException(matcher.toMatchResult().group());
    assertThrown!IllegalStateException(absent.group());
    assert(second.group().get == "😀" && second.group(2).isNull && second.end(3) == 2);
    auto noCaptures = Pattern.compile("a").matcher("a");
    assert(noCaptures.matches());
    auto whole = noCaptures.toMatchResult();
    noCaptures.reset("b");
    assert(whole.groupCount() == 0 && whole.group().get == "a" && whole.end() == 1);
}

@("Matcher.find walks successive matches and reports UTF-16 offsets")
unittest
{
    import flint.java.lang : IndexOutOfBoundsException;
    import std.exception : assertThrown;

    auto matcher = Pattern.compile("(b.)").matcher("😀bc xbd");
    assert(matcher.find());
    assert(matcher.group().get == "bc" && matcher.start() == 2 && matcher.end() == 4);
    assert(matcher.group(1).get == "bc" && matcher.start(1) == 2 && matcher.end(1) == 4);
    assert(matcher.find());
    assert(matcher.group().get == "bd" && matcher.start() == 6 && matcher.end() == 8);
    assert(!matcher.find() && !matcher.hasMatch());
    assert(matcher.find(4) && matcher.start() == 6 && matcher.group().get == "bd");
    assertThrown!IndexOutOfBoundsException(matcher.find(-1));
    assertThrown!IndexOutOfBoundsException(matcher.find(9));
}

@("Matcher.find yields the empty matches Java reports")
unittest
{
    auto matcher = Pattern.compile("a*").matcher("ba");
    assert(matcher.find() && matcher.start() == 0 && matcher.end() == 0);
    assert(matcher.find() && matcher.start() == 1 && matcher.end() == 2 && matcher.group().get == "a");
    assert(matcher.find() && matcher.start() == 2 && matcher.end() == 2);
    assert(!matcher.find());

    auto prefix = Pattern.compile("a").matcher("aXaa");
    assert(prefix.lookingAt() && prefix.end() == 1);
    assert(prefix.find() && prefix.start() == 2 && prefix.end() == 3);
    assert(prefix.find() && prefix.start() == 3 && prefix.end() == 4);

    auto anchored = Pattern.compile("^b").matcher("ab");
    assert(!anchored.find());
}

@("Pattern.split follows Java's limit rules and UTF-16 boundaries")
unittest
{
    auto commas = Pattern.compile(",");
    assert(commas.split("a,b,,c") == ["a", "b", "", "c"]);
    assert(commas.split("a,b,,") == ["a", "b"]);
    assert(commas.split("a,b,,", -1) == ["a", "b", "", ""]);
    assert(commas.split("a,b,c,d", 2) == ["a", "b,c,d"]);
    assert(commas.split("") == [""]);
    assert(commas.split("abc") == ["abc"]);

    auto empty = Pattern.compile("");
    assert(empty.split("abc") == ["a", "b", "c"]);
    assert(empty.split("abc", 2) == ["a", "bc"]);
    assert(empty.split("😀b") == ["😀", "b"]);

    assert(Pattern.compile("\\s+").split(" one two ") == ["", "one", "two"]);
    assert(Pattern.compile("x").split(null) == [""]);
}

@("Pattern.quote compiles literal text, including embedded terminator sequences")
unittest
{
    foreach (text; ["plain", "a.b*c", "a\\E*b", "\\Q", "", "😀|"])
    {
        auto literal = Pattern.compile(Pattern.quote(text));
        assert(literal.matcher(text).matches());
        assert(literal.pattern() == Pattern.quote(text));
    }
    assert(!Pattern.compile(Pattern.quote("a.b")).matcher("axb").matches());
}

@("Pattern.asPredicate finds and asMatchPredicate matches whole inputs, as Java SE 21 does")
unittest
{
    auto word = Pattern.compile("[a-z]+");
    auto find = word.asPredicate();
    auto whole = word.asMatchPredicate();
    assert(find.test("abc"));
    assert(find.test("  abc  "));
    assert(!whole.test("  abc  "));
    assert(whole.test("abc"));
    assert(!find.test("123"));
    assert(!find.test(null));
    assert(!whole.test(null));
    assert(whole.test("one"));
    assert(!whole.test("one two"));

    auto empty = Pattern.compile("");
    assert(empty.asPredicate().test(""));
    assert(empty.asMatchPredicate().test(""));
    assert(empty.asPredicate().test(null));
    assert(empty.asMatchPredicate().test(null));
}
