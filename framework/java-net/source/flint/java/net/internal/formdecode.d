/** Java application/x-www-form-urlencoded decoding. */
module flint.java.net.internal.formdecode;

import flint.engine.aot.text : utf8Length;
import flint.java.net.internal.formcharset : Mode, isSingleByte, representation;
import flint.java.net.internal.formutf8 : decodeFormRuns, decodeFormUtf8;
import flint.java.nio.charset : Charset, StandardCharsets;

@safe:

package(flint.java.net):

string decodeForm(string input, Charset charset) pure
{
    if (charset == StandardCharsets.UTF_8)
        return decodeFormUtf8(input);
    const mode = representation(charset);
    return decodeFormRuns(input, (scope const(char)[] run, scope char[] output) => isSingleByte(mode)
            ? decodeSingleByte(run, mode, output) : decodeUtf16(run, mode, output));
}

private size_t decodeSingleByte(scope const(char)[] run, Mode mode, scope char[] output) pure nothrow @nogc
{
    size_t written;
    foreach (byte_; run)
    {
        const point = mode == Mode.ascii && byte_ >= 0x80 ? 0xFFFD : cast(dchar) byte_;
        written += putUtf8(output[written .. $], point);
    }
    return written;
}

private size_t decodeUtf16(scope const(char)[] run, Mode mode, scope char[] output) pure nothrow @nogc
{
    bool little = mode == Mode.littleEndian;
    if (mode == Mode.utf16 && run.length >= 2)
    {
        const marker = readWord(run, false);
        little = marker == 0xFFFE;
        if (marker == 0xFEFF || little)
            run = run[2 .. $];
    }

    size_t written;
    while (run.length != 0)
    {
        const point = consumeUtf16(run, little);
        written += putUtf8(output[written .. $], point);
    }
    return written;
}

private dchar consumeUtf16(ref scope const(char)[] run, bool little) pure nothrow @nogc
{
    const first = consumeWord(run, little);
    if (first >= 0xD800 && first <= 0xDBFF)
    {
        const second = consumeWord(run, little);
        if (second >= 0xDC00 && second <= 0xDFFF)
            return cast(dchar)(0x10000 + ((first - 0xD800) << 10) + (second - 0xDC00));
        return 0xFFFD;
    }
    if (first >= 0xDC00 && first <= 0xDFFF)
        return 0xFFFD;
    return cast(dchar) first;
}

private uint consumeWord(ref scope const(char)[] run, bool little) pure nothrow @nogc
{
    if (run.length < 2)
    {
        run = null;
        return 0xFFFD;
    }
    const word = readWord(run, little);
    run = run[2 .. $];
    return word;
}

private uint readWord(scope const(char)[] bytes, bool little) pure nothrow @nogc
{
    return little ? bytes[0] | (cast(uint) bytes[1] << 8) : (cast(uint) bytes[0] << 8) | bytes[1];
}

private size_t putUtf8(scope char[] output, dchar point) pure nothrow @nogc
{
    static immutable ubyte[5] head = [0, 0, 0xC0, 0xE0, 0xF0];
    const length = utf8Length(point);
    for (auto i = length - 1; i != 0; --i)
    {
        output[i] = cast(char)(0x80 | (point & 0x3F));
        point >>= 6;
    }
    output[0] = cast(char)(head[length] | point);
    return length;
}
