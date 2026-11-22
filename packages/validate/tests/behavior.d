module validate_behavior;

import flint.arena : RequestArena, Status, Text;
import flint.validate : Email, Max, Min, NotBlank, Pattern, Size, Valid, Violation, validate, validateIn;

@safe:

private struct Caption
{
    @NotBlank string value;
}

private struct Widths
{
    @Size(2, 2) string label;
    @Size(2, 2) ubyte[] raw;
}

@("UTF-8 whitespace and scalar counts")
unittest
{
    enum white = "\t\n\v\f\r \u0085\u00A0\u1680\u2000\u2001\u2002\u2003\u2004\u2005"
        ~ "\u2006\u2007\u2008\u2009\u200A\u2028\u2029\u202F\u205F\u3000";
    static immutable malformed = [
        "", white, "  \n ", "A\x80", "\xC0\x80", "\xE2\x82", "\xED\xA0\x80", "\xF4\x90\x80\x80"
    ];
    foreach (sample; malformed)
    {
        const value = Caption(sample);
        assert(!validate(value, []).valid);
    }
    foreach (sample; [" x ", "é", "🐈", "\u200B", "\0"])
    {
        const value = Caption(sample);
        assert(validate(value, []).valid);
    }

    ubyte[2] raw = [0xFF, 0xFF];
    Widths widths = Widths("猫é", raw[]);
    assert(validate(widths, []).valid);
    widths.label = "\xFF\xFF";
    assert(validate(widths, []).total == 1);
    widths.label = "café";
    widths.raw = raw[0 .. 1];
    assert(validate(widths, []).total == 2);
}

private struct Numeric
{
    @Min(long.min) @Max(long.min) long signedMinimum;
    @Min(-1) ulong unsignedValue;
    @Max(long.max) ulong cappedUnsigned;
    @Min(16_777_217) float roundedBound;
    @Max(long.max) double upperFloat;
    @Min(0) @Max(0) double fractional;
}

@("numeric comparisons avoid sign overflow and rounded long endpoints")
unittest
{
    Numeric values = Numeric(long.min, ulong.max, long.max, 16_777_218.0f, 0x1.fffffffffffffp62, -0.0);
    Violation[8] violations;
    assert(validate(values, violations[]).valid);
    values.signedMinimum = long.min + 1;
    values.cappedUnsigned = ulong.max;
    values.roundedBound = 16_777_216.0f;
    values.upperFloat = 0x1p63;
    values.fractional = -0.125;
    const report = validate(values, violations[]);
    assert(report.total == 5 && report.written == 5);
    assert(violations[0].constraint == "Max");
    assert(violations[2].field == "roundedBound");
    assert(violations[3].field == "upperFloat");
    assert(violations[4].constraint == "Min");

    foreach (nanOrInfinity; [double.nan, double.infinity, -double.infinity])
    {
        Numeric unusual = Numeric(long.min, 0, 0, 16_777_218.0f, -0x1p63, nanOrInfinity);
        assert(validate(unusual, []).total == 2);
    }
}

private struct Mailbox
{
    @Email string address;
}

private string repeated(char byteValue, size_t count)
{
    char[] value = new char[count];
    value[] = byteValue;
    return value.idup;
}

@("ASCII addr-spec boundaries and malformed mailboxes")
unittest
{
    const local = repeated('x', 64);
    const label = repeated('d', 63);
    const domain = label ~ "." ~ label ~ "." ~ repeated('e', 61);
    assert(local.length + 1 + domain.length == 254);
    foreach (address; [
        "local@domain", "firstname.lastname+tag@example.com", local ~ "@" ~ domain,
        "~!*@a-b.example", "A9@example.test"
    ])
    {
        const mailbox = Mailbox(address);
        assert(validate(mailbox, []).valid, address);
    }
    foreach (address; [
        "x" ~ local ~ "@x.co", "x@" ~ label ~ "a.org", local ~ "@" ~ domain ~ "a", ".u@x.io",
        "u.@x.io", "u..v@x.io", "@x.io", "a@@x.io", "a@", "a@.io", "a@x..io", "a@x.io.", "a@-x.io",
        "a@x-.io", "a@x_.io", "\"a\"@x.io", "a b@x.io", "ä@x.io", "a@é.io", "a@x\0.io",
        repeated('x', 16_384) ~ "@x.io"
    ])
    {
        const mailbox = Mailbox(address);
        assert(!validate(mailbox, []).valid);
    }
}

private bool matches(string expression)(string value) nothrow @nogc
{
    static struct Sample
    {
        @Pattern(expression) string subject;
    }

    const dto = Sample(value);
    return validate(dto, []).valid;
}

@("full Thompson matching with ASCII syntax and UTF-8 scalar input")
unittest
{
    assert(matches!r"^(ab|cd){2,3}[0-9]?[^a-z]+$"("abcd7-🐈"));
    assert(!matches!r"^(ab|cd){2,3}[0-9]?[^a-z]+$"("ab7-"));
    assert(!matches!r"^(ab|cd){2,3}[0-9]?[^a-z]+$"("abcd7a"));
    assert(matches!r"a{2,}"("aaaa"));
    assert(!matches!r"a{2,}"("a"));
    assert(matches!r"a{0}b{2}"("bb"));
    assert(matches!r"(z*|a?)+"(""));
    assert(matches!r"^(\[|\])\d\w\s\x2b$"("[8_ +"));
    assert(matches!r"[^a-c-][\]]+"("é]]"));
    assert(matches!r"^.$"("🐈"));
    assert(!matches!r"^.$"("\n"));
    assert(!matches!r"^.$"("\xFF"));
    assert(!matches!"yes"("say yes"));
    assert(matches!".*yes.*"("say yes"));
    assert(matches!""(""));
    assert(!matches!""("x"));
}

@("256 states and adversarial input stay bounded")
unittest
{
    assert(matches!"a{255}"(repeated('a', 255)));
    assert(!matches!"a{255}"(repeated('a', 254)));
    char[16_385] input;
    input[] = 'a';
    assert(!matches!r"(a+)+b"(input[0 .. 16_384].idup));
    input[16_383] = 'b';
    assert(matches!r"(a+)+b"(input[0 .. 16_384].idup));
    assert(!matches!r"(a+)+b"(input[].idup));
}

private struct Entry
{
    @("unrelated") @NotBlank @Size(2, 3) string display;
    @Min(1) int score;
}

private struct Form
{
    @Size(3, 4) @Valid Entry[][] groups;
    @Valid Entry single;
}

@("violations follow declaration order, annotation order, and nested indexes")
unittest
{
    Entry[] rows = [Entry("", 0), Entry("ok", 1)];
    Entry[][] groups = [rows[], rows[1 .. $]];
    Form form = Form(groups[], Entry(" ", 2));
    const counted = validate(form, []);
    assert(!counted.valid && counted.total == 6 && counted.written == 0);
    Violation[8] errors;
    const truncated = validate(form, errors[0 .. 1]);
    assert(!truncated.valid && truncated.total == 6 && truncated.written == 1);
    assert(errors[0].constraint == "Size" && errors[0].field == "groups" && errors[0].indexCount == 0);

    const written = validate(form, errors[]);
    assert(written.written == 6 && written.total == 6);
    assert(errors[1].field == "groups[][].display" && errors[1].constraint == "NotBlank");
    assert(errors[2].field == "groups[][].display" && errors[2].constraint == "Size");
    assert(errors[3].field == "groups[][].score" && errors[3].constraint == "Min");
    assert(errors[3].indexCount == 2 && errors[3].indexes[0 .. 2] == [0, 0]);
    assert(errors[4].field == "single.display" && errors[4].indexCount == 0);
    assert(errors[5].field == "single.display" && errors[5].indexCount == 0);
}

private struct Bulk
{
    @Valid Caption[] entries;
}

@("the 4097 sentinel leaves output beyond the 4096th violation intact")
unittest
{
    auto values = new Caption[4097];
    auto errors = new Violation[4097];
    errors[4096].field = "guard";
    Bulk dto = Bulk(values[0 .. 4096]);
    assert(validate(dto, errors[]).total == 4096);
    dto.entries = values[];
    const overflow = validate(dto, errors[]);
    assert(!overflow.valid && overflow.total == 4097 && overflow.written == 4096);
    assert(errors[4095].indexes[0] == 4095);
    assert(errors[4096].field == "guard");
}

private struct ArenaCaption
{
    @Size(2, 2) @NotBlank @Pattern("..") Text name;
}

@("Text handles require the current owning arena and use the same UTF-8 rules")
unittest
{
    ubyte[24] backing;
    ubyte[24] others;
    scope owns = RequestArena(backing[]);
    scope foreign = RequestArena(others[]);
    const handle = owns.copyIn(cast(const(ubyte)[]) "é🐈");
    assert(handle.ok());

    ArenaCaption dto = ArenaCaption(Text(handle.value));
    Violation[3] errors;
    assert(validateIn(dto, owns, errors[]).valid);
    assert(validate(dto, errors[]).total == 3);
    assert(validateIn(dto, foreign, errors[]).total == 3);
    assert(owns.reset() == Status.ok);
    assert(validateIn(dto, owns, errors[]).total == 3);
    assert(errors[0].message == "invalid or unavailable arena text handle");
}

private enum CanValidate(T) = __traits(compiles, () @safe nothrow @nogc { T dto; validate(dto, []); });

private struct BadBlank
{
    @NotBlank uint count;
}

private struct BadMin
{
    @Min(0) Caption label;
}

private struct BadInterval
{
    @Min(9) @Max(5) int index;
}

private struct BadSize
{
    @Size(5, 10) @Size(1, 4) string label;
}

private struct BadBytes
{
    @Pattern("a") ubyte[] bytes;
}

private struct Recursive
{
    @Valid Recursive[] children;
}

private struct TooManyIndexes
{
    @Valid Caption[][][][][][][][][] content;
}

private struct BadPattern(string expression)
{
    @Pattern(expression) string content;
}

static assert(CanValidate!ArenaCaption);
static assert(CanValidate!Form);
static assert(!CanValidate!BadBlank);
static assert(!CanValidate!BadMin);
static assert(!CanValidate!BadInterval);
static assert(!CanValidate!BadSize);
static assert(!CanValidate!BadBytes);
static assert(!CanValidate!Recursive);
static assert(!CanValidate!TooManyIndexes);
static assert(!CanValidate!(BadPattern!r"(a)\1"));
static assert(!CanValidate!(BadPattern!r"(?=a)"));
static assert(!CanValidate!(BadPattern!r"(?<!a)"));
static assert(!CanValidate!(BadPattern!r"\p{L}"));
static assert(!CanValidate!(BadPattern!r"a{256}"));
static assert(!CanValidate!(BadPattern!r"a{3,2}"));
static assert(!CanValidate!(BadPattern!r"a**"));
static assert(!CanValidate!(BadPattern!r"[z-a]"));

private struct MissingMinimum
{
    @Min int count;
}

private struct NestedDepth(size_t depth)
{
    static if (depth == 0)
    {
        @NotBlank string label;
    }
    else
    {
        @Valid NestedDepth!(depth - 1) child;
    }
}

static assert(!CanValidate!MissingMinimum);
static assert(CanValidate!(NestedDepth!63));
static assert(!CanValidate!(NestedDepth!64));

private struct WideWidths
{
    @Size(2, 2) wstring utf16;
    @Size(2, 2) dstring utf32;
    @Size(2, 2) const(wchar)[] mutable16;
}

@("Size counts scalars in UTF-16 and UTF-32 strings and rejects invalid code units")
unittest
{
    wchar[2] loneHigh = [cast(wchar) 0xD83D, 'a'];
    wchar[2] loneLow = ['a', cast(wchar) 0xDC08];
    dchar[2] surrogate = ['a', cast(dchar) 0xD800];
    dchar[2] beyond = ['a', cast(dchar) 0x11_0000];

    WideWidths widths = WideWidths("🐈é"w, "🐈é"d, "猫🐈"w);
    Violation[3] errors;
    assert(validate(widths, errors[]).valid);

    widths.utf16 = "🐈"w;
    widths.utf32 = "🐈"d;
    widths.mutable16 = "abc"w;
    const counted = validate(widths, errors[]);
    assert(counted.total == 3 && errors[0].field == "utf16" && errors[2].field == "mutable16");

    widths = WideWidths(loneHigh.idup, surrogate.idup, loneLow[]);
    assert(validate(widths, errors[]).total == 3);
    widths.utf32 = beyond.idup;
    widths.mutable16 = loneHigh[0 .. 1];
    assert(validate(widths, errors[]).total == 3);
}

private struct NarrowNumeric
{
    @Min(int.min) @Max(int.min) int signedInt;
    @Min(short.min) short signedShort;
    @Max(ubyte.max) ubyte unsignedByte;
    @Min(uint.max) uint unsignedInt;
    @Max(0) float single;
    @Min(0) real extended;
}

@("narrow signed minima, unsigned maxima and nonfinite float and real values")
unittest
{
    NarrowNumeric values = NarrowNumeric(int.min, short.min, ubyte.max, uint.max, -1.0f, 0.0L);
    Violation[6] errors;
    assert(validate(values, errors[]).valid);
    values.signedInt = int.min + 1;
    const report = validate(values, errors[]);
    assert(report.total == 1 && errors[0].field == "signedInt" && errors[0].constraint == "Max");

    values.signedInt = int.min;
    values.unsignedInt = uint.max - 1;
    assert(validate(values, errors[]).total == 1 && errors[0].field == "unsignedInt");
    values.unsignedInt = uint.max;

    foreach (index; 0 .. 3)
    {
        values.single = [float.nan, float.infinity, -float.infinity][index];
        values.extended = [real.nan, real.infinity, -real.infinity][index];
        const nonfinite = validate(values, errors[]);
        assert(nonfinite.total == 2 && errors[0].field == "single" && errors[1].field == "extended");
    }
}

private bool referenceAlphanumeric(ubyte ch)
{
    return (ch >= '0' && ch <= '9') || ((ch | 0x20) >= 'a' && (ch | 0x20) <= 'z');
}

/// Independent model of the documented dot-atom local part: nonempty atoms of atext.
private bool referenceLocal(scope const(ubyte)[] local)
{
    import std.algorithm.searching : canFind;
    import std.array : split;

    enum atext = cast(immutable(ubyte)[]) "!#$%&'*+-/=?^_`{|}~";
    if (local.length == 0 || local.length > 64)
        return false;
    foreach (atom; local.split('.'))
    {
        if (atom.length == 0)
            return false;
        foreach (ch; atom)
        {
            if (!referenceAlphanumeric(ch) && !atext.canFind(ch))
                return false;
        }
    }
    return true;
}

/// Independent model of the documented domain: nonempty labels of at most 63 letters, digits or inner hyphens.
private bool referenceDomain(scope const(ubyte)[] domain)
{
    import std.array : split;

    if (domain.length == 0)
        return false;
    foreach (label; domain.split('.'))
    {
        if (label.length == 0 || label.length > 63 || label[0] == '-' || label[$ - 1] == '-')
            return false;
        foreach (ch; label)
        {
            if (!referenceAlphanumeric(ch) && ch != '-')
                return false;
        }
    }
    return true;
}

/// Independent model of the documented pragmatic ASCII addr-spec grammar.
private bool referenceEmail(scope const(ubyte)[] input)
{
    import std.algorithm.searching : count, countUntil;

    if (input.length > 254 || input.count('@') != 1)
        return false;
    immutable at = input.countUntil('@');
    return referenceLocal(input[0 .. at]) && referenceDomain(input[at + 1 .. $]);
}

@("seeded mailbox fuzz agrees with the addr-spec model and never accepts beyond the bounds")
unittest
{
    static immutable ubyte[] alphabet = cast(immutable(ubyte)[]) "aZ09.-@_+~\"\\ (\x00\xC3\xA9\x7F";
    uint random = 0x5eed_e3a1;
    uint next()
    {
        random ^= random << 13;
        random ^= random >>> 17;
        random ^= random << 5;
        return random;
    }

    ubyte[320] scratch;
    size_t accepted;
    foreach (round; 0 .. 20_000)
    {
        size_t length;
        if (round % 2 == 0)
        {
            // Structured candidates exercise the 64/63/254 limits and label punctuation.
            immutable localLength = next() % 70;
            foreach (_; 0 .. localLength)
                scratch[length++] = (next() % 9 == 0) ? '.' : cast(ubyte)('a' + next() % 26);
            scratch[length++] = '@';
            immutable labels = 1 + next() % 5;
            foreach (labelIndex; 0 .. labels)
            {
                if (labelIndex != 0)
                    scratch[length++] = '.';
                immutable labelLength = next() % 68;
                foreach (_; 0 .. labelLength)
                {
                    if (length == scratch.length)
                        break;
                    scratch[length++] = (next() % 11 == 0) ? '-' : cast(ubyte)('0' + next() % 10);
                }
            }
        }
        else
        {
            length = next() % 300;
            foreach (index; 0 .. length)
                scratch[index] = alphabet[next() % alphabet.length];
        }

        const candidate = scratch[0 .. length];
        const mailbox = Mailbox(cast(string) candidate.idup);
        immutable verdict = validate(mailbox, []).valid;
        assert(verdict == referenceEmail(candidate), cast(string) candidate.idup);
        if (verdict)
        {
            ++accepted;
            assert(candidate.length <= 254);
        }
    }
    assert(accepted > 1_000 && accepted < 10_000);
}

private struct Budgeted
{
    @Pattern(r"(a{15}){17}") string exact;
    @Pattern(r"((a|b)+)*c") string nested;
    @Pattern(r"(a*)*(a|aa)*b") string ambiguous;
}

@("nested quantifiers stay within the state budget and linear on adversarial input")
unittest
{
    Budgeted dto = Budgeted(repeated('a', 255), "ababbac", "aaab");
    assert(validate(dto, []).valid);
    dto.exact = repeated('a', 254);
    dto.nested = repeated('a', 16_383) ~ "c";
    dto.ambiguous = repeated('a', 16_383) ~ "b";
    Violation[3] errors;
    const report = validate(dto, errors[]);
    assert(report.total == 1 && errors[0].field == "exact");

    dto.exact = repeated('a', 255);
    dto.nested = repeated('a', 16_384);
    dto.ambiguous = repeated('a', 16_384) ~ "b";
    const adversarial = validate(dto, errors[]);
    assert(adversarial.total == 2 && errors[0].field == "nested" && errors[1].field == "ambiguous");
}

static assert(!CanValidate!(BadPattern!r"(a{16}){16}"));
static assert(!CanValidate!(BadPattern!r"((a{4}){4}){17}"));
static assert(!CanValidate!(BadPattern!r"(?:a)"));
static assert(!CanValidate!(BadPattern!r"\k<name>"));

private struct Pair
{
    @NotBlank string left;
    @Min(1) int right;
}

@("one-slot and exactly-sized outputs report written and total separately")
unittest
{
    Pair[3] rows = [Pair("", 0), Pair("x", 1), Pair(" ", 1)];
    static struct Rows
    {
        @Valid Pair[] rows;
    }

    const dto = Rows(rows[]);
    Violation[3] errors;
    errors[1].field = "untouched";
    const single = validate(dto, errors[0 .. 1]);
    assert(single.written == 1 && single.total == 3 && !single.valid);
    assert(errors[0].field == "rows[].left" && errors[0].indexes[0] == 0);
    assert(errors[1].field == "untouched");

    const exact = validate(dto, errors[]);
    assert(exact.written == 3 && exact.total == 3);
    assert(errors[1].field == "rows[].right" && errors[1].indexes[0] == 0);
    assert(errors[2].field == "rows[].left" && errors[2].indexes[0] == 2 && errors[2].indexCount == 1);
    foreach (attempt; 0 .. 3)
    {
        Violation[3] again;
        assert(validate(dto, again[]) == exact && again == errors);
    }
}

private struct ArenaRow
{
    @NotBlank Text label;
}

private struct ArenaTable
{
    @Valid ArenaRow[][] rows;
}

@("default, stale and foreign Text handles inside nested arrays fail without dereference")
unittest
{
    ubyte[16] backing;
    ubyte[16] otherBacking;
    scope arena = RequestArena(backing[]);
    scope other = RequestArena(otherBacking[]);
    const label = arena.copyIn(cast(const(ubyte)[]) "ok");
    const foreignLabel = other.copyIn(cast(const(ubyte)[]) "ok");
    assert(label.ok() && foreignLabel.ok());

    ArenaRow[][] outer = [
        [ArenaRow(Text(label.value)), ArenaRow(Text.init)], [ArenaRow(Text(foreignLabel.value))]
    ];
    const table = ArenaTable(outer);
    Violation[4] errors;
    const report = validateIn(table, arena, errors[]);
    assert(report.total == 2 && report.written == 2);
    assert(errors[0].field == "rows[][].label" && errors[0].indexes[0 .. 2] == [0, 1]);
    assert(errors[1].indexes[0 .. 2] == [1, 0] && errors[1].indexCount == 2);
    assert(errors[0].message == "invalid or unavailable arena text handle");

    assert(arena.reset() == Status.ok);
    assert(validateIn(table, arena, errors[]).total == 3);
    assert(validateIn(table, other, errors[]).total == 2);
}
