/** Java application/x-www-form-urlencoded encoding. */
module flint.java.net.internal.formencode;

import flint.engine.aot.text : decodeUtf8;
import flint.java.lang : IllegalArgumentException;
import flint.java.net.internal.formcharset : Mode, isSingleByte, representation;
import flint.java.nio.charset : Charset, StandardCharsets;

@safe:

package(flint.java.net):

string encodeForm(string input, Charset charset) pure
{
    if (charset == StandardCharsets.UTF_8)
        return encodeFormUtf8(input);
    const mode = representation(charset);
    size_t unchanged;
    while (unchanged < input.length && formSafe(input[unchanged]))
        ++unchanged;
    if (unchanged == input.length)
        return input;
    if (input.length > size_t.max / 12)
        throw new IllegalArgumentException("Encoded form is too long");
    return encodeWithMode(input, mode, writeEncoded(input, mode, null));
}

string encodeFormUtf8(string input) pure
{
    size_t escaped;
    bool spaces;
    foreach (byte_; input)
    {
        if (byte_ == ' ')
            spaces = true;
        else if (!formSafe(byte_))
            ++escaped;
    }
    if (escaped == 0 && !spaces)
        return input;
    if (escaped > (size_t.max - input.length) / 2)
        throw new IllegalArgumentException("Encoded form is too long");

    return encodeUtf8Bytes(input, input.length + escaped * 2);
}

// The callers convert these fresh, strongly pure results to immutable slices.
private char[] encodeWithMode(string input, Mode mode, size_t length) pure
{
    auto output = new char[length];
    cast(void) writeEncoded(input, mode, output);
    return output;
}

private char[] encodeUtf8Bytes(string input, size_t length) pure
{
    auto output = new char[length];
    writeEncoding(input, output);
    return output;
}

private bool formSafe(char value) pure nothrow @nogc
{
    const lower = value | 0x20;
    return (lower >= 'a' && lower <= 'z') || (value >= '0' && value <= '9') || value == '.'
        || value == '-' || value == '_' || value == '*';
}

private void writeEncoding(scope const(char)[] input, scope char[] output) pure nothrow @nogc
{
    enum hex = "0123456789ABCDEF";
    size_t written;
    foreach (byte_; input)
    {
        if (formSafe(byte_))
            output[written++] = byte_;
        else if (byte_ == ' ')
            output[written++] = '+';
        else
        {
            output[written++] = '%';
            output[written++] = hex[byte_ >> 4];
            output[written++] = hex[byte_ & 15];
        }
    }
}

/// An empty output slice requests a size count.
private size_t writeEncoded(scope const(char)[] input, Mode mode, scope char[] output) pure nothrow @nogc
{
    size_t index, written;
    bool escaping;
    while (index < input.length)
    {
        const byte_ = input[index];
        if (formSafe(byte_) || byte_ == ' ')
        {
            put(output, written, byte_ == ' ' ? '+' : byte_);
            ++index;
            escaping = false;
            continue;
        }

        const scalar = decodeUtf8(input, index);
        if (isSingleByte(mode))
        {
            const limit = mode == Mode.ascii ? 0x7F : 0xFF;
            putEscape(output, written, scalar <= limit ? scalar : '?');
        }
        else
        {
            if (!escaping && mode == Mode.utf16)
                putWord(output, written, 0xFEFF, false);
            putUtf16(output, written, scalar, mode == Mode.littleEndian);
        }
        escaping = true;
    }
    return written;
}

private void put(scope char[] output, ref size_t position, char value) pure nothrow @nogc
{
    if (output.length != 0)
        output[position] = value;
    ++position;
}

private void putEscape(scope char[] output, ref size_t position, uint octet) pure nothrow @nogc
{
    enum hex = "0123456789ABCDEF";
    put(output, position, '%');
    put(output, position, hex[octet >> 4]);
    put(output, position, hex[octet & 15]);
}

private void putWord(scope char[] output, ref size_t position, uint word, bool little) pure nothrow @nogc
{
    const high = word >> 8;
    const low = word & 0xFF;
    putEscape(output, position, little ? low : high);
    putEscape(output, position, little ? high : low);
}

private void putUtf16(scope char[] output, ref size_t position, dchar scalar, bool little) pure nothrow @nogc
{
    if (scalar <= 0xFFFF)
        putWord(output, position, scalar, little);
    else
    {
        const offset = scalar - 0x10000;
        putWord(output, position, 0xD800 | (offset >> 10), little);
        putWord(output, position, 0xDC00 | (offset & 0x3FF), little);
    }
}
