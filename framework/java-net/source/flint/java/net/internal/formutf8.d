/** Java form escape scanning and UTF-8 decoding. */
module flint.java.net.internal.formutf8;

import flint.engine.aot.text : decodeUtf8;
import flint.java.lang : IllegalArgumentException;
import flint.java.lang.character.decimaldigits : javaDecimalDigit;

@safe:

package(flint.java.net):

string decodeFormUtf8(string input) pure
{
    return decodeFormRuns(input, (scope const(char)[] run, scope char[] output) => writeDecodedRun(run, output));
}

alias FormRunDecoder = size_t delegate(scope const(char)[], scope char[]) @safe pure nothrow @nogc;

string decodeFormRuns(string input, scope FormRunDecoder decodeRun) pure
{
    size_t first;
    while (first < input.length && input[first] != '%' && input[first] != '+')
        ++first;
    if (first == input.length)
        return input;

    auto output = new char[input.length];
    output[0 .. first] = input[0 .. first];
    size_t written = first;
    char[] run;
    for (size_t position = first; position < input.length;)
    {
        if (input[position] != '%')
        {
            const byte_ = input[position++];
            output[written++] = byte_ == '+' ? ' ' : byte_;
            continue;
        }
        if (run is null && input.length >= 3)
            run = new char[input.length / 3];
        Digits digits;
        const count = readRun(input, position, run, digits);
        if (count < 0)
            throw escapeFailure(input, cast(int) count, digits);
        written += decodeRun(run[0 .. cast(size_t) count], output[written .. $]);
    }
    return output[0 .. written].idup;
}

private enum int invalidFirst = -1;
private enum int invalidSecond = -2;
private enum int negativeOctet = -3;
private enum int incompleteEscape = -4;

private struct Digits
{
    size_t first;
    size_t end;
    bool partialSurrogate;
}

private IllegalArgumentException escapeFailure(string text, int code, Digits digits) pure
{
    if (code == incompleteEscape)
        return new IllegalArgumentException("URLDecoder: Incomplete trailing escape (%) pattern");
    enum prefix = "URLDecoder: Illegal hex characters in escape (%) pattern - ";
    if (code == negativeOctet)
        return new IllegalArgumentException(prefix ~ "negative value");
    const index = code == invalidFirst ? "0" : "1";
    const half = digits.partialSurrogate ? "?" : "";
    return new IllegalArgumentException(
            prefix ~ "Error at index " ~ index ~ " in: \"" ~ text[digits.first .. digits.end] ~ half ~ "\"");
}

private ptrdiff_t readRun(scope string text, ref size_t index, scope char[] run, out Digits digits) pure nothrow @nogc
{
    size_t count;
    while (index < text.length && text[index] == '%')
    {
        const value = readOctet(text, index, digits);
        if (value < 0)
            return value;
        run[count++] = cast(char) value;
    }
    return cast(ptrdiff_t) count;
}

private int readOctet(scope const(char)[] text, ref size_t position, out Digits digits) pure nothrow @nogc
{
    digits.first = ++position;
    if (text.length - position < 2)
        return incompleteEscape;
    const first = decodeUtf8(text, position);
    if (first > 0xFFFF)
    {
        digits.end = position;
        return invalidFirst;
    }
    if (position == text.length)
        return incompleteEscape;

    const secondStart = position;
    const second = decodeUtf8(text, position);
    digits.partialSurrogate = second > 0xFFFF;
    digits.end = digits.partialSurrogate ? secondStart : position;
    return signedOctet(first, hexDigit(second));
}

private int signedOctet(dchar first, int second) pure nothrow @nogc
{
    const high = hexDigit(first);
    if (high < 0 && first != '+' && first != '-')
        return invalidFirst;
    if (second < 0)
        return invalidSecond;
    if (first == '-')
        return second == 0 ? 0 : negativeOctet;
    if (first == '+')
        return second;
    return high * 16 + second;
}

private int hexDigit(dchar point) pure nothrow @nogc
{
    if (point >= '0' && point <= '9')
        return cast(int)(point - '0');
    const lower = point | 0x20;
    if (lower >= 'a' && lower <= 'f')
        return cast(int)(lower - 'a') + 10;
    if (point >= 0xFF21 && point <= 0xFF26)
        return cast(int)(point - 0xFF21) + 10;
    if (point >= 0xFF41 && point <= 0xFF46)
        return cast(int)(point - 0xFF41) + 10;
    const digit = javaDecimalDigit(point);
    return digit == uint.max ? -1 : cast(int) digit;
}

private size_t writeDecodedRun(scope const(char)[] run, scope char[] output) pure nothrow @nogc
{
    size_t written;
    while (run.length != 0)
    {
        bool scalar;
        const width = decodePrefix(run, scalar);
        const text = scalar ? run[0 .. width] : "�";
        output[written .. written + text.length] = text;
        written += text.length;
        run = run[width .. $];
    }
    return written;
}

// The Java decoder consumes a structurally valid surrogate triple as one malformed unit. Other invalid
// first and second bytes each consume only the lead, and a following non-continuation stays unread.
private size_t decodePrefix(scope const(char)[] run, out bool scalar) pure nothrow @nogc
{
    const first = run[0];
    if (first < 0x80)
    {
        scalar = true;
        return 1;
    }
    if (first < 0xC2 || first > 0xF4 || run.length < 2 || !validSecond(first, run[1]))
        return 1;

    const width = first < 0xE0 ? 2 : first < 0xF0 ? 3 : 4;
    size_t end = 2;
    while (end < width && end < run.length && continuation(run[end]))
        ++end;
    scalar = end == width && (first != 0xED || run[1] < 0xA0);
    return end;
}

private bool continuation(char value) pure nothrow @nogc
{
    return (value & 0xC0) == 0x80;
}

private bool validSecond(char first, char second) pure nothrow @nogc
{
    return continuation(second) && (first != 0xE0 || second >= 0xA0) && (first != 0xF0 || second >= 0x90)
        && (first != 0xF4 || second <= 0x8F);
}
