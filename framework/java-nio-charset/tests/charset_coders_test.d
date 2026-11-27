// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
// Original Flint tests against the Java SE 21 CharsetDecoder and CharsetEncoder API, pinned by Temurin 21.0.13+9
// oracles (CoderIntakeOracle.java and LegalReplacementOracle.java in the charset-coders intake evidence).
module charset_coders_test;

import flint.java.lang : IllegalArgumentException, IllegalStateException, NullPointerException,
    UnsupportedOperationException;
import flint.java.nio.bufferoverflowexception : BufferOverflowException;
import flint.java.nio.bytebuffer : ByteBuffer;
import flint.java.nio.charbuffer : CharBuffer;
import flint.java.nio.charset : Charset, StandardCharsets;
import flint.java.nio.charset.charsetdecoder : CharsetDecoder;
import flint.java.nio.charset.charsetencoder : CharsetEncoder;
import flint.java.nio.charset.codermalfunctionerror : CoderMalfunctionError;
import flint.java.nio.charset.coderresult : CoderResult;
import flint.java.nio.charset.codingerroraction : CodingErrorAction;
import std.exception : collectException;

@safe:

// The oracle's US-ASCII loops: a negative byte is malformed, a character from U+0080 is unmappable.
/// A US-ASCII decoder like the oracle's.
final class AsciiDecoder : CharsetDecoder
{
    ///
    this(float average = 1, float max = 1)
    {
        super(StandardCharsets.US_ASCII, average, max);
    }

    protected override CoderResult decodeLoop(ByteBuffer in_, CharBuffer out_)
    {
        while (in_.hasRemaining())
        {
            if (!out_.hasRemaining())
                return CoderResult.OVERFLOW;
            const b = in_.get();
            if (b < 0)
            {
                in_.position(in_.position() - 1);
                return CoderResult.malformedForLength(1);
            }
            out_.put(cast(wchar) b);
        }
        return CoderResult.UNDERFLOW;
    }
}

/// A US-ASCII encoder like the oracle's.
class AsciiEncoder : CharsetEncoder
{
    ///
    this(float average = 1, float max = 1)
    {
        super(StandardCharsets.US_ASCII, average, max);
    }

    ///
    this(float average, float max, scope const(byte)[] replacement)
    {
        super(StandardCharsets.US_ASCII, average, max, replacement);
    }

    ///
    this(Charset cs, scope const(byte)[] replacement)
    {
        super(cs, 1, 8, replacement);
    }

    protected override CoderResult encodeLoop(CharBuffer in_, ByteBuffer out_)
    {
        while (in_.hasRemaining())
        {
            if (!out_.hasRemaining())
                return CoderResult.OVERFLOW;
            const c = in_.get();
            if (c >= 0x80)
            {
                in_.position(in_.position() - 1);
                return CoderResult.unmappableForLength(1);
            }
            out_.put(cast(byte) c);
        }
        return CoderResult.UNDERFLOW;
    }
}

/// Throws the given exception from its loop.
final class ThrowingDecoder : CharsetDecoder
{
    private Exception toThrow;

    ///
    this(Exception toThrow)
    {
        super(StandardCharsets.US_ASCII, 1, 1);
        this.toThrow = toThrow;
    }

    protected override CoderResult decodeLoop(ByteBuffer in_, CharBuffer out_)
    {
        throw toThrow;
    }
}

/// Throws IllegalStateException from its loop.
final class ThrowingEncoder : CharsetEncoder
{
    ///
    this()
    {
        super(StandardCharsets.US_ASCII, 1, 1);
    }

    protected override CoderResult encodeLoop(CharBuffer in_, ByteBuffer out_)
    {
        throw new IllegalStateException("boom");
    }
}

/// Returns UNDERFLOW without consuming anything, leaving input behind at end of input.
final class StallingDecoder : CharsetDecoder
{
    ///
    this()
    {
        super(StandardCharsets.US_ASCII, 1, 1);
    }

    protected override CoderResult decodeLoop(ByteBuffer in_, CharBuffer out_)
    {
        return CoderResult.UNDERFLOW;
    }
}

/// A shift-state encoder: a non-ASCII character opens a 3-byte escape, and flush closes it with another 3 bytes.
final class ShiftEncoder : CharsetEncoder
{
    private bool shifted;
    string[] calls; /// The impl hooks called, in order.

    ///
    this()
    {
        super(StandardCharsets.ISO_8859_1, 2, 8);
    }

    protected override CoderResult encodeLoop(CharBuffer in_, ByteBuffer out_)
    {
        while (in_.hasRemaining())
        {
            const c = in_.get(in_.position());
            const need = c < 0x80 ? (shifted ? 4 : 1) : (shifted ? 2 : 5);
            if (out_.remaining() < need)
                return CoderResult.OVERFLOW;
            if (c < 0x80 && shifted)
            {
                out_.put(cast(const(byte)[]) "\x1b(B");
                shifted = false;
            }
            else if (c >= 0x80 && !shifted)
            {
                out_.put(cast(const(byte)[]) "\x1b$B");
                shifted = true;
            }
            if (c < 0x80)
                out_.put(cast(byte) c);
            else
            {
                const byte[2] pair = [cast(byte)(c >> 8), cast(byte) c];
                out_.put(pair[]);
            }
            in_.get();
        }
        return CoderResult.UNDERFLOW;
    }

    protected override CoderResult implFlush(ByteBuffer out_)
    {
        calls ~= "implFlush";
        if (!shifted)
            return CoderResult.UNDERFLOW;
        if (out_.remaining() < 3)
            return CoderResult.OVERFLOW;
        out_.put(cast(const(byte)[]) "\x1b(B");
        shifted = false;
        return CoderResult.UNDERFLOW;
    }

    protected override void implReset()
    {
        calls ~= "implReset";
        shifted = false;
    }

    protected override void implReplaceWith(byte[] newReplacement)
    {
        calls ~= "implReplaceWith";
    }

    protected override void implOnMalformedInput(CodingErrorAction newAction)
    {
        calls ~= "implOnMalformedInput " ~ newAction.toString();
    }

    protected override void implOnUnmappableCharacter(CodingErrorAction newAction)
    {
        calls ~= "implOnUnmappableCharacter " ~ newAction.toString();
    }
}

private string messageOf(E)(scope void delegate() @safe action)
{
    auto e = collectException!E(action());
    assert(e !is null, "expected " ~ E.stringof);
    return e.msg.idup;
}

private byte[] bytes(scope const(ubyte)[] values...) pure nothrow
{
    return cast(byte[]) values.dup;
}

private byte[] written(ByteBuffer buffer)
{
    auto copy = new byte[buffer.position()];
    foreach (i, ref b; copy)
        b = buffer.get(cast(int) i);
    return copy;
}

private wstring writtenChars(CharBuffer buffer)
{
    auto copy = new wchar[buffer.position()];
    foreach (i, ref c; copy)
        c = buffer.get(cast(int) i);
    return copy.idup;
}

@("CharsetDecoder and CharsetEncoder constructors reject non-positive, NaN and inverted rates in Java's order")
unittest
{
    static struct Case
    {
        float average, max;
        string decoder, encoder;
    }

    static immutable Case[] cases = [
        Case(float.nan, 1, "Non-positive averageCharsPerByte", "Non-positive averageBytesPerChar"),
        Case(1, float.nan, "Non-positive maxCharsPerByte", "Non-positive maxBytesPerChar"),
        Case(0, 1, "Non-positive averageCharsPerByte", "Non-positive averageBytesPerChar"),
        Case(-1, 1, "Non-positive averageCharsPerByte", "Non-positive averageBytesPerChar"),
        Case(1, 0, "Non-positive maxCharsPerByte", "Non-positive maxBytesPerChar"),
        Case(1, -1, "Non-positive maxCharsPerByte", "Non-positive maxBytesPerChar"),
        Case(2, 1, "averageCharsPerByte exceeds maxCharsPerByte",
                "averageBytesPerChar exceeds maxBytesPerChar"),
        Case(3.9f, 1.2f, "averageCharsPerByte exceeds maxCharsPerByte",
                "averageBytesPerChar exceeds maxBytesPerChar"),
        Case(float.nan, float.nan, "Non-positive averageCharsPerByte", "Non-positive averageBytesPerChar"),
    ];
    foreach (c; cases)
    {
        assert(messageOf!IllegalArgumentException({ new AsciiDecoder(c.average, c.max); }) == c.decoder);
        assert(messageOf!IllegalArgumentException({ new AsciiEncoder(c.average, c.max); }) == c.encoder);
    }

    foreach (rates; [
            [1.0f, 1.0f], [float.infinity, float.infinity], [1.0f, float.infinity], [0.5f, 1.5f]
        ])
    {
        auto decoder = new AsciiDecoder(rates[0], rates[1]);
        assert(decoder.averageCharsPerByte() is rates[0] && decoder.maxCharsPerByte() is rates[1]);
        auto encoder = new AsciiEncoder(rates[0], rates[1]);
        assert(encoder.averageBytesPerChar() is rates[0] && encoder.maxBytesPerChar() is rates[1]);
    }
}

@("CharsetDecoder defaults: U+FFFD replacement, REPORT actions, no auto-detection")
unittest
{
    auto decoder = new AsciiDecoder;
    assert(decoder.charset() == StandardCharsets.US_ASCII);
    assert(decoder.replacement() == "\uFFFD");
    assert(decoder.malformedInputAction() == CodingErrorAction.REPORT);
    assert(decoder.unmappableCharacterAction() == CodingErrorAction.REPORT);
    assert(!decoder.isAutoDetecting());
    assert(messageOf!UnsupportedOperationException({ decoder.isCharsetDetected(); }) is null);
    assert(messageOf!UnsupportedOperationException({ decoder.detectedCharset(); }) is null);
    assert(decoder.onMalformedInput(CodingErrorAction.IGNORE) is decoder);
    assert(decoder.onUnmappableCharacter(CodingErrorAction.REPLACE) is decoder);
    assert(decoder.malformedInputAction() == CodingErrorAction.IGNORE);
    assert(decoder.unmappableCharacterAction() == CodingErrorAction.REPLACE);
}

@("CharsetDecoder.replaceWith counts UTF-16 units and treats a null string as empty (R14, R26)")
unittest
{
    auto decoder = new AsciiDecoder(1, 1);
    assert(messageOf!IllegalArgumentException({ decoder.replaceWith(null); }) == "Empty replacement");
    assert(messageOf!IllegalArgumentException({ decoder.replaceWith(""); }) == "Empty replacement");
    assert(messageOf!IllegalArgumentException({ decoder.replaceWith("ab"); }) == "Replacement too long");
    assert(messageOf!IllegalArgumentException({ decoder.replaceWith("\U0001F600"); }) == "Replacement too long");
    assert(decoder.replaceWith("\u00e9") is decoder && decoder.replacement() == "\u00e9");
    assert(new AsciiDecoder(1, 2).replaceWith("ab").replacement() == "ab");
    assert(new AsciiDecoder(1, 2).replaceWith("\U0001F600").replacement() == "\U0001F600");
}

@("CharsetEncoder replacement: default '?', validated, copied in and out")
unittest
{
    auto encoder = new AsciiEncoder;
    assert(encoder.replacement() == bytes('?'));
    assert(encoder.malformedInputAction() == CodingErrorAction.REPORT);
    assert(encoder.unmappableCharacterAction() == CodingErrorAction.REPORT);

    assert(messageOf!IllegalArgumentException({ new AsciiEncoder(1, 1, []); }) == "Empty replacement");
    assert(messageOf!IllegalArgumentException({ new AsciiEncoder(1, 1, null); }) == "Empty replacement");
    assert(messageOf!IllegalArgumentException({ new AsciiEncoder(1, 1, bytes(0x80)); }) == "Illegal replacement");
    assert(messageOf!IllegalArgumentException({ new AsciiEncoder(1, 1, bytes(1, 2)); }) == "Replacement too long");

    auto source = bytes(1, 2);
    auto wide = new AsciiEncoder(1, 2, source);
    source[0] = 9;
    assert(wide.replacement() == bytes(1, 2));
    wide.replacement()[0] = 9;
    assert(wide.replacement() == bytes(1, 2));
    assert(wide.replaceWith(bytes('*')) is wide && wide.replacement() == bytes('*'));
    assert(messageOf!IllegalArgumentException({ wide.replaceWith(bytes(0xff)); }) == "Illegal replacement");
    assert(wide.replacement() == bytes('*'));
}

@("CharsetEncoder.isLegalReplacement decodes with the charset's standard decoder under REPORT")
unittest
{
    static immutable ubyte[][] cases = [
        [0x3f], [0x7f], [0x80], [0xff], [0xc3, 0xa9], [0xc0, 0x80], [0xc2], [0xe0, 0x80, 0x80],
        [0xe0, 0xa0, 0x80], [0xed, 0x9f, 0xbf], [0xed, 0xa0, 0x80], [0xf0, 0x90, 0x80, 0x80],
        [0xf4, 0x8f, 0xbf, 0xbf], [0xf4, 0x90, 0x80, 0x80], [0xf5, 0x80, 0x80, 0x80], [0xe2, 0x82],
        [0x00, 0x3f], [0x3f, 0x00], [0xff, 0xfd], [0xfd, 0xff], [0xd8, 0x00, 0xdc, 0x00],
        [0x00, 0xd8, 0x00, 0xdc], [0xd8, 0x00], [0xdc, 0x00], [0x00, 0xdc], [0xfe, 0xff], [
            0xff, 0xfe
        ], [0xff, 0xfe, 0x00, 0xd8, 0x00, 0xdc], [0xfe, 0xff, 0xd8, 0x00, 0xdc, 0x00],
        [0xff, 0xfe, 0xd8, 0x00], [0xd8, 0x00, 0x00, 0x41], [0x00, 0x41, 0x00],
    ];
    // legal-replacement-oracle.log, Temurin 21.0.13+9.
    const table = [
        StandardCharsets.US_ASCII: "TTFFFFFFFFFFFFFFTTFFFFFFFFFFFFFT",
        StandardCharsets.ISO_8859_1: "TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT",
        StandardCharsets.UTF_8: "TTFFTFFFTTFTTFFFTTFFFFFFFFFFFFFT",
        StandardCharsets.UTF_16: "FFFFTTFFFFFTTTTTTTTTTTFFTTTTTTFF",
        StandardCharsets.UTF_16BE: "FFFFTTFFFFFTTTTTTTTTTTFFTTTTTFFF",
        StandardCharsets.UTF_16LE: "FFFFTTFFFFFTTTTTTTTTTTTTFTTTTTTF",
    ];
    foreach (cs, want; table)
    {
        const isUtf16 = cs == StandardCharsets.UTF_16 || cs == StandardCharsets.UTF_16BE
            || cs == StandardCharsets.UTF_16LE;
        auto encoder = new AsciiEncoder(cs, isUtf16 ? bytes(0, 0x3f) : bytes(0x3f));
        foreach (i, c; cases)
            assert(encoder.isLegalReplacement(cast(const(byte)[]) c) == (want[i] == 'T'), cs.name());
    }
}

@("CharsetEncoder for a null charset throws NullPointerException; a decoder keeps it")
unittest
{
    assert(collectException!NullPointerException(new AsciiEncoder(Charset.init, bytes('?'))) !is null);
    auto decoder = new class CharsetDecoder
    {
        this()
        {
            super(Charset.init, 1, 1);
        }

        protected override CoderResult decodeLoop(ByteBuffer in_, CharBuffer out_)
        {
            return CoderResult.UNDERFLOW;
        }
    };
    assert(decoder.charset() == Charset.init);
}

@("CharsetEncoder construction for UTF-16 rejects the default '?' replacement")
unittest
{
    foreach (cs; [StandardCharsets.UTF_16, StandardCharsets.UTF_16BE])
        assert(messageOf!IllegalArgumentException({ new AsciiEncoder(cs, bytes('?')); }) == "Illegal replacement");
}

@("CharsetEncoder constructor consults an overridden isLegalReplacement and implReplaceWith")
unittest
{
    static final class Permissive : AsciiEncoder
    {
        int legalityChecks;

        this()
        {
            super(1, 1, bytes(0xff));
        }

        override bool isLegalReplacement(scope const(byte)[] repl)
        {
            ++legalityChecks;
            return true;
        }
    }

    auto encoder = new Permissive;
    assert(encoder.legalityChecks == 1 && encoder.replacement() == bytes(0xff));
    auto shift = new ShiftEncoder;
    assert(shift.calls == ["implReplaceWith"]);
}

private string run(Coder)(Coder coder, string sequence)
{
    string result;
    for (size_t i = 0; i < sequence.length; ++i)
    {
        string step;
        switch (sequence[i])
        {
        case 'C':
            const eoi = sequence[++i] == 't';
            static if (is(Coder : CharsetDecoder))
                step = coder.decode(ByteBuffer.allocate(0), CharBuffer.allocate(0), eoi).toString().idup;
            else
                step = coder.encode(CharBuffer.allocate(0), ByteBuffer.allocate(0), eoi).toString().idup;
            break;
        case 'F':
            static if (is(Coder : CharsetDecoder))
                step = coder.flush(CharBuffer.allocate(0)).toString().idup;
            else
                step = coder.flush(ByteBuffer.allocate(0)).toString().idup;
            break;
        default:
            coder.reset();
            step = "reset";
        }
        result ~= (result.length ? " " : "") ~ step;
    }
    return result;
}

@("decode, encode, flush and reset follow Java's state machine and IllegalStateException messages")
unittest
{
    static struct Step
    {
        string sequence, outcome;
    }

    static immutable Step[] steps = [
        Step("F", "!Current state = RESET, new state = FLUSHED"), Step("Ct", "UNDERFLOW"),
        Step("CtF", "UNDERFLOW UNDERFLOW"), Step("CtFF", "UNDERFLOW UNDERFLOW UNDERFLOW"),
        Step("CtFCf", "!Current state = FLUSHED, new state = CODING"),
        Step("CtFCt", "!Current state = FLUSHED, new state = CODING_END"),
        Step("CfCt", "UNDERFLOW UNDERFLOW"),
        Step("CtCf", "!Current state = CODING_END, new state = CODING"),
        Step("CtCt", "UNDERFLOW UNDERFLOW"), Step("CtFR", "UNDERFLOW UNDERFLOW reset"),
        Step("CtFRCf", "UNDERFLOW UNDERFLOW reset UNDERFLOW"),
        Step("CfF", "!Current state = CODING, new state = FLUSHED"), Step("Cf", "UNDERFLOW"),
        Step("RF", "!Current state = RESET, new state = FLUSHED"),
        Step("CtRCt", "UNDERFLOW reset UNDERFLOW"), Step("CtRCf", "UNDERFLOW reset UNDERFLOW"),
        Step("CtFRF", "!Current state = RESET, new state = FLUSHED"),
    ];
    foreach (step; steps)
    {
        foreach (useDecoder; [true, false])
        {
            string outcome;
            const failure = collectException!IllegalStateException(outcome = useDecoder
                    ? run(new AsciiDecoder, step.sequence) : run(new AsciiEncoder, step.sequence));
            if (failure !is null)
                outcome = "!" ~ failure.msg.idup;
            assert(outcome == step.outcome, step.sequence ~ ": " ~ outcome);
        }
    }
}

@("decode applies REPORT, IGNORE and REPLACE to malformed input")
unittest
{
    static immutable wstring[3] expected = ["a"w, "ab"w, "a\uFFFDb"w];
    foreach (i, action; [
        CodingErrorAction.REPORT, CodingErrorAction.IGNORE, CodingErrorAction.REPLACE
    ])
    {
        auto decoder = new AsciiDecoder;
        decoder.onMalformedInput(action);
        auto input = ByteBuffer.wrap(bytes(0x61, 0xff, 0x62));
        auto output = CharBuffer.allocate(8);
        const result = decoder.decode(input, output, true);
        assert(result == (i == 0 ? CoderResult.malformedForLength(1) : CoderResult.UNDERFLOW));
        assert(input.position() == (i == 0 ? 1 : 3));
        assert(writtenChars(output) == expected[i]);
    }
}

@("encode applies REPORT, IGNORE and REPLACE to unmappable characters")
unittest
{
    static immutable ubyte[][3] expected = [[97], [97, 98], [97, 63, 98]];
    foreach (i, action; [
        CodingErrorAction.REPORT, CodingErrorAction.IGNORE, CodingErrorAction.REPLACE
    ])
    {
        auto encoder = new AsciiEncoder;
        encoder.onUnmappableCharacter(action);
        auto input = CharBuffer.wrap("a\u00e9b"w.dup);
        auto output = ByteBuffer.allocate(8);
        const result = encoder.encode(input, output, true);
        assert(result == (i == 0 ? CoderResult.unmappableForLength(1) : CoderResult.UNDERFLOW));
        assert(input.position() == (i == 0 ? 1 : 3));
        assert(written(output) == cast(const(byte)[]) expected[i]);
    }
}

@("REPLACE without room for the replacement returns OVERFLOW and consumes nothing")
unittest
{
    static final class NoCheckDecoder : CharsetDecoder
    {
        this()
        {
            super(StandardCharsets.US_ASCII, 1, 2);
        }

        protected override CoderResult decodeLoop(ByteBuffer in_, CharBuffer out_)
        {
            return CoderResult.malformedForLength(1);
        }
    }

    auto decoder = new NoCheckDecoder;
    decoder.onMalformedInput(CodingErrorAction.REPLACE).replaceWith("xy");
    auto input = ByteBuffer.wrap(bytes(0xff));
    auto output = CharBuffer.allocate(1);
    assert(decoder.decode(input, output, true) == CoderResult.OVERFLOW);
    assert(input.position() == 0 && output.position() == 0);

    auto oracle = new AsciiDecoder;
    oracle.onMalformedInput(CodingErrorAction.REPLACE);
    auto oracleInput = ByteBuffer.wrap(bytes(0xff));
    assert(oracle.decode(oracleInput, CharBuffer.allocate(0), true) == CoderResult.OVERFLOW);
    assert(oracleInput.position() == 0);
}

@("input left behind at end of input is malformed for its remaining length")
unittest
{
    auto input = ByteBuffer.wrap(bytes(1, 2));
    assert(new StallingDecoder().decode(input, CharBuffer.allocate(4), true) == CoderResult.malformedForLength(2));
    assert(input.position() == 0);

    auto more = ByteBuffer.wrap(bytes(1, 2));
    assert(new StallingDecoder().decode(more, CharBuffer.allocate(4), false) == CoderResult.UNDERFLOW);

    auto ignoring = new StallingDecoder;
    ignoring.onMalformedInput(CodingErrorAction.IGNORE);
    auto skipped = ByteBuffer.wrap(bytes(1, 2));
    assert(ignoring.decode(skipped, CharBuffer.allocate(4), true) == CoderResult.UNDERFLOW);
    assert(skipped.position() == 2);
}

@("a RuntimeException from the loop is wrapped in CoderMalfunctionError; other exceptions are not")
unittest
{
    auto boom = new IllegalStateException("boom");
    auto error = collectException!CoderMalfunctionError(new ThrowingDecoder(boom)
            .decode(ByteBuffer.allocate(1), CharBuffer.allocate(1), true));
    assert(error !is null && error.getCause() is boom);
    assert(error.getMessage() == "flint.java.lang.IllegalStateException: boom");

    auto overflow = new BufferOverflowException();
    error = collectException!CoderMalfunctionError(new ThrowingDecoder(overflow)
            .decode(ByteBuffer.allocate(1), CharBuffer.allocate(1), true));
    assert(error !is null && error.getCause() is overflow);

    auto encoded = collectException!CoderMalfunctionError(new ThrowingEncoder()
            .encode(CharBuffer.allocate(1), ByteBuffer.allocate(1), true));
    assert(encoded !is null && cast(IllegalStateException) encoded.getCause() !is null);

    auto checked = new Exception("checked");
    const raw = collectException(new ThrowingDecoder(checked).decode(ByteBuffer.allocate(1),
            CharBuffer.allocate(1), true));
    assert(raw is checked);
}

@("null buffers fail as CoderMalfunctionError caused by NullPointerException (R8)")
unittest
{
    auto decoded = collectException!CoderMalfunctionError(new AsciiDecoder().decode(null, null, true));
    assert(decoded !is null && cast(NullPointerException) decoded.getCause() !is null);
    decoded = collectException!CoderMalfunctionError(new AsciiDecoder().decode(ByteBuffer.allocate(1), null, true));
    assert(decoded !is null && cast(NullPointerException) decoded.getCause() !is null);
    auto encoded = collectException!CoderMalfunctionError(new AsciiEncoder().encode(CharBuffer.allocate(1),
            null, false));
    assert(encoded !is null && cast(NullPointerException) encoded.getCause() !is null);
    assert(collectException!NullPointerException(new AsciiEncoder().canEncode(cast(CharBuffer) null)) !is null);
}

@("canEncode runs a REPORT encoding, then restores the actions and resets")
unittest
{
    auto encoder = new AsciiEncoder;
    assert(encoder.canEncode('a'));
    assert(!encoder.canEncode('\u00e9'));
    assert(encoder.canEncode("ab"));
    assert(!encoder.canEncode("ab\u00e9"));
    assert(encoder.canEncode(""));
    assert(encoder.canEncode(cast(string) null));

    encoder.onUnmappableCharacter(CodingErrorAction.REPLACE);
    assert(!encoder.canEncode('\u00e9'));
    assert(encoder.unmappableCharacterAction() == CodingErrorAction.REPLACE);

    auto buffer = CharBuffer.wrap("x\u00e9"w.dup);
    assert(!encoder.canEncode(buffer));
    assert(buffer.position() == 0);
    buffer.position(1);
    assert(!encoder.canEncode(buffer));
    buffer.limit(1);
    assert(encoder.canEncode(buffer));

    // After a completed operation canEncode resets; during one it refuses.
    assert(encoder.encode(CharBuffer.allocate(0), ByteBuffer.allocate(0), true).isUnderflow());
    assert(encoder.flush(ByteBuffer.allocate(0)).isUnderflow());
    assert(encoder.canEncode('a'));
    assert(encoder.encode(CharBuffer.allocate(0), ByteBuffer.allocate(0), false).isUnderflow());
    const coding = messageOf!IllegalStateException({ encoder.canEncode('a'); });
    assert(coding == "Current state = CODING, new state = CODING");
    encoder.reset();
    assert(encoder.encode(CharBuffer.allocate(0), ByteBuffer.allocate(0), true).isUnderflow());
    const ended = messageOf!IllegalStateException({ encoder.canEncode("a"); });
    assert(ended == "Current state = CODING_END, new state = CODING");
}

@("canEncode grows its output past a zero-capacity estimate and flushes")
unittest
{
    auto shift = new ShiftEncoder;
    shift.calls = null;
    assert(shift.canEncode("a\u3001b"));
    assert(shift.calls.length > 0 && shift.calls[$ - 1] == "implReset");
    bool flushed;
    foreach (call; shift.calls)
        flushed |= call == "implFlush";
    assert(flushed);

    auto sparse = new AsciiEncoder(0.01f, 1);
    assert(sparse.canEncode("abcdefgh"));
    assert(!sparse.canEncode("abcdefg\u00e9"));
}

@("flush can return OVERFLOW repeatedly and then complete in a larger buffer")
unittest
{
    auto encoder = new ShiftEncoder;
    auto input = CharBuffer.wrap("\u3001"w.dup);
    auto output = ByteBuffer.allocate(6);
    assert(encoder.encode(input, output, true).isUnderflow());
    assert(!input.hasRemaining());
    assert(written(output) == bytes(0x1b, '$', 'B', 0x30, 0x01));

    assert(encoder.flush(output).isOverflow());
    assert(encoder.flush(output).isOverflow());
    assert(output.position() == 5);

    auto larger = ByteBuffer.allocate(2 * output.capacity() + 10);
    output.flip();
    larger.put(output);
    assert(encoder.flush(larger).isUnderflow());
    assert(written(larger) == bytes(0x1b, '$', 'B', 0x30, 0x01, 0x1b, '(', 'B'));

    encoder.calls = null;
    assert(encoder.flush(larger).isUnderflow());
    assert(encoder.flush(larger).isUnderflow());
    assert(encoder.calls.length == 0 && larger.position() == 8);
}

@("the impl hooks report replacement, action and reset changes")
unittest
{
    auto encoder = new ShiftEncoder;
    encoder.calls = null;
    encoder.onMalformedInput(CodingErrorAction.IGNORE);
    encoder.onUnmappableCharacter(CodingErrorAction.REPLACE);
    encoder.replaceWith(bytes('!'));
    encoder.reset();
    assert(encoder.calls == [
        "implOnMalformedInput IGNORE", "implOnUnmappableCharacter REPLACE", "implReplaceWith",
        "implReset"
    ]);
}
