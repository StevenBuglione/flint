/// Java SE 21 regular-expression compilation and whole-input matching.
module flint.java.util.regex.pattern;

import flint.java.lang : IllegalArgumentException, IllegalStateException, IndexOutOfBoundsException,
    NullPointerException;
import flint.java.util.function_ : Function, Predicate;
import flint.java.util.regex.internal.engine : Region, Regex, RegexFlag, RegexSyntaxException, compileRegex;
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

    /// A predicate that finds this expression in each input (R3, R26).
    Predicate!string asPredicate()
    {
        auto self = this;
        return Predicate!string.of((string input) => self.matcher(input).find());
    }

    /// A predicate that matches this expression against each whole input (R3, R26).
    Predicate!string asMatchPredicate()
    {
        auto self = this;
        return Predicate!string.of((string input) => self.matcher(input).matches());
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

    /// Quote literal text so it compiles as an expression that matches itself (R5, R26).
    static string quote(string text)
    {
        string result = "\\Q";
        size_t start;
        size_t at;
        while (at + 1 < text.length)
        {
            if (text[at] == '\\' && text[at + 1] == 'E')
            {
                result ~= text[start .. at] ~ "\\E\\\\E\\Q";
                at += 2;
                start = at;
            }
            else
                ++at;
        }
        return result ~ text[start .. $] ~ "\\E";
    }

    /// Split the input around matches, dropping trailing empty strings (R5, R26).
    string[] split(string input)
    {
        return split(input, 0);
    }

    /// Split the input with Java's positive, zero and negative limit rules (R5, R26).
    string[] split(string input, int limit)
    {
        return splitImpl(input, limit, false);
    }

    /// Split around matches, interleaving each matched delimiter, as Java SE 21 does (R5, R26).
    string[] splitWithDelimiters(string input, int limit)
    {
        return splitImpl(input, limit, true);
    }

    /// Java's shared split loop. The limit counts pieces, not list entries, so a delimited split
    /// yields at most `2 * limit - 1` entries exactly as Java's `splitWithDelimiters` does.
    private string[] splitImpl(string input, int limit, bool withDelimiters)
    {
        const text = input is null ? "" : input;
        const units = utf16Length(text);
        const limited = limit > 0;
        string[] pieces;
        int index;
        int chunks;
        auto matcher = matcher(text);
        while (matcher.find())
        {
            const first = matcher.start();
            if (!limited || chunks < limit - 1)
            {
                if (index == 0 && first == 0 && matcher.end() == 0)
                    continue; // Java drops the empty piece before a zero-width match at the start
                pieces ~= sliceUtf16(text, index, first);
                index = matcher.end();
                if (withDelimiters)
                    pieces ~= sliceUtf16(text, first, index);
                ++chunks;
            }
            else if (chunks == limit - 1)
            {
                pieces ~= sliceUtf16(text, index, units);
                index = matcher.end();
                ++chunks;
            }
        }
        if (index == 0)
            return [text];
        if (!limited || chunks < limit)
            pieces ~= sliceUtf16(text, index, units);
        if (limit == 0)
        {
            size_t keep = pieces.length;
            while (keep > 0 && pieces[keep - 1].length == 0)
                --keep;
            pieces.length = keep;
        }
        return pieces;
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
    private bool stale;
    private const(int[string]) groupNames;

    private struct Capture
    {
        int first, last;
    }

    private this(string input, int groups, const(int[string]) groupNames) pure nothrow @nogc
    {
        this.input = input;
        this.groups = groups;
        this.groupNames = groupNames;
    }

    /// Count the capturing groups defined by the pattern.
    override int groupCount() const pure nothrow @nogc
    {
        return groups;
    }

    /// The named-group table in effect. A live Matcher reads the current pattern's table.
    protected const(int[string]) nameView() const pure nothrow @nogc
    {
        return groupNames;
    }

    final override int start() const
    {
        return start(0);
    }

    final override int start(int group) const
    {
        return utf16Offset(capture(group).first);
    }

    final int start(string name) const
    {
        return start(matchedGroupIndex(name));
    }

    final override int end() const
    {
        return end(0);
    }

    final override int end(int group) const
    {
        return utf16Offset(capture(group).last);
    }

    final int end(string name) const
    {
        return end(matchedGroupIndex(name));
    }

    final override Nullable!string group() const
    {
        return group(0);
    }

    final override Nullable!string group(int index) const
    {
        if (stale && index == 0)
            return Nullable!string.init;
        const range = capture(index);
        if (range.first < 0)
            return Nullable!string.init;
        size_t at;
        advance(range.first, at);
        const first = at;
        advance(range.last - range.first, at);
        return Nullable!string(input[first .. at]);
    }

    final Nullable!string group(string name) const
    {
        return group(matchedGroupIndex(name));
    }

    /// Java's `getMatchedGroupIndex`: the match check comes before the name lookup.
    private int matchedGroupIndex(string name) const
    {
        if (!matched)
            throw new IllegalStateException("No match found");
        auto found = name in nameView();
        if (found is null)
            throw new IllegalArgumentException("No group with name <" ~ name ~ ">");
        return *found;
    }

    /// The capture pair for `start`/`end`. A stale whole-match after `usePattern` keeps Java's old `first`/`last`.
    private Capture capture(int group) const
    {
        if (!matched)
            throw new IllegalStateException("No match found");
        if (cast(uint) group > cast(uint) groupCount())
            throw new IndexOutOfBoundsException("Invalid capture group");
        if (!capturePoints.length || (group == 0 && capturePoints[0] < 0))
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
    private int searchFrom; // in Unicode code points
    private int regionStartUnit; // Java's region start, in UTF-16 units
    private int regionEndUnit; // Java's region end, in UTF-16 units
    private bool anchoringBounds = true;
    private bool transparentBounds;

    private this(Pattern compiled, string input)
    {
        super(input, compiled.program.groupCount(), compiled.program.nameTable());
        this.compiled = compiled;
        this.regionEndUnit = utf16Length(input);
    }

    /// The compiled expression associated with this matcher.
    Pattern pattern() pure nothrow @nogc
    {
        return compiled;
    }

    /// The capturing groups of the current pattern; `usePattern` can change them.
    override int groupCount() const pure nothrow @nogc
    {
        return compiled.program.groupCount();
    }

    /// The current pattern's named-group table.
    protected override const(int[string]) nameView() const pure nothrow @nogc
    {
        return compiled.program.nameTable();
    }

    /// Replace the compiled expression while keeping the input and search position, as Java SE 21 does (R3).
    Matcher usePattern(Pattern newPattern)
    {
        if (newPattern is null)
            throw new IllegalArgumentException("Pattern cannot be null");
        if (matched)
        {
            if (capturePoints.length)
            {
                wholeMatch[0] = capturePoints[0];
                wholeMatch[1] = capturePoints[1];
            }
            stale = true;
        }
        compiled = newPattern;
        const count = newPattern.program.groupCount();
        capturePoints = new int[2 * (count + 1 > 10 ? count + 1 : 10)];
        capturePoints[] = -1;
        return this;
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

    /// Find the next match at or after the current search position.
    bool find()
    {
        return findFrom(searchFrom);
    }

    /// Find the first match at or after the given UTF-16 offset, over the entire input (R3, R26).
    bool find(int start)
    {
        if (start < 0 || start > utf16Length(input))
            throw new IndexOutOfBoundsException("Illegal start index");
        reset();
        searchFrom = codePointIndex(input, start);
        return findFrom(searchFrom);
    }

    /// Set the region searched and matched by this matcher, in UTF-16 offsets (R3, R26).
    Matcher region(int start, int end)
    {
        const length = utf16Length(input);
        if (start < 0 || start > length)
            throw new IndexOutOfBoundsException("start");
        if (end < 0 || end > length)
            throw new IndexOutOfBoundsException("end");
        if (start > end)
            throw new IndexOutOfBoundsException("start > end");
        reset();
        regionStartUnit = start;
        regionEndUnit = end;
        return this;
    }

    /// The first UTF-16 offset of the region a match may use (R3).
    int regionStart() const pure nothrow @nogc
    {
        return regionStartUnit;
    }

    /// One past the last UTF-16 offset of the region a match may use (R3).
    int regionEnd() const pure nothrow @nogc
    {
        return regionEndUnit;
    }

    /// Whether look-around and boundaries may see outside the region (R3).
    bool hasTransparentBounds() const pure nothrow @nogc
    {
        return transparentBounds;
    }

    /// Set whether look-around and boundaries may see outside the region (R3).
    Matcher useTransparentBounds(bool value) pure nothrow @nogc
    {
        transparentBounds = value;
        return this;
    }

    /// Whether anchors treat the region boundaries as the input boundaries (R3).
    bool hasAnchoringBounds() const pure nothrow @nogc
    {
        return anchoringBounds;
    }

    /// Set whether anchors treat the region boundaries as the input boundaries (R3).
    Matcher useAnchoringBounds(bool value) pure nothrow @nogc
    {
        anchoringBounds = value;
        return this;
    }

    /// Replace every match with Java's replacement syntax: `$g`, `${name}` and `\` escapes (R5, R26).
    string replaceAll(string replacement)
    {
        reset();
        return replaceMatches(replacement, false);
    }

    /// Replace the first match with Java's replacement syntax (R5, R26).
    string replaceFirst(string replacement)
    {
        reset();
        return replaceMatches(replacement, true);
    }

    /// Replace every match with the text the replacer returns for the live MatchResult (R3, R26).
    string replaceAll(Function!(MatchResult, string) replacer)
    {
        return replaceFunctional(replacer, false);
    }

    /// Replace the first match with the text the replacer returns (R3, R26).
    string replaceFirst(Function!(MatchResult, string) replacer)
    {
        return replaceFunctional(replacer, true);
    }

    /// Quote literal text so it can be used as a replacement (R5, R26).
    static string quoteReplacement(string text)
    {
        string result;
        foreach (char c; text)
        {
            if (c == '\\' || c == '$')
                result ~= '\\';
            result ~= c;
        }
        return result;
    }

    /// Clear the match state while keeping the current input, expression and bounds policy (R3).
    Matcher reset() pure nothrow @nogc
    {
        matched = false;
        stale = false;
        searchFrom = 0;
        regionStartUnit = 0;
        regionEndUnit = utf16Length(input);
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
        stale = false;
        if (groupCount() && !capturePoints.length)
            capturePoints = new int[2 * (groupCount() + 1)];
        scope int[] result = capturePoints.length ? capturePoints[0 .. 2 * (groupCount() + 1)] : wholeMatch[];
        matched = compiled.program.captureMatch(input, engineRegion(), result, wholeInput);
        searchFrom = matched ? (result[1] == result[0] ? result[1] + 1 : result[1]) : 0;
        return matched;
    }

    private bool findFrom(int from)
    {
        matched = false;
        stale = false;
        if (groupCount() && !capturePoints.length)
            capturePoints = new int[2 * (groupCount() + 1)];
        scope int[] result = capturePoints.length ? capturePoints[0 .. 2 * (groupCount() + 1)] : wholeMatch[];
        matched = compiled.program.searchMatch(input, engineRegion(), from, result);
        searchFrom = matched ? (result[1] == result[0] ? result[1] + 1 : result[1]) : 0;
        return matched;
    }

    /// The stored UTF-16 region as the engine's code-point bounds and bounds policy.
    private Region engineRegion() const pure nothrow @nogc
    {
        import flint.java.util.regex.internal.engine : Region;

        Region region;
        region.from = codePointIndex(input, regionStartUnit);
        region.to = codePointIndex(input, regionEndUnit);
        region.anchoring = anchoringBounds;
        region.transparent = transparentBounds;
        return region;
    }

    private string replaceMatches(string replacement, bool firstOnly)
    {
        import flint.engine.aot.text : decodeUtf8;

        string output;
        size_t byteCursor;
        int unitCursor;
        bool any;
        while (find())
        {
            any = true;
            const matchStart = start();
            const segmentStart = byteCursor;
            while (unitCursor < matchStart)
                unitCursor += decodeUtf8(input, byteCursor) > wchar.max ? 2 : 1;
            output ~= input[segmentStart .. byteCursor];
            appendExpanded(output, replacement);
            const matchEnd = end();
            while (unitCursor < matchEnd)
                unitCursor += decodeUtf8(input, byteCursor) > wchar.max ? 2 : 1;
            if (firstOnly)
                break;
        }
        if (!any)
            return input;
        output ~= input[byteCursor .. $];
        return output;
    }

    /// Java's `replaceAll` and `replaceFirst` over a replacer function. The returned text is appended verbatim, and
    /// a null return raises the null-pointer exception Java's `appendReplacement` raises.
    private string replaceFunctional(Function!(MatchResult, string) replacer, bool firstOnly)
    {
        import flint.engine.aot.text : decodeUtf8;

        if (replacer is null)
            throw new NullPointerException();
        reset();
        if (!find())
            return input;
        string output;
        size_t byteCursor;
        int unitCursor;
        do
        {
            const matchStart = start();
            const segmentStart = byteCursor;
            while (unitCursor < matchStart)
                unitCursor += decodeUtf8(input, byteCursor) > wchar.max ? 2 : 1;
            output ~= input[segmentStart .. byteCursor];
            const replacement = replacer.apply(this);
            if (replacement is null)
                throw new NullPointerException();
            output ~= replacement;
            const matchEnd = end();
            while (unitCursor < matchEnd)
                unitCursor += decodeUtf8(input, byteCursor) > wchar.max ? 2 : 1;
            if (firstOnly)
                break;
        }
        while (find());
        output ~= input[byteCursor .. $];
        return output;
    }

    private void appendExpanded(ref string output, string replacement) const
    {
        size_t at;
        size_t literal = 0;
        while (at < replacement.length)
        {
            const c = replacement[at];
            if (c == '\\')
            {
                output ~= replacement[literal .. at];
                if (at + 1 >= replacement.length)
                    throw new IllegalArgumentException("character to be escaped is missing");
                const length = utf8SequenceLength(replacement, at + 1);
                output ~= replacement[at + 1 .. at + 1 + length];
                at += 1 + length;
                literal = at;
            }
            else if (c == '$')
            {
                output ~= replacement[literal .. at];
                at = appendGroupReference(output, replacement, at + 1);
                literal = at;
            }
            else
                ++at;
        }
        output ~= replacement[literal .. $];
    }

    private size_t appendGroupReference(ref string output, string replacement, size_t at) const
    {
        if (at >= replacement.length)
            throw new IllegalArgumentException("Illegal group reference: group index is missing");
        if (replacement[at] == '{')
            return appendNamedGroupReference(output, replacement, at);
        if (replacement[at] < '0' || replacement[at] > '9')
            throw new IllegalArgumentException("Illegal group reference");
        return appendNumberedGroupReference(output, replacement, at);
    }

    private size_t appendNamedGroupReference(ref string output, string replacement, size_t at) const
    {
        auto close = at + 1;
        while (close < replacement.length && replacement[close] != '}')
            ++close;
        if (close >= replacement.length)
            throw new IllegalArgumentException("named capturing group is missing trailing '}'");
        const name = replacement[at + 1 .. close];
        if (name.length == 0)
            throw new IllegalArgumentException("named capturing group has 0 length name");
        auto found = name in nameView();
        if (found is null)
            throw new IllegalArgumentException("No group with name {" ~ name ~ "}");
        appendGroup(output, *found);
        return close + 1;
    }

    private size_t appendNumberedGroupReference(ref string output, string replacement, size_t at) const
    {
        int group = replacement[at] - '0';
        auto next = at + 1;
        while (next < replacement.length && replacement[next] >= '0' && replacement[next] <= '9')
        {
            const candidate = group * 10 + (replacement[next] - '0');
            if (group > (int.max - 9) / 10 || candidate > groupCount())
                break;
            group = candidate;
            ++next;
        }
        if (group > groupCount())
        {
            import flint.engine.aot.text : decimal;

            throw new IndexOutOfBoundsException("No group " ~ decimal(cast(long) group));
        }
        appendGroup(output, group);
        return next;
    }

    private void appendGroup(ref string output, int group) const
    {
        const text = this.group(group);
        if (!text.isNull)
            output ~= text.get;
    }

    /// Whether the preceding match succeeded.
    bool hasMatch() const pure nothrow @nogc
    {
        return matched;
    }

    /// Capture a detached view of the current numbered match state.
    MatchResult toMatchResult() const pure nothrow
    {
        auto result = new NumberedMatch(matched ? input : null, groupCount(), nameView());
        if (matched)
        {
            result.matched = true;
            result.stale = stale;
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

/// The number of bytes in the UTF-8 sequence that starts at `at`.
private size_t utf8SequenceLength(scope const(char)[] text, size_t at) pure nothrow @nogc
{
    const lead = cast(ubyte) text[at];
    const length = lead >= 0xF0 ? 4 : lead >= 0xE0 ? 3 : lead >= 0xC0 ? 2 : 1;
    const remaining = text.length - at;
    return length < remaining ? length : remaining;
}

/// The number of UTF-16 code units in UTF-8 `text`, matching Java's `String.length`.
private int utf16Length(scope const(char)[] text) pure nothrow @nogc
{
    import flint.engine.aot.text : decodeUtf8;

    size_t at;
    int units;
    while (at < text.length)
        units += decodeUtf8(text, at) > wchar.max ? 2 : 1;
    return units;
}

/// The code point index whose UTF-16 prefix reaches `unit`, rounding a mid-pair offset down.
private int codePointIndex(scope const(char)[] text, int unit) pure nothrow @nogc
{
    import flint.engine.aot.text : decodeUtf8;

    size_t at;
    int units, points;
    while (at < text.length && units < unit)
    {
        units += decodeUtf8(text, at) > wchar.max ? 2 : 1;
        ++points;
    }
    return points;
}

/// The byte offset of the code point that contains UTF-16 offset `unit`.
private size_t byteOffset(scope const(char)[] text, int unit) pure nothrow @nogc
{
    import flint.engine.aot.text : decodeUtf8;

    size_t at;
    int units;
    while (at < text.length && units < unit)
        units += decodeUtf8(text, at) > wchar.max ? 2 : 1;
    return at;
}

/// A UTF-8 slice between two UTF-16 offsets drawn from match boundaries.
private string sliceUtf16(string text, int fromUnit, int toUnit) pure nothrow @nogc
{
    return text[byteOffset(text, fromUnit) .. byteOffset(text, toUnit)];
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
