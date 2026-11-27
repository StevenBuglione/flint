// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
// Original Flint tests of the standard US-ASCII, ISO-8859-1, UTF-8 and UTF-16* coders. golden/standard-coders-oracle.log
// is the output of StandardCodersOracle.java (standard-coders intake evidence) on Temurin 21.0.13+9; each test replays
// its lines through the Flint coders and expects the same line back.
module standard_coders_test;

import flint.java.nio.bytebuffer : ByteBuffer;
import flint.java.nio.charbuffer : CharBuffer;
import flint.java.nio.charset : Charset, StandardCharsets;
import flint.java.nio.charset.charsetdecoder : CharsetDecoder;
import flint.java.nio.charset.charsetencoder : CharsetEncoder;
import flint.java.nio.charset.coderresult : CoderResult;
import flint.java.nio.charset.codingerroraction : CodingErrorAction;
import flint.java.nio.charset.internal.decoders : standardDecoder;
import flint.java.nio.charset.internal.encoders : standardEncoder;
import std.array : join, split;
import std.conv : to;
import std.format : format;
import std.string : indexOf, lastIndexOf, lineSplitter, startsWith;

@safe:

private enum oracle = import("standard-coders-oracle.log");

private immutable Charset[6] standard = [
    StandardCharsets.US_ASCII, StandardCharsets.ISO_8859_1, StandardCharsets.UTF_8,
    StandardCharsets.UTF_16, StandardCharsets.UTF_16BE, StandardCharsets.UTF_16LE
];

// The oracle lines starting with `prefix`, at least `minimum` of them.
private string[] oracleLines(string prefix, size_t minimum)
{
    string[] lines;
    foreach (line; oracle.lineSplitter)
        if (line.startsWith(prefix))
            lines ~= line;
    assert(lines.length >= minimum, prefix);
    return lines;
}

private CodingErrorAction action(string a)
{
    return a == "R" ? CodingErrorAction.REPORT : a == "I" ? CodingErrorAction.IGNORE : CodingErrorAction.REPLACE;
}

private byte[] bytes(string hex)
{
    byte[] r;
    if (hex != "-")
        foreach (h; hex.split(" "))
            r ~= cast(byte) h.to!ubyte(16);
    return r;
}

private wchar[] units(string hex)
{
    wchar[] r;
    if (hex != "-")
        foreach (h; hex.split(" "))
            r ~= cast(wchar) h.to!ushort(16);
    return r;
}

private string hex(ByteBuffer b)
{
    string[] parts;
    foreach (i; 0 .. b.position())
        parts ~= format("%02x", cast(ubyte) b.get(i));
    return parts.length ? parts.join(" ") : "-";
}

private string hex(CharBuffer b)
{
    string[] parts;
    foreach (i; 0 .. b.position())
        parts ~= format("%04x", cast(ushort) b.get(i));
    return parts.length ? parts.join(" ") : "-";
}

// The fields of `op charset [input] capacity split eoi action -> ...`.
private struct Case
{
    string op, charset, input, action;
    int capacity, split;
    bool eoi;
}

private Case parse(string line)
{
    Case c;
    const open = line.indexOf('[');
    const close = line.indexOf(']');
    const head = line[0 .. open - 1].split(" ");
    c.op = head[0];
    c.charset = head[1];
    c.input = line[open + 1 .. close];
    const tail = line[close + 2 .. line.indexOf(" -> ")].split(" ");
    c.capacity = tail[0].to!int;
    c.split = tail[1].to!int;
    c.eoi = tail[2] == "true";
    c.action = tail[3];
    return c;
}

private string prefix(Case c)
{
    return format("%s %s [%s] %d %d %s %s -> ", c.op, c.charset, c.input, c.capacity, c.split, c.eoi, c.action);
}

// StandardCodersOracle.dec in Flint; `decro` decodes from a read-only source, which has no accessible array.
private string replayDecode(Case c)
{
    auto d = standardDecoder(Charset.forName(c.charset));
    d.onMalformedInput(action(c.action)).onUnmappableCharacter(action(c.action));
    auto src = bytes(c.input);
    auto bb = ByteBuffer.wrap(src);
    if (c.op == "decro")
        bb = bb.asReadOnlyBuffer();
    auto cb = CharBuffer.allocate(c.capacity);
    string r;
    if (c.split >= 0)
    {
        bb.limit(c.split);
        r = d.decode(bb, cb, false).toString() ~ " ";
        bb.limit(cast(int) src.length);
    }
    const cr = d.decode(bb, cb, c.eoi);
    r ~= cr.toString();
    if (c.eoi && cr.isUnderflow())
        r ~= " " ~ d.flush(cb).toString();
    return prefix(c) ~ format("%s %d [%s]", r, bb.position(), hex(cb));
}

// StandardCodersOracle.enc in Flint; `encro` encodes from a read-only source, which has no accessible array.
private string replayEncode(Case c)
{
    auto e = standardEncoder(Charset.forName(c.charset));
    e.onMalformedInput(action(c.action)).onUnmappableCharacter(action(c.action));
    auto src = units(c.input);
    auto cb = CharBuffer.wrap(src);
    if (c.op == "encro")
        cb = cb.asReadOnlyBuffer();
    auto bb = ByteBuffer.allocate(c.capacity);
    string r;
    if (c.split >= 0)
    {
        cb.limit(c.split);
        r = e.encode(cb, bb, false).toString() ~ " ";
        cb.limit(cast(int) src.length);
    }
    const cr = e.encode(cb, bb, c.eoi);
    r ~= cr.toString();
    if (c.eoi && cr.isUnderflow())
        r ~= " " ~ e.flush(bb).toString();
    return prefix(c) ~ format("%s %d [%s]", r, cb.position(), hex(bb));
}

@("StandardCoders.properties")
unittest
{
    foreach (line; oracleLines("props ", 6))
    {
        const cs = Charset.forName(line.split(" ")[1]);
        auto d = standardDecoder(cs);
        auto e = standardEncoder(cs);
        string rep;
        foreach (b; e.replacement())
            rep ~= format("%02x", cast(ubyte) b);
        assert(d.charset() == cs && e.charset() == cs);
        assert(d.replacement() == "\uFFFD");
        const got = format("props %s dec %.1f %.1f enc %.1f %.1f %s", cs.name(),
                d.averageCharsPerByte(), d.maxCharsPerByte(), e.averageBytesPerChar(), e.maxBytesPerChar(), rep);
        assert(got == line, got ~ "\n" ~ line);
    }
}

// Covers CharsetEncoder/CanEncode: unpaired surrogates are never encodable, and US-ASCII rejects U+00B6.
@("StandardCoders.canEncode")
unittest
{
    static immutable wchar[12] chars = [
        'x', '\u007f', '\u0080', '\u00B6', '\u00FF', '\u0100', '\u20AC', 0xD800, 0xDBFF, 0xDC00,
        0xDFFF, '\uFFFD'
    ];
    static immutable wchar[][8] texts = [
        "x"w, "xyzzy"w, "xy\u00B6"w, "\u20AC"w, "\U0001F600"w, [0xD800], ['a', 0xDC00],
        [0xDE00, 0xD83D]
    ];
    foreach (line; oracleLines("canEncode ", 6))
    {
        auto e = standardEncoder(Charset.forName(line.split(" ")[1]));
        string got = "canEncode " ~ e.charset().name() ~ " ";
        foreach (c; chars)
            got ~= e.canEncode(c) ? 'T' : 'F';
        got ~= ' ';
        foreach (i, t; texts)
        {
            const viaBuffer = e.canEncode(CharBuffer.wrap(t.dup));
            // A D string cannot hold an unpaired surrogate, so only the well-formed texts also go through UTF-8.
            const viaText = i < 5 ? e.canEncode(t.to!string) : viaBuffer;
            got ~= viaBuffer == viaText ? (viaBuffer ? 'T' : 'F') : '?';
        }
        assert(got == line, got ~ "\n" ~ line);
    }
}

@("StandardCoders.decode")
unittest
{
    foreach (line; oracleLines("dec", 600))
    {
        const got = replayDecode(parse(line));
        assert(got == line, got ~ "\n" ~ line);
    }
}

@("StandardCoders.encode")
unittest
{
    foreach (line; oracleLines("enc", 400))
    {
        const got = replayEncode(parse(line));
        assert(got == line, got ~ "\n" ~ line);
    }
}

// After reset, UTF-16 writes a byte-order mark again and reads the next one afresh.
@("StandardCoders.reuseAfterReset")
unittest
{
    foreach (line; oracleLines("reuse ", 4))
    {
        const fields = line.split(" ");
        const cs = Charset.forName(fields[2]);
        string got;
        if (fields[1] == "enc")
        {
            auto e = standardEncoder(cs);
            auto bb = ByteBuffer.allocate(16);
            e.encode(CharBuffer.wrap(['A']), bb, true);
            e.flush(bb);
            e.reset();
            e.encode(CharBuffer.wrap(['B']), bb, true);
            e.flush(bb);
            got = format("reuse enc %s [%s]", cs.name(), hex(bb));
        }
        else
        {
            auto d = standardDecoder(cs);
            auto cb = CharBuffer.allocate(8);
            d.decode(ByteBuffer.wrap(bytes("ff fe 41 00")), cb, true);
            d.flush(cb);
            d.reset();
            d.decode(ByteBuffer.wrap(bytes("00 42")), cb, true);
            d.flush(cb);
            got = format("reuse dec %s [%s]", cs.name(), hex(cb));
        }
        assert(got == line, got ~ "\n" ~ line);
    }
}

// Covers CharsetDecoder/ASCIIDecode: a reused US-ASCII decoder writes the ASCII prefix before reporting the
// malformed byte, on every call.
@("StandardCoders.asciiDecodeRepeated")
unittest
{
    auto decoder = standardDecoder(StandardCharsets.US_ASCII);
    auto input = bytes("60 60 60 ff");
    foreach (i; 0 .. 10_000)
    {
        auto output = new wchar[4];
        auto cb = CharBuffer.wrap(output);
        auto bb = ByteBuffer.wrap(input);
        const cr = decoder.decode(bb, cb, true);
        assert(output[0 .. 3] == "```"w && cr.isMalformed() && cr.length() == 1 && bb.position() == 3);
    }
}

// Covers CharsetDecoder/EmptyInput as far as it goes before CoderResult#throwException (fc-io-charset): an empty
// buffer decodes to UNDERFLOW, which throwException turns into BufferUnderflowException.
@("StandardCoders.emptyInput")
unittest
{
    foreach (cs; standard)
    {
        auto bb = ByteBuffer.allocate(10);
        bb.flip();
        auto cb = CharBuffer.allocate(10);
        const cr = standardDecoder(cs).decode(bb, cb, true);
        assert(cr.isUnderflow() && cb.position() == 0);
    }
}

// The default isLegalReplacement decodes with the standard decoder, so every standard encoder accepts its own
// default replacement.
@("StandardCoders.ownReplacementIsLegal")
unittest
{
    foreach (cs; standard)
    {
        auto e = standardEncoder(cs);
        assert(e.isLegalReplacement(e.replacement()));
    }
}
