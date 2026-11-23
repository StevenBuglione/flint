/// Acceptance tests for TOML 1.0 binding and checked output.
module toml_behavior;

import flint.arena : Buffer, RequestArena, Status, Text;
import flint.serde : DecodeOptions, EncodeOptions, JsonDefault, JsonName, JsonRequired, TomlDate,
    TomlDateTime, TomlTime, UnknownFields, decodeTomlInto, encodeToml;
import flint.serde.owned : deserializeToml;

@safe:

private struct Server
{
    @JsonRequired
    ushort port;
    @JsonName("server name")
    Text name;
    @JsonDefault("true")
    bool active;
}

private struct Service
{
    Server server;
    TomlDate calendar;
    TomlTime clock;
    TomlDateTime start;
    int[3] codes;
    double ratio;
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

@("TOML handles headers, quoted dotted keys, base-prefixed numbers and tagged calendar values")
unittest
{
    enum input = `calendar = 2000-02-29
clock = 18:15:12.1234567891
start = 2026-11-21 08:15:12.124-05:30
codes = [0xF_F, 0o12, 0b10_01,] # canonical integer values
ratio = +1_2.50e-1
[server]
port = 8_080
"server name" = "serv\u00e9ur"
`;
    ubyte[2048] backing;
    scope arena = RequestArena(backing[]);
    Service service;
    auto status = decodeTomlInto(cast(const(ubyte)[]) input, service, arena);
    assert(status.code == Status.ok, status.message);
    assert(service.server.port == 8080 && service.server.active);
    assert(equal(arena, service.server.name.bytes, "servéur"));
    assert(service.calendar == TomlDate(2000, 2, 29));
    assert(service.clock == TomlTime(18, 15, 12, 123_456_789));
    assert(service.start == TomlDateTime(TomlDate(2026, 11, 21), TomlTime(8, 15, 12, 124_000_000), -330, true));
    assert(service.codes == [255, 10, 9]);
    assert(service.ratio == 1.25);

    auto encoded = encodeToml(service, arena, EncodeOptions(true));
    assert(encoded.ok(), encoded.error.message);
    enum expected = `calendar = 2000-02-29
clock = 18:15:12.123456789
codes = [255, 10, 9]
ratio = 1.25
server = {active = true, port = 8080, "server name" = "servéur"}
start = 2026-11-21T08:15:12.124-05:30
`;
    assert(equal(arena, encoded.value, expected));
    const reread = arena.read(encoded.value, (scope const(ubyte)[] bytes) @safe nothrow @nogc {
        Service roundtrip;
        assert(decodeTomlInto(bytes, roundtrip, arena).code == Status.ok);
        assert(roundtrip.server.port == service.server.port && roundtrip.start == service.start);
    });
    assert(reread == Status.ok);
}

@("TOML literal and basic multiline strings normalize newlines and line continuation")
unittest
{
    static struct Texts
    {
        string literal;
        string basic;
        string ends;
        string empty;
    }

    enum input = `literal = '''
first
second'''
basic = """
first \
    second\U0001F600
last"""
ends = """one quote""""
empty = ""
`;
    auto result = deserializeToml!Texts(input);
    assert(result.ok(), result.error.message);
    assert(result.value.literal == "first\nsecond");
    assert(result.value.basic == "first second😀\nlast");
    assert(result.value.ends == "one quote\"");
    assert(result.value.empty.length == 0);

    enum rawCrlf = "literal = '''\r\na\r\nb'''";
    auto redone = deserializeToml!Texts(rawCrlf);
    assert(redone.ok());
    assert(redone.value.literal == "a\nb");
}

@("TOML table arrays keep source order and route child headers to the latest element")
unittest
{
    static struct Inventory
    {
        static struct Item
        {
            uint id;
            Label category;
        }

        static struct Label
        {
            string label;
        }

        Item[] items;
    }

    enum input = `[[items]]
id = 1
[items.category]
label = 'first'
[[items]]
id = 2
[items.category]
label = 'second'
`;
    auto result = deserializeToml!Inventory(input);
    assert(result.ok(), result.error.message);
    assert(result.value.items.length == 2);
    assert(result.value.items[0].id == 1 && result.value.items[0].category.label == "first");
    assert(result.value.items[1].id == 2 && result.value.items[1].category.label == "second");
}

@("TOML rejects repeated keys, reopened inline tables and invalid scalars before allocating")
unittest
{
    ubyte[128] backing;
    scope arena = RequestArena(backing[]);
    Service service;
    auto previous = arena.copyIn(cast(const(ubyte)[]) "preserved");
    assert(previous.ok());
    service.server.name = Text(previous.value);
    const used = arena.stats().used;
    auto options = DecodeOptions.init;
    options.unknownFields = UnknownFields.ignore;
    options.rejectDuplicateKeys = false;

    immutable invalid = [
        "server.port = 1\nserver.port = 2\n", "server.port = 1\n[server]\n",
        "[server]\nport = 1\n[server]\n", "server = {port=1}\n[server]\n",
        "server = {port=1,}\n", "server.port = 0x_10\n",
        "server.port = +0x10\n", "server.port = 01\n", "server.port = 65536\n",
        "server.port = 1\ncalendar=1900-02-29\n", "server.port = 1\nclock=25:00:00\n",
        "server.port = 1\nclock=13:00:00.\n", "server.port = 1\nratio=1e999\n",
        "server.port = 1\nratio=1_.0\n", "server.port=1\n" ~ `ignored = {a=1,"\u0061"=2}` ~ "\n",
    ];
    foreach (input; invalid)
    {
        const result = decodeTomlInto(cast(const(ubyte)[]) input, service, arena, options);
        assert(result.code == Status.invalidArgument, input);
        assert(result.offset <= input.length);
        assert(arena.stats().used == used);
        assert(equal(arena, service.server.name.bytes, "preserved"));
    }
}

@("TOML binding is transactional for missing required keys, stale handles and allocation failure")
unittest
{
    ubyte[8] backing;
    scope arena = RequestArena(backing[]);
    Server value;
    auto previous = arena.copyIn(cast(const(ubyte)[]) "abc");
    assert(previous.ok());
    value.name = Text(previous.value);
    const used = arena.stats().used;

    enum full = `port=1
"server name"="too much"
`;
    assert(decodeTomlInto(cast(const(ubyte)[]) full, value, arena).code == Status.outOfMemory);
    assert(value.port == 0 && equal(arena, value.name.bytes, "abc"));
    assert(arena.stats().used == used);
    assert(decodeTomlInto(cast(const(ubyte)[]) `"server name"="a"`, value, arena).code == Status.invalidArgument);
    assert(arena.stats().used == used);
    assert(arena.reset() == Status.ok);
    assert(encodeToml(value, arena).error.code == Status.invalidArgument);
    assert(arena.stats().used == 0);
}

@("TOML entries preserve explicit empty values, decoded paths and source positions")
unittest
{
    import flint.serde.owned : readTomlEntries;

    enum config = `title = "old"
[a."quoted.key"]
enabled = false
port = 0
dates = [2026-11-21, "quoted", 0x10]
[a.empty]
`;
    auto entries = readTomlEntries(config);
    assert(entries.ok(), entries.error.message);
    assert(entries.value.length == 5);
    assert(entries.value[0].path == ["title"]);
    assert(entries.value[0].json == `"old"` && entries.value[0].offset == 0);
    assert(entries.value[1].path == ["a", "quoted.key", "enabled"]);
    assert(entries.value[1].json == "false" && config[entries.value[1].offset] == 'e');
    assert(entries.value[2].path == ["a", "quoted.key", "port"] && entries.value[2].json == "0");
    assert(entries.value[3].json == `["2026-11-21","quoted",16]`);
    assert(entries.value[4].path == ["a", "empty"] && entries.value[4].json == "{}");
}

@("owned TOML entries sort interleaved tables by source offset")
unittest
{
    import flint.serde.owned : readTomlEntries;

    enum source = "title = 1\n[a]\nx = 2\n[b]\ny = 3\n[a.nested]\nz = 4\n";
    const result = readTomlEntries(source);
    assert(result.ok() && result.value.length == 4);
    assert(result.value[0].path == ["title"]);
    assert(result.value[1].path == ["a", "x"]);
    assert(result.value[2].path == ["b", "y"]);
    assert(result.value[3].path == ["a", "nested", "z"]);
    foreach (index; 1 .. result.value.length)
        assert(result.value[index - 1].offset < result.value[index].offset);
}

@("seeded malformed TOML inputs retain existing destination and arena data")
unittest
{
    enum sample = `port=8080
"server name"="Flint"
active=true
`;
    uint state = 0x699b_1b23;
    foreach (index; 0 .. 256)
    {
        ubyte[256] backing;
        scope arena = RequestArena(backing[]);
        auto previous = arena.copyIn(cast(const(ubyte)[]) "preserved");
        assert(previous.ok());
        const used = arena.stats().used;
        Server value = Server(42, Text(previous.value), true);
        ubyte[sample.length] source;
        source[] = cast(const(ubyte)[]) sample;
        state ^= state << 13;
        state ^= state >>> 17;
        state ^= state << 5;
        source[state % source.length] = cast(ubyte)(state >> 17);

        const failure = decodeTomlInto(source[], value, arena);
        if (failure.code != Status.ok)
        {
            assert(value.port == 42);
            assert(arena.stats().used == used);
            assert(equal(arena, value.name.bytes, "preserved"));
        }
        assert(equal(arena, previous.value, "preserved"));
    }
}

@("TOML omission bypasses ignored application-only field types")
unittest
{
    import flint.serde : JsonIgnore;

    static struct Payload
    {
        int value;
        @JsonIgnore
        void* context;
    }

    ubyte[128] backing;
    scope arena = RequestArena(backing[]);
    const payload = Payload(7);
    const encoded = encodeToml(payload, arena);
    assert(encoded.ok() && equal(arena, encoded.value, "value = 7\n"));
    const all = encodeToml(payload, arena, EncodeOptions(false, false));
    assert(all.error.code == Status.invalidArgument);
}

private char[] longKeyTable(string open, string close, size_t members)
{
    char[] prefix;
    foreach (index; 0 .. 1000)
        prefix ~= 'a';
    char[] text;
    foreach (index; 0 .. members)
    {
        char[4] digits;
        size_t value = index;
        foreach_reverse (position; 0 .. 4)
        {
            digits[position] = cast(char)('0' + value % 10);
            value /= 10;
        }
        text ~= open ~ prefix ~ digits[] ~ close ~ " = 1\n";
    }
    return text;
}

@("TOML sibling lookup stays fast for long keys with a shared prefix")
unittest
{
    import core.time : MonoTime, seconds;

    static struct Empty
    {
        int unused;
    }

    ubyte[64] storage;
    scope arena = RequestArena(storage[]);
    auto options = DecodeOptions.init;
    options.unknownFields = UnknownFields.ignore;
    Empty value;
    const started = MonoTime.currTime;
    foreach (quote; ["", "\"", "'"])
    {
        const document = longKeyTable(quote, quote, 1000);
        assert(document.length < 1_048_576);
        assert(decodeTomlInto(cast(const(ubyte)[]) document, value, arena, options).code == Status.ok);
    }
    // Escaped and verbatim spellings of the same key are still duplicates.
    const repeated = longKeyTable("\"", "\"", 3) ~ "\"\\u0061" ~ longKeyTable("", "", 2)[1 .. 1004] ~ "\" = 2\n";
    const failure = decodeTomlInto(cast(const(ubyte)[]) repeated, value, arena, options);
    assert(failure.code == Status.invalidArgument && failure.message == "duplicate TOML key");
    assert(MonoTime.currTime - started < 3.seconds);
}
