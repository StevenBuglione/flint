module base64_test;

import flint.java.lang : IllegalArgumentException;
import flint.java.util.base64 : Base64;
import std.conv : to;
import std.exception : assertThrown, collectException;
import std.string : split, splitLines, startsWith;
import std.utf : encode;

@safe:

private byte[] unhex(string text)
{
    if (text == "-")
        return null;
    auto bytes = new byte[text.length / 2];
    foreach (i, ref b; bytes)
        b = cast(byte) text[2 * i .. 2 * i + 2].to!ubyte(16);
    return bytes;
}

/// Java's String of ISO-8859-1 `bytes`, as UTF-8.
private string latin1(scope const(byte)[] bytes)
{
    string text;
    foreach (b; bytes)
    {
        char[4] buffer;
        text ~= buffer[0 .. encode(buffer, cast(dchar) cast(ubyte) b)].idup;
    }
    return text;
}

private Base64.Encoder encoderNamed(string name)
{
    final switch (name)
    {
    case "basic":
        return Base64.getEncoder();
    case "url":
        return Base64.getUrlEncoder();
    case "mime":
        return Base64.getMimeEncoder();
    case "basic-np":
        return Base64.getEncoder().withoutPadding();
    case "url-np":
        return Base64.getUrlEncoder().withoutPadding();
    case "mime-np":
        return Base64.getMimeEncoder().withoutPadding();
    case "mime10lf":
        return Base64.getMimeEncoder(10, ['\n']);
    case "mime10lf-np":
        return Base64.getMimeEncoder(10, ['\n']).withoutPadding();
    case "mime8none":
        return Base64.getMimeEncoder(8, null);
    }
}

private Base64.Decoder decoderNamed(string name)
{
    final switch (name)
    {
    case "basic":
        return Base64.getDecoder();
    case "url":
        return Base64.getUrlDecoder();
    case "mime":
        return Base64.getMimeDecoder();
    }
}

/// Check one decoder result against the oracle's output hex or `!message`.
private void checkDecode(lazy byte[] result, string expected, string line)
{
    if (expected.startsWith("!"))
    {
        const e = collectException!IllegalArgumentException(result);
        assert(e !is null, line);
        assert(e.msg == expected[1 .. $], line ~ " got " ~ e.msg);
    }
    else
    {
        assert(result == unhex(expected), line);
    }
}

@("Base64 encoders and decoders match Java SE 21")
unittest
{
    size_t[char] rows;
    foreach (line; import("base64-java21.tsv").splitLines())
    {
        auto fields = line.split("\t");
        switch (fields[0])
        {
        case "E":
            auto encoder = encoderNamed(fields[1]);
            const input = unhex(fields[2]);
            const expected = unhex(fields[3]);
            assert(encoder.encode(input) == expected, line);
            assert(encoder.encodeToString(input) == latin1(expected), line);
            auto exact = new byte[expected.length];
            assert(encoder.encode(input, exact) == expected.length, line);
            assert(exact == expected, line);
            auto roomy = new byte[expected.length + 3];
            assert(encoder.encode(input, roomy) == expected.length, line);
            assert(roomy[0 .. expected.length] == expected, line);
            break;
        case "D":
            auto decoder = decoderNamed(fields[1]);
            const input = unhex(fields[2]);
            checkDecode(decoder.decode(input), fields[3], line);
            if (!fields[3].startsWith("!"))
            {
                const expected = unhex(fields[3]);
                auto exact = new byte[expected.length];
                assert(decoder.decode(input, exact) == expected.length, line);
                assert(exact == expected, line);
            }
            break;
        case "S":
            auto decoder = decoderNamed(fields[1]);
            const text = cast(const(char)[]) unhex(fields[2]);
            checkDecode(decoder.decode(text), fields[3], line);
            break;
        case "M":
            const separator = unhex(fields[2]);
            const input = unhex(fields[3]);
            if (fields[4].startsWith("!"))
            {
                const e = collectException!IllegalArgumentException(Base64.getMimeEncoder(fields[1].to!int, separator));
                assert(e !is null && e.msg == fields[4][1 .. $], line);
            }
            else
            {
                const expected = unhex(fields[4]);
                auto encoder = Base64.getMimeEncoder(fields[1].to!int, separator);
                assert(encoder.encode(input) == expected, line);
                assert(encoder.encodeToString(input) == latin1(expected), line);
            }
            break;
        default:
            assert(false, line);
        }
        ++rows.require(fields[0][0]);
    }
    assert(rows['E'] == 432 && rows['D'] == 1491 && rows['S'] == 30 && rows['M'] == 121);
}

@("Base64 rejects output arrays that are too small")
unittest
{
    const raw = cast(const(byte)[]) "foobar";
    auto small = new byte[7];
    auto e = collectException!IllegalArgumentException(Base64.getEncoder().encode(raw, small));
    assert(e !is null && e.msg == "Output byte array is too small for encoding all input bytes");
    assert(Base64.getEncoder().withoutPadding().encode(cast(const(byte)[]) "fooba", small) == 7);

    auto two = new byte[2];
    e = collectException!IllegalArgumentException(Base64.getDecoder().decode(cast(const(byte)[]) "Zm9v", two));
    assert(e !is null && e.msg == "Output byte array is too small for decoding all input bytes");
    assert(Base64.getDecoder().decode(cast(const(byte)[]) "Zm8=", two) == 2);
    assert(two == cast(const(byte)[]) "fo");
}

@("Base64 null arrays count as empty (R26) and withoutPadding is idempotent")
unittest
{
    auto encoder = Base64.getUrlEncoder();
    assert(encoder.encode(null).length == 0);
    assert(encoder.encodeToString(null) == "");
    assert(encoder.encode(null, null) == 0);
    assert(Base64.getMimeDecoder().decode(cast(const(byte)[]) null).length == 0);
    assert(Base64.getDecoder().decode("").length == 0);
    auto bare = encoder.withoutPadding();
    assert(bare !is encoder);
    assert(bare.withoutPadding() is bare);
    assert(Base64.getMimeEncoder(3, ['\n']).encodeToString(cast(const(byte)[]) "foobar") == "Zm9vYmFy");
}

@("Base64 MIME separator above 0x7F reads as its Latin-1 character")
unittest
{
    auto encoder = Base64.getMimeEncoder(4, [cast(byte) 0xe9]);
    assert(encoder.encodeToString(cast(const(byte)[]) "foobar") == "Zm9véYmFy");
    assert(encoder.encode(cast(const(byte)[]) "foobar") == cast(const(byte)[]) "Zm9v\xe9YmFy");
    assertThrown!IllegalArgumentException(Base64.getMimeEncoder(4, cast(const(byte)[]) "\r\n="));
}
