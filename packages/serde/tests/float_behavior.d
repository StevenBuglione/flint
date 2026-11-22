/// Shortest round-trip floating point output (ADR-017 decision 10).
module flint.serde.float_behavior_test;

import flint.arena : RequestArena, Status;
import flint.serde : decodeInto, decodeTomlInto, encodeJson, encodeToml;
import flint.serde.internal.shortest : inversePow5, pow5;

@safe:

private struct Text
{
    char[2048] bytes;
    size_t length;
    bool failed;

    const(char)[] opSlice() const return
    {
        return failed ? "<error>" : bytes[0 .. length];
    }
}

private Text encoded(T)(T value, bool toml = false)
{
    static struct Holder
    {
        T x;
    }

    ubyte[4096] backing;
    scope arena = RequestArena(backing[]);
    Text text;
    const holder = Holder(value);
    auto result = toml ? encodeToml(holder, arena) : encodeJson(value, arena);
    if (!result.ok())
    {
        text.failed = true;
        return text;
    }
    const status = arena.read(result.value, (scope const(ubyte)[] bytes) @safe nothrow @nogc {
        if (bytes.length > text.bytes.length)
        {
            text.failed = true;
            return;
        }
        foreach (index, byteValue; bytes)
            text.bytes[index] = cast(char) byteValue;
        text.length = bytes.length;
    });
    text.failed |= status != Status.ok;
    return text;
}

private union DoubleView
{
    ulong raw;
    double number;
}

private union FloatView
{
    uint raw;
    float number;
}

private double fromBits(ulong raw)
{
    DoubleView view;
    view.raw = raw;
    return view.number;
}

private float fromBits32(uint raw)
{
    FloatView view;
    view.raw = raw;
    return view.number;
}

// Expected text is Go's encoding/json output for the same bits (go1.27.4), which
// uses the same fixed/exponent thresholds; Flint writes `e21` where Go writes `e+21`.
@("binary64 output is the shortest decimal that round trips, matching Go")
unittest
{
    immutable ulong[] bits = [
        0x3fb999999999999a, 0x3fd3333333333333, 0x3ff0000000000000, 0xc004000000000000,
        0x0000000000000001, 0x7fefffffffffffff, 0x0010000000000000, 0x444b1ae4d6e2ef50,
        0x4480f0cf064dd592, 0x441ac53a7e04bcda, 0x3eb0c6f7a0b5ed8d, 0x3e7ad7f29abcaf48,
        0x3eb4b3fd5942cd96, 0x44b52d02c7e14af6, 0x4340000000000000, 0x4059000000000000,
        0x3fd5555555555555, 0x3fe5555555555555, 0x00005c0ab9347ed7, 0x4011666666666666,
        0x430c6bf526340000, 0x41b1de784a000000, 0x44dfe185ca57c517, 0x8000000000000000,
    ];
    immutable string[] wanted = [
        "0.1", "0.3", "1", "-2.5", "5e-324", "1.7976931348623157e308", "2.2250738585072014e-308",
        "1e21", "1e22", "123456789012345680000", "0.000001", "1e-7", "0.000001234", "1e23",
        "9007199254740992", "100", "0.3333333333333333", "0.6666666666666666", "5e-310", "4.35",
        "1000000000000000", "299792458", "6.02214076e23", "-0",
    ];
    foreach (index, raw; bits)
    {
        const text = encoded(fromBits(raw));
        assert(text[] == wanted[index], wanted[index] ~ " != " ~ text[].idup);
    }
    assert(encoded(fromBits(0x3fb999999999999a), true)[] == "x = 0.1\n");
    assert(encoded(1.0, true)[] == "x = 1.0\n");
    assert(encoded(fromBits(0x0000000000000001), true)[] == "x = 5e-324\n");
    assert(encoded(1e22, true)[] == "x = 1e22\n");
}

@("binary32 output is the shortest decimal for the single-precision value, matching Go")
unittest
{
    immutable uint[] bits = [
        0x3dcccccd, 0x3f800000, 0x7f7fffff, 0x00000001, 0x4b800000, 0x3e99999a, 0x33d6bf95, 0x15ae43fe,
        0x00800000,
    ];
    immutable string[] wanted = [
        "0.1", "1", "3.4028235e38", "1e-45", "16777216", "0.3", "1e-7", "7.0385313e-26",
        "1.1754944e-38",
    ];
    foreach (index, raw; bits)
    {
        const text = encoded(fromBits32(raw));
        assert(text[] == wanted[index], wanted[index] ~ " != " ~ text[].idup);
    }
    assert(encoded(0.1f, true)[] == "x = 0.1\n");
}

// Significant digits and decimal exponent of a JSON number spelling.
private struct Spelling
{
    char[24] digits;
    size_t count;
    int exponent;
    bool negative;
}

private Spelling split(scope const(char)[] text)
{
    import std.conv : to;

    Spelling spelling;
    bool fraction;
    foreach (index, letter; text)
    {
        if (letter == 'e')
        {
            spelling.exponent += text[index + 1 .. $].to!int;
            break;
        }
        if (letter == '-')
            spelling.negative = true;
        else if (letter == '.')
            fraction = true;
        else
        {
            if (spelling.count != 0 || letter != '0')
                spelling.digits[spelling.count++] = letter;
            if (fraction)
                --spelling.exponent;
        }
    }
    for (; spelling.count > 1 && spelling.digits[spelling.count - 1] == '0'; --spelling.count)
        ++spelling.exponent;
    return spelling;
}

private bool decodesTo(T)(scope const(char)[] text, T value)
{
    T decoded;
    ubyte[256] backing;
    scope arena = RequestArena(backing[]);
    return decodeInto(cast(const(ubyte)[]) text, decoded, arena).code == Status.ok && sameBits(decoded, value);
}

// Shortest: no decimal with one digit fewer, rounded either way, parses to the same value.
private bool shortestRoundTrip(T)(T value)
{
    import std.conv : to;

    const text = encoded(value);
    if (text.failed || !decodesTo(text[], value))
        return false;
    const spelling = split(text[]);
    if (spelling.count <= 1)
        return true;
    foreach (up; [false, true])
    {
        const shorter = spelling.digits[0 .. spelling.count - 1].to!ulong + (up ? 1 : 0);
        const candidate = (spelling.negative ? "-" : "") ~ shorter.to!string ~ "e" ~ (spelling.exponent + 1).to!string;
        if (decodesTo(candidate, value))
            return false;
    }
    return true;
}

private bool sameBits(T)(T left, T right)
{
    static if (is(T == double))
    {
        DoubleView a, b;
        a.number = left;
        b.number = right;
    }
    else
    {
        FloatView a, b;
        a.number = left;
        b.number = right;
    }
    return a.raw == b.raw;
}

@("seeded binary64 and binary32 values round trip through the shortest decimal")
unittest
{
    ulong state = 0x9e37_79b9_7f4a_7c15;
    ulong next()
    {
        state ^= state << 13;
        state ^= state >>> 7;
        state ^= state << 17;
        return state;
    }

    foreach (index; 0 .. 20_000)
    {
        auto raw = next();
        // Every fourth sample is subnormal, every eighth an exact power of two.
        if (index % 4 == 1)
            raw &= 0x800f_ffff_ffff_ffff;
        else if (index % 8 == 2)
            raw &= 0xfff0_0000_0000_0000;
        if ((raw & 0x7ff0_0000_0000_0000) == 0x7ff0_0000_0000_0000)
            continue;
        assert(shortestRoundTrip(fromBits(raw)));
        immutable single = cast(uint) raw;
        if ((single & 0x7f80_0000) != 0x7f80_0000)
            assert(shortestRoundTrip(fromBits32(single)));
    }
    double power = 1;
    foreach (exponent; 0 .. 308)
    {
        assert(shortestRoundTrip(power) && shortestRoundTrip(-power));
        assert(shortestRoundTrip(1 / power));
        power *= 10;
    }
    foreach (raw; [
        0x0000_0000_0000_0001UL, 0x000f_ffff_ffff_ffff, 0x0010_0000_0000_0000, 0x7fef_ffff_ffff_ffff,
        0x3fef_ffff_ffff_ffff, 0x3ff0_0000_0000_0001, 0x4340_0000_0000_0000, 0x4330_0000_0000_0001
    ])
        assert(shortestRoundTrip(fromBits(raw)));
}

@("TOML floats keep a fraction and decode back to the same bits")
unittest
{
    static struct Holder
    {
        double x;
        float y;
    }

    ubyte[4096] backing;
    scope arena = RequestArena(backing[]);
    foreach (raw; [0x3fb999999999999aUL, 0x0000000000000001, 0x7fefffffffffffff, 0x4059000000000000])
    {
        const value = Holder(fromBits(raw), cast(float) fromBits(raw));
        auto result = encodeToml(value, arena);
        assert(result.ok());
        Holder decoded;
        const status = arena.read(result.value, (scope const(ubyte)[] bytes) @safe nothrow @nogc {
            assert(decodeTomlInto(bytes, decoded, arena).code == Status.ok);
        });
        assert(status == Status.ok && sameBits(decoded.x, value.x) && sameBits(decoded.y, value.y));
        assert(arena.reset() == Status.ok);
    }
}

@("power-of-five tables reconstruct the exact 125-bit Ryu values")
unittest
{
    import std.bigint : BigInt;

    BigInt five = 1;
    foreach (index; 0 .. 326)
    {
        // bits(5^index)
        size_t length;
        for (BigInt probe = five; probe != 0; probe >>= 1)
            ++length;
        const truncated = length >= 125 ? five >> (length - 125) : five << (125 - length);
        const parts = pow5(index);
        assert((BigInt(parts.high) << 64) + parts.low == truncated);
        if (index < 292)
        {
            const inverse = (BigInt(1) << (length - 1 + 125)) / five + 1;
            const inverseParts = inversePow5(index);
            assert((BigInt(inverseParts.high) << 64) + inverseParts.low == inverse);
        }
        five *= 5;
    }
}

@("zero with any exponent decodes to a signed zero in both widths")
unittest
{
    foreach (spelling; ["0e2000000000", "-0e2000000000", "-0.000e-99999", "0.0", "-0"])
    {
        immutable negative = spelling[0] == '-';
        assert(decodesTo(spelling, negative ? -0.0 : 0.0));
        assert(decodesTo(spelling, negative ? -0.0f : 0.0f));
    }
}
