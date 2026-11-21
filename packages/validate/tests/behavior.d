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
