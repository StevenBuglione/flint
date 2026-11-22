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

/// Shortest round-trip floating point output without druntime (ADR-017 decision 10).
struct Floats
{
    /// Exercise the binary64 shortest writer and both parser paths.
    double[5] d;
    /// Exercise the binary32 interval in the same core.
    float[3] f;
}

private union DoubleBits
{
    ulong raw;
    double value;
}

private int floatTest() nothrow @nogc
{
    ubyte[1024] storage;
    scope arena = RequestArena(storage[]);
    Floats value;
    DoubleBits bits;
    bits.raw = 1;
    value.d = [0.1, bits.value, double.max, 0x1p-1022, -2.5];
    value.f = [0.1f, float.max, 0x1p-149f];
    auto output = encodeJson(value, arena);
    assert(output.ok());
    enum expected = `{"d":[0.1,5e-324,1.7976931348623157e308,2.2250738585072014e-308,-2.5],`
        ~ `"f":[0.1,3.4028235e38,1e-45]}`;
    Floats decoded;
    const read = arena.read(output.value, (scope const(ubyte)[] bytes) @safe nothrow @nogc {
        assert(bytes.length == expected.length);
        foreach (index, byteValue; bytes)
            assert(byteValue == expected[index]);
        assert(decodeInto(bytes, decoded, arena).code == Status.ok);
    });
    assert(read == Status.ok);
    foreach (index; 0 .. value.d.length)
    {
        DoubleBits left;
        DoubleBits right;
        left.value = value.d[index];
        right.value = decoded.d[index];
        assert(left.raw == right.raw);
    }
    foreach (index; 0 .. value.f.length)
        assert(value.f[index] == decoded.f[index]);
    return 0;
}

private int behaviorTest() nothrow @nogc
{
    if (floatTest() != 0)
        return 1;
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
