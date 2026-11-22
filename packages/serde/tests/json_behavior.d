/// Acceptance checks against the live JSON encoder and decoder.
module json_behavior;

import flint.arena : Buffer, RequestArena, Status, Text;
import flint.serde : DecodeOptions, EncodeOptions, JsonDefault, JsonFlatten, JsonIgnore, JsonName,
    JsonRequired, UnknownFields, decodeInto, encodeJson;

@safe:

private enum Kind
{
    primary,
    secondary
}

private struct Nested
{
    @JsonName("a")
    int first;
    Kind kind;
}

private struct Record
{
    @JsonRequired @JsonName("display")
    Text name;
    int[2] sample;
    @JsonFlatten Nested nested;
    @JsonDefault("42")
    ubyte count;
    @JsonIgnore uint ignored;
}

private bool equal(ref scope RequestArena arena, Buffer buffer, scope const(char)[] expected) nothrow @nogc
{
    bool same;
    const status = arena.read(buffer, (scope const(ubyte)[] contents) @safe nothrow @nogc {
        if (contents.length != expected.length)
            return;
        foreach (index, byteValue; contents)
        {
            if (byteValue != expected[index])
                return;
        }
        same = true;
    });
    return status == Status.ok && same;
}

@("JSON serializes renames, flattening, enums, fixed arrays, escaped NUL and surrogate pairs")
unittest
{
    ubyte[2048] storage;
    scope arena = RequestArena(storage[]);
    Record record;
    const input = `{"display":"h\u0000\ud83d\ude00","a":-42,"kind":"secondary","sample":[-2147483648,2147483647]}`;
    assert(decodeInto(cast(const(ubyte)[]) input, record, arena).code == Status.ok);
    assert(record.nested.first == -42);
    assert(record.nested.kind == Kind.secondary);
    assert(record.count == 42);
    assert(record.sample[0] == int.min && record.sample[1] == int.max);
    assert(equal(arena, record.name.bytes, "h\0😀"));

    auto encoded = encodeJson(record, arena, EncodeOptions(true));
    assert(encoded.ok());
    assert(equal(arena, encoded.value,
            `{"a":-42,"count":42,"display":"h\u0000😀","kind":"secondary","sample":[-2147483648,2147483647]}`));

    auto allFields = encodeJson(record, arena, EncodeOptions(true, false));
    assert(allFields.ok());
    assert(equal(arena, allFields.value, `{"a":-42,"count":42,"display":"h\u0000😀","ignored":0,`
            ~ `"kind":"secondary","sample":[-2147483648,2147483647]}`));
}

@("JSON parse, duplicate and required errors leave the arena and destination intact")
unittest
{
    ubyte[2048] storage;
    scope arena = RequestArena(storage[]);
    Record record;
    record.count = 77;
    record.name.bytes = arena.copyIn(cast(const(ubyte)[]) "old").value;
    const used = arena.stats().used;
    immutable inputs = [
        `{"display":"new","ignored":{"broken":[] ,}}}`, `{"display":"new","\u0064isplay":"x"}`,
        `{"display":"new","sample":[1,2e4]}`, `{"display":"new","sample":[1,2,3]}`,
        `{"display":"new","count":256}`, `{"display":"new","a":-2147483649}`,
        `{"display":"new","kind":"typo"}`, `{"display":"new"} other`, `{"display":"\uD800"}`,
        `{"display":"\uDC00"}`, `{"a":7}`, `{"display":"` ~ "\xC0\x80" ~ `"}`,
        `{"display":"` ~ "\xED\xA0\x80" ~ `"}`, `{"display":"` ~ "\xF4\x90\x80\x80" ~ `"}`,
        `{"display":"` ~ "\0" ~ `"}`,
    ];
    foreach (input; inputs)
    {
        const error = decodeInto(cast(const(ubyte)[]) input, record, arena);
        assert(error.code == Status.invalidArgument, input);
        assert(error.offset <= input.length);
        assert(arena.stats().used == used);
        assert(record.count == 77);
        assert(equal(arena, record.name.bytes, "old"));
    }
}

@("JSON arena preflight exhausts atomically with multiple variable fields")
unittest
{
    static struct Pair
    {
        Text first;
        Text second;
    }

    ubyte[8] storage;
    scope arena = RequestArena(storage[]);
    auto prior = arena.copyIn(cast(const(ubyte)[]) "abc");
    assert(prior.ok());
    const used = arena.stats().used;
    Pair pair = Pair(Text(prior.value), Text(prior.value));
    const input = `{"first":"1234","second":"56"}`;
    assert(decodeInto(cast(const(ubyte)[]) input, pair, arena).code == Status.outOfMemory);
    assert(arena.stats().used == used);
    assert(equal(arena, pair.first.bytes, "abc"));
    assert(equal(arena, pair.second.bytes, "abc"));
}

@("unknown JSON objects enforce duplicate and structural checks before skipping")
unittest
{
    static struct Value
    {
        ulong count;
    }

    ubyte[32] storage;
    scope arena = RequestArena(storage[]);
    Value value;
    auto options = DecodeOptions.init;
    options.unknownFields = UnknownFields.ignore;
    const duplicated = `{"count":1,"ignored":[{"a":null,"\u0061":false}]}`;
    assert(decodeInto(cast(const(ubyte)[]) duplicated, value, arena, options).code == Status.invalidArgument);
    const trailing = `{"count":1,"ignored":[1,]}`;
    assert(decodeInto(cast(const(ubyte)[]) trailing, value, arena, options).code == Status.invalidArgument);
    const valid = `{"count":18446744073709551615,"ignored":[{"a":[true,false,null]}]}`;
    assert(decodeInto(cast(const(ubyte)[]) valid, value, arena, options).code == Status.ok);
    assert(value.count == ulong.max);

    options.rejectDuplicateKeys = false;
    assert(decodeInto(cast(const(ubyte)[]) duplicated, value, arena, options).code == Status.ok);
    const repeated = `{"count":8,"count":9}`;
    assert(decodeInto(cast(const(ubyte)[]) repeated, value, arena, options).code == Status.ok);
    assert(value.count == 9);
    const overflow = `{"count":18446744073709551616}`;
    assert(decodeInto(cast(const(ubyte)[]) overflow, value, arena, options).code == Status.invalidArgument);
    assert(value.count == 9);
}

@("JSON depth, member and byte limits are checked for unknown values")
unittest
{
    struct Node
    {
        int known;
    }

    ubyte[32] storage;
    scope arena = RequestArena(storage[]);
    auto options = DecodeOptions.init;
    options.unknownFields = UnknownFields.ignore;
    Node target;
    char[143] input;
    input[0 .. 5] = `{"u":`;
    input[5 .. 69] = '[';
    input[69] = '0';
    input[70 .. 134] = ']';
    input[134] = '}';
    assert(decodeInto(cast(const(ubyte)[]) input[0 .. 135], target, arena, options).code == Status.resourceExhausted);
    input[5] = ' ';
    input[133] = ' ';
    assert(decodeInto(cast(const(ubyte)[]) input[0 .. 135], target, arena, options).code == Status.ok);

    const shortInput = `{"u":[1,2],"known":1}`;
    options.maxMembers = 1;
    assert(decodeInto(cast(const(ubyte)[]) shortInput, target, arena, options).code == Status.resourceExhausted);
    options.maxBytes = 4;
    assert(decodeInto(cast(const(ubyte)[]) shortInput, target, arena, options).offset == 4);
}

@("JSON stale handle and invalid UTF-8 output fail before allocating")
unittest
{
    ubyte[128] storage;
    scope arena = RequestArena(storage[]);
    auto handle = arena.copyIn(cast(const(ubyte)[]) "stale");
    assert(handle.ok());
    assert(arena.reset() == Status.ok);
    auto text = Text(handle.value);
    assert(encodeJson(text, arena).error.code == Status.invalidArgument);
    assert(arena.stats().used == 0);
    string invalid = "\xFF";
    assert(encodeJson(invalid, arena).error.code == Status.invalidArgument);
    assert(arena.stats().used == 0);
}

@("seeded byte mutations never corrupt JSON destination or prior allocations")
unittest
{
    ubyte[512] backward;
    scope arena = RequestArena(backward[]);
    auto preserved = arena.copyIn(cast(const(ubyte)[]) "preserved");
    assert(preserved.ok());

    enum input = `{"display":"hola","a":123,"kind":"primary","sample":[0,1]}`;
    uint state = 0xbf86_af81;
    foreach (iteration; 0 .. 1536)
    {
        ubyte[input.length] bytes;
        bytes[] = cast(const(ubyte)[]) input;
        state ^= state << 13;
        state ^= state >>> 17;
        state ^= state << 5;
        bytes[state % bytes.length] = cast(ubyte)(state >> 16);

        ubyte[256] temporary;
        scope decodeArena = RequestArena(temporary[]);
        Record value;
        value.count = 77;
        const failure = decodeInto(bytes[], value, decodeArena);
        if (failure.code != Status.ok)
        {
            assert(value.count == 77);
            assert(decodeArena.stats().used == 0);
        }
        else
        {
            auto output = encodeJson(value, decodeArena);
            assert(output.ok());
            const reread = decodeArena.read(output.value, (scope const(ubyte)[] roundtrip) @safe nothrow @nogc {
                Record copy;
                const decoded = decodeInto(roundtrip, copy, decodeArena);
                assert(decoded.code == Status.ok && copy.count == value.count && copy.nested.first == value
                    .nested.first);
            });
            assert(reread == Status.ok);
        }
        assert(equal(arena, preserved.value, "preserved"));
    }
}

private union FloatView
{
    ulong raw;
    double number;
}

@("JSON decimal conversion rounds midpoint ties and preserves signed zero")
unittest
{
    ubyte[4096] backing;
    scope arena = RequestArena(backing[]);
    double number;
    immutable representable = [
        "0", "-0", "0.1", "1.25", "1e308", "1.7976931348623157e308", "2.2250738585072014e-308",
        "4.9406564584124654e-324", "1e-100000000",
        "1.00000000000000011102230246251565404236316680908203125",
        "1.0000000000000001110223024625156540423631668090820312500001",
    ];
    immutable ulong[] wanted = [
        0, 0x8000_0000_0000_0000, 0x3fb9_9999_9999_999a, 0x3ff4_0000_0000_0000, 0x7fe1_ccf3_85eb_c8a0,
        0x7fef_ffff_ffff_ffff, 0x0010_0000_0000_0000, 1, 0, 0x3ff0_0000_0000_0000,
        0x3ff0_0000_0000_0001,
    ];
    foreach (index, input; representable)
    {
        assert(decodeInto(cast(const(ubyte)[]) input, number, arena).code == Status.ok, input);
        FloatView actual;
        actual.number = number;
        assert(actual.raw == wanted[index], input);
    }
    foreach (bad; ["1e309", "1.7976931348623159e308", "Infinity", "NaN", "-Infinity"])
        assert(decodeInto(cast(const(ubyte)[]) bad, number, arena).code == Status.invalidArgument);
    auto invalid = double.nan;
    assert(encodeJson(invalid, arena).error.code == Status.invalidArgument);
    invalid = double.infinity;
    assert(encodeJson(invalid, arena).error.code == Status.invalidArgument);

    float[1] single;
    assert(decodeInto(cast(const(ubyte)[]) "3.4028234663852886e38", single[0], arena).code == Status.ok);
    assert(single[0] == float.max);
    assert(decodeInto(cast(const(ubyte)[]) "3.4028236e38", single[0], arena).code == Status.invalidArgument);
}

@("seeded finite binary64 values round trip exactly through decimal JSON")
unittest
{
    ubyte[1024] backing;
    scope arena = RequestArena(backing[]);
    ulong state = 0xb1c3_765a_3459_2c10;
    foreach (index; 0 .. 512)
    {
        state ^= state << 13;
        state ^= state >>> 7;
        state ^= state << 17;
        FloatView sample;
        sample.raw = state;
        if ((sample.raw & 0x7ff0_0000_0000_0000) == 0x7ff0_0000_0000_0000)
            continue;

        auto encoded = encodeJson(sample.number, arena);
        assert(encoded.ok());
        const status = arena.read(encoded.value, (scope const(ubyte)[] bytes) @safe nothrow @nogc {
            FloatView decoded;
            assert(decodeInto(bytes, decoded.number, arena).code == Status.ok);
            assert(decoded.raw == sample.raw);
        });
        assert(status == Status.ok);
        assert(arena.reset() == Status.ok);
    }
}

@("JSON Schema uses the same deterministic field names and verified restrictions")
unittest
{
    import flint.serde : jsonSchema;

    static struct SchemaValue
    {
        @JsonRequired @JsonName("count")
        byte amount;
        @JsonIgnore int hidden;
        Kind kind;
    }

    ubyte[512] backing;
    scope arena = RequestArena(backing[]);
    auto schema = jsonSchema!SchemaValue(arena);
    assert(schema.ok());
    enum prefix = `{"type":"object","properties":{"count":{"type":"integer","minimum":-128,"maximum":127},`;
    enum properties = `"kind":{"type":"string","enum":["primary","secondary"]}},`;
    enum suffix = `"required":["count"],"additionalProperties":false}`;
    assert(equal(arena, schema.value, prefix ~ properties ~ suffix));
}

@("native owned JSON strings and nested arrays outlive the borrowed source")
unittest
{
    import flint.serde.owned : deserialize;

    static struct Payload
    {
        @JsonDefault("\"fallback\"")
        string title;
        string[][] values;
        int[] numbers;
    }

    char[66] source;
    enum json = `{"values":[["\u00e9",""],["\u0000"]],"numbers":[3,-4]}`;
    source[0 .. json.length] = json;
    auto result = deserialize!Payload(source[0 .. json.length]);
    assert(result.ok());
    source[] = ' ';
    assert(result.value.title == "fallback");
    assert(result.value.values.length == 2);
    assert(result.value.values[0][0] == "é" && result.value.values[0][1] == "");
    assert(result.value.values[1][0].length == 1 && result.value.values[1][0][0] == 0);
    assert(result.value.numbers[0] == 3 && result.value.numbers[1] == -4);

    auto options = DecodeOptions.init;
    options.maxMembers = 1;
    assert(deserialize!(int[])("[1,2]", options).error.code == Status.resourceExhausted);
}

@("native owned values serialize with dynamic arrays, names, ignores and canonical order, and round-trip")
unittest
{
    import flint.serde.owned : deserialize, serialize;

    static struct Location
    {
        string file;
        long line;
    }

    static struct Report
    {
        @JsonName("schema_name")
        string schema;
        bool ok;
        string[] names;
        Location[] where;
        Kind kind;
        @JsonIgnore string hidden = "secret";
    }

    Report report = Report("flint.check/1", true, ["a", "b\"c\n"], [Location("src/x.d", 3)], Kind.secondary);
    auto text = serialize(report);
    assert(text.ok());
    enum expected = `{"schema_name":"flint.check/1","ok":true,"names":["a","b\"c\n"],`
        ~ `"where":[{"file":"src/x.d","line":3}],"kind":"secondary"}`;
    assert(text.value == expected);

    auto options = EncodeOptions.init;
    options.canonical = true;
    auto sorted = serialize(report, options);
    assert(sorted.ok() && sorted.value == `{"kind":"secondary","names":["a","b\"c\n"],"ok":true,`
            ~ `"schema_name":"flint.check/1","where":[{"file":"src/x.d","line":3}]}`);

    auto back = deserialize!Report(text.value);
    assert(back.ok() && back.value.names == report.names && back.value.where[0].line == 3);
    Report empty;
    assert(serialize(empty).value == `{"schema_name":"","ok":false,"names":[],"where":[],"kind":"primary"}`);

    auto deep = EncodeOptions.init;
    deep.maxDepth = 1;
    assert(serialize(report, deep).error.code == Status.resourceExhausted);
    auto many = new int[DecodeOptions.init.maxMembers + 1];
    assert(serialize(many).error.code == Status.resourceExhausted);
}

@("arena JSON encoding still rejects dynamic arrays at compile time")
unittest
{
    static struct Owned
    {
        int[] values;
    }

    static assert(!__traits(compiles, () {
            ubyte[64] backing;
            auto arena = RequestArena(backing[]);
            Owned value;
            return encodeJson(value, arena);
        }));
}

private char[] memberName(char prefix, size_t index)
{
    char[6] name = prefix;
    foreach_reverse (position; 1 .. 6)
    {
        name[position] = cast(char)('0' + index % 10);
        index /= 10;
    }
    return name[].dup;
}

private char[] wideObject(char prefix, size_t members, size_t valueBytes)
{
    char[] text = "{".dup;
    foreach (index; 0 .. members)
    {
        if (index != 0)
            text ~= ',';
        text ~= '"';
        text ~= memberName(prefix, index);
        text ~= `":"`;
        foreach (fill; 0 .. valueBytes)
            text ~= 'x';
        text ~= '"';
    }
    return text ~ '}';
}

@("duplicate detection in skipped and visited JSON objects stays linear in the input size")
unittest
{
    import core.time : MonoTime, seconds;
    import flint.arena : Error;
    import flint.serde.json_visit : JsonMemberName, visitJsonObject;

    static struct Known
    {
        int known;
        @JsonIgnore int skipped;
    }

    static struct Open
    {
        int known;
    }

    const wide = wideObject('k', 1000, 1000);
    assert(wide.length < 1_040_000);
    ubyte[64] storage;
    scope arena = RequestArena(storage[]);
    auto ignoring = DecodeOptions.init;
    ignoring.unknownFields = UnknownFields.ignore;

    const started = MonoTime.currTime;
    Open open;
    assert(decodeInto(cast(const(ubyte)[]) wide, open, arena, ignoring).code == Status.ok);
    Known known;
    const nested = `{"skipped":` ~ wide ~ `,"known":3}`;
    assert(decodeInto(cast(const(ubyte)[]) nested, known, arena).code == Status.ok && known.known == 3);
    uint visited;
    auto count = delegate Error(scope JsonMemberName name, scope const(ubyte)[] value) @safe nothrow @nogc {
        if (name.length == 6 && value.length == 1002)
            ++visited;
        return Error.init;
    };
    const visiting = visitJsonObject(cast(const(ubyte)[]) wide, count);
    assert(visiting.code == Status.ok && visited == 1000);
    assert(MonoTime.currTime - started < 3.seconds);
}

@("duplicate detection is exact across very wide nested JSON objects")
unittest
{
    static struct Open
    {
        int known;
    }

    ubyte[64] storage;
    scope arena = RequestArena(storage[]);
    auto ignoring = DecodeOptions.init;
    ignoring.unknownFields = UnknownFields.ignore;
    Open open;

    // The inner object displaces earlier outer names; the late outer repeat must still be found.
    const outer = wideObject('o', 900, 1);
    const inner = wideObject('i', 1000, 1);
    const repeated = outer[0 .. $ - 1] ~ `,"inner":` ~ inner ~ `,"o00007":1}`;
    auto failure = decodeInto(cast(const(ubyte)[]) repeated, open, arena, ignoring);
    assert(failure.code == Status.invalidArgument && failure.message == "duplicate JSON member");
    assert(failure.offset == repeated.length - `"o00007":1}`.length);
    const distinct = outer[0 .. $ - 1] ~ `,"inner":` ~ inner ~ `,"o00900":1,"known":5}`;
    assert(decodeInto(cast(const(ubyte)[]) distinct, open, arena, ignoring).code == Status.ok && open.known == 5);

    // The same checks apply inside a skipped value and to escaped spellings.
    const skipped = `{"skip":` ~ outer[0 .. $ - 1] ~ `,"inner":` ~ inner ~ `,"o00899":1}}`;
    failure = decodeInto(cast(const(ubyte)[]) skipped, open, arena, ignoring);
    assert(failure.code == Status.invalidArgument && failure.message == "duplicate JSON member");
    assert(failure.offset == skipped.length - `"o00899":1}}`.length);
    const innerRepeat = `{"skip":` ~ outer[0 .. $ - 1] ~ `,"inner":` ~ inner[0 .. $ - 1] ~ `,"i00999":2}}}`;
    failure = decodeInto(cast(const(ubyte)[]) innerRepeat, open, arena, ignoring);
    assert(failure.code == Status.invalidArgument);
    assert(failure.offset == innerRepeat.length - `"i00999":2}}}`.length);
}
