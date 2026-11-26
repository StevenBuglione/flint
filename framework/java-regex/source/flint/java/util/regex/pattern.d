/// Java SE 21 regular-expression compilation and whole-input matching.
module flint.java.util.regex.pattern;

import flint.java.lang : IllegalArgumentException, IllegalStateException, IndexOutOfBoundsException;
import flint.java.util.regex.internal.engine : Regex, RegexFlag, RegexSyntaxException, compileRegex;
import flint.java.util.regex.matchresult : MatchResult;
import std.typecons : Nullable;

@safe:

/// An immutable compiled expression that can be shared across matchers.
final class Pattern
{
    enum int UNIX_LINES = RegexFlag.UNIX_LINES;
    enum int CASE_INSENSITIVE = RegexFlag.CASE_INSENSITIVE;
    enum int COMMENTS = RegexFlag.COMMENTS;
    enum int MULTILINE = RegexFlag.MULTILINE;
    enum int LITERAL = RegexFlag.LITERAL;
    enum int DOTALL = RegexFlag.DOTALL;
    enum int UNICODE_CASE = RegexFlag.UNICODE_CASE;
    enum int CANON_EQ = RegexFlag.CANON_EQ;
    enum int UNICODE_CHARACTER_CLASS = RegexFlag.UNICODE_CHARACTER_CLASS;

    private immutable string expression;
    private const Regex program;

    private this(string expression, Regex program)
    {
        this.expression = expression;
        this.program = program;
    }

    /// Compile with default flags.
    static Pattern compile(string regex)
    {
        return compile(regex, 0);
    }

    /// Compile with the specified Java flag bits.
    static Pattern compile(string regex, int flags)
    {
        enum allFlags = (UNICODE_CHARACTER_CLASS << 1) - 1;
        if (flags & ~allFlags)
            throw new IllegalArgumentException("Unknown regular expression flags");
        return new Pattern(regex, compilePattern(regex, flags));
    }

    /// Compile an expression and match the entire input once.
    static bool matches(string regex, scope const(char)[] input)
    {
        return compilePattern(regex, 0).matches(input);
    }

    /// Test the entire borrowed input against this pattern without constructing a Matcher.
    package(flint) bool matches(scope const(char)[] input) const
    {
        return program.matches(input);
    }

    /// Bind one input to the compiled expression.
    Matcher matcher(string input)
    {
        return new Matcher(this, input);
    }

    /// The flags in effect after compiling this expression.
    int flags() const pure nothrow @nogc
    {
        return program.flags();
    }

    /// The original expression.
    string pattern() const pure nothrow @nogc
    {
        return expression;
    }

    override string toString() const pure nothrow @nogc
    {
        return expression;
    }
}

// Numbered access is shared by a live Matcher and a detached result.
private class NumberedMatch : MatchResult
{
    private string input;
    private immutable int groups;
    private int[2] wholeMatch;
    private int[] capturePoints;
    private bool matched;

    private struct Capture
    {
        int first, last;
    }

    private this(string input, int groups) pure nothrow @nogc
    {
        this.input = input;
        this.groups = groups;
    }

    /// Count the capturing groups defined by the pattern.
    final override int groupCount() const pure nothrow @nogc
    {
        return groups;
    }

    final override int start() const
    {
        return start(0);
    }

    final override int start(int group) const
    {
        return utf16Offset(capture(group).first);
    }

    final override int end() const
    {
        return end(0);
    }

    final override int end(int group) const
    {
        return utf16Offset(capture(group).last);
    }

    final override Nullable!string group() const
    {
        return group(0);
    }

    final override Nullable!string group(int index) const
    {
        const range = capture(index);
        if (range.first < 0)
            return Nullable!string.init;
        size_t at;
        advance(range.first, at);
        const first = at;
        advance(range.last - range.first, at);
        return Nullable!string(input[first .. at]);
    }

    private Capture capture(int group) const
    {
        if (!matched)
            throw new IllegalStateException("No match found");
        if (cast(uint) group > cast(uint) groupCount())
            throw new IndexOutOfBoundsException("Invalid capture group");
        if (!capturePoints.length)
            return Capture(wholeMatch[0], wholeMatch[1]);
        const slot = 2 * group;
        const pair = capturePoints[slot .. slot + 2];
        return Capture(pair[0], pair[1]);
    }

    pragma(inline, false) private int utf16Offset(int point) const pure nothrow @nogc
    {
        if (point < 0)
            return -1;
        size_t at;
        return advance(point, at);
    }

    pragma(inline, false) private int advance(int points, ref size_t at) const pure nothrow @nogc
    {
        import flint.engine.aot.text : decodeUtf8;

        int units;
        foreach (i; 0 .. points)
            units += decodeUtf8(input, at) > wchar.max ? 2 : 1;
        return units;
    }
}

/// Whole-input or prefix matching against a compiled Pattern.
final class Matcher : NumberedMatch
{
    private Pattern compiled;

    private this(Pattern compiled, string input)
    {
        super(input, compiled.program.groupCount());
        this.compiled = compiled;
    }

    /// The compiled expression associated with this matcher.
    Pattern pattern() pure nothrow @nogc
    {
        return compiled;
    }

    /// Test the entire input and record its captures.
    bool matches()
    {
        return match(true);
    }

    /// Match from the beginning of the input and record the first matching prefix.
    bool lookingAt()
    {
        return match(false);
    }

    /// Clear the match state while keeping the current input and compiled expression.
    Matcher reset() pure nothrow @nogc
    {
        matched = false;
        return this;
    }

    /// Replace the input and clear the match state. A null slice represents empty text (R26).
    Matcher reset(string input) pure nothrow @nogc
    {
        this.input = input;
        return reset();
    }

    private bool match(bool wholeInput)
    {
        matched = false;
        if (groupCount() && !capturePoints.length)
            capturePoints = new int[2 * (groupCount() + 1)];
        scope int[] result = capturePoints.length ? capturePoints : wholeMatch[];
        matched = compiled.program.captureMatch(input, result, wholeInput);
        return matched;
    }

    /// Whether the preceding match succeeded.
    bool hasMatch() const pure nothrow @nogc
    {
        return matched;
    }

    /// Capture a detached view of the current numbered match state.
    MatchResult toMatchResult() const pure nothrow
    {
        auto result = new NumberedMatch(matched ? input : null, groupCount());
        if (matched)
        {
            result.matched = true;
            result.wholeMatch = wholeMatch;
            if (capturePoints.length)
            {
                auto copy = new int[capturePoints.length];
                copy[] = capturePoints[];
                result.capturePoints = copy;
            }
        }
        return result;
    }
}

/// A malformed regular expression and the approximate position of the error.
class PatternSyntaxException : IllegalArgumentException
{
    private immutable Nullable!string description;
    private immutable Nullable!string expression;
    private immutable int index;

    /// Construct with present strings. An empty slice remains a present value.
    this(string description, string regex, int index)
    {
        this(Nullable!string(description), Nullable!string(regex), index);
    }

    /// Construct with nullable fields (R5).
    this(Nullable!string description, Nullable!string regex, int index)
    {
        super(syntaxMessage(description, regex, index));
        this.description = description;
        this.expression = regex;
        this.index = index;
    }

    Nullable!string getDescription() const pure nothrow @nogc
    {
        return description;
    }

    Nullable!string getPattern() const pure nothrow @nogc
    {
        return expression;
    }

    int getIndex() const pure nothrow @nogc
    {
        return index;
    }
}

private Regex compilePattern(string regex, int flags)
{
    try
        return compileRegex(regex, flags);
    catch (RegexSyntaxException failure)
        throw new PatternSyntaxException(failure.description, failure.pattern, cast(int) failure.index);
}

private string syntaxMessage(Nullable!string description, Nullable!string expression, int index)
{
    import flint.engine.aot.text : decimal, decodeUtf8;

    version (Windows)
        enum eol = "\r\n";
    else
        enum eol = "\n";

    const detail = description.isNull ? "null" : description.get;
    const pattern = expression.isNull ? "null" : expression.get;
    if (index < 0)
        return detail ~ eol ~ pattern;
    string message = detail ~ " near index " ~ decimal(index) ~ eol ~ pattern;
    if (expression.isNull)
        return message;

    size_t units;
    size_t cursor;
    while (cursor < pattern.length && units <= index)
        units += decodeUtf8(pattern, cursor) > wchar.max ? 2 : 1;
    if (units <= index)
        return message;

    auto indicator = new char[eol.length + cast(size_t) index + 1];
    indicator[0 .. eol.length] = eol;
    indicator[eol.length .. $ - 1] = ' ';
    indicator[$ - 1] = '^';
    cursor = 0;
    for (size_t indent = 0; indent < index;)
    {
        const codePoint = decodeUtf8(pattern, cursor);
        if (codePoint == '\t')
            indicator[eol.length + indent] = '\t';
        indent += codePoint > wchar.max ? 2 : 1;
    }
    message ~= indicator[];
    return message;
}
