module betterc_serde;

import flint.arena : RequestArena, Status, Text;
import flint.serde : EncodeOptions, JsonName, decodeInto, decodeTomlInto, encodeJson, encodeToml;

@safe:

/// Fixed JSON fixture shared by native and browser BetterC execution.
struct Value
{
    /// Exercise Unicode conversion into arena-owned text.
    @JsonName("a")
    Text text;
    /// Exercise bounded integer arrays.
    int[2] numbers;
    /// Exercise scalar output ordering.
    bool valid;
    /// Exercise portable floating point conversion.
    double precise;
}

private int behaviorTest() nothrow @nogc
{
    ubyte[1024] storage;
    scope arena = RequestArena(storage[]);
    Value value;
    enum input = `{"valid":true,"numbers":[-32,42],"a":"\u0000\ud83d\ude00","precise":1.25}`;
    auto error = decodeInto(cast(const(ubyte)[]) input, value, arena);
    assert(error.code == Status.ok);
    assert(value.valid && value.precise == 1.25);
    assert(value.numbers[0] == -32 && value.numbers[1] == 42);
    auto output = encodeJson(value, arena, EncodeOptions(true));
    assert(output.ok());
    enum expected = `{"a":"\u0000😀","numbers":[-32,42],"precise":1.25,"valid":true}`;
    const read = arena.read(output.value, (scope const(ubyte)[] bytes) @safe nothrow @nogc {
        assert(bytes.length == expected.length);
        foreach (index, byteValue; bytes)
            assert(byteValue == expected[index]);
    });
    assert(read == Status.ok);
    const reset = arena.reset();
    assert(reset == Status.ok);
    enum toml = "a = \"zi\\u00e9\"\nnumbers=[0x2A, -32]\nprecise=1.25\nvalid=true\n";
    assert(decodeTomlInto(cast(const(ubyte)[]) toml, value, arena).code == Status.ok);
    assert(value.valid && value.numbers[0] == 42 && value.numbers[1] == -32 && value.precise == 1.25);
    auto encodedToml = encodeToml(value, arena, EncodeOptions(true));
    assert(encodedToml.ok());
    enum wantedToml = "a = \"zié\"\nnumbers = [42, -32]\nprecise = 1.25\nvalid = true\n";
    const readToml = arena.read(encodedToml.value, (scope const(ubyte)[] bytes) @safe nothrow @nogc {
        assert(bytes.length == wantedToml.length);
        foreach (index, byteValue; bytes)
            assert(byteValue == wantedToml[index]);
    });
    assert(readToml == Status.ok);
    return 0;
}

version (WebAssembly)
{
    /// Execute the real package assertions from a freestanding wasm32 host.
    extern (C) export int flint_test() nothrow @nogc
    {
        return behaviorTest();
    }
}
else
{
    /// Execute the same assertions without druntime.
    extern (C) int main() nothrow @nogc
    {
        return behaviorTest();
    }
}
