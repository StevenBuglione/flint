module flint.log.encoding;

import flint.arena : Error, Result, Status;
import flint.log.types : Field, Format, Level, LogContext;

@safe:

package(flint.log) enum maxKeyBytes = 128;
package(flint.log) enum maximumRecord = 65_536;
private enum fieldHeaderBytes = 5;
private enum redacted = "[REDACTED]";
private enum timestampPattern = "0000-00-00T00:00:00.000Z";
private enum alphabet = "0123456789abcdef";
private immutable string[5] levels = ["trace", "debug", "info", "warn", "error"];
private immutable string[6] sensitive = [
    "authorization", "cookie", "password", "secret", "token", "api_key"
];

package(flint.log) struct RecordHeader
{
    Level level;
    LogContext context;
    ulong timestamp;
    uint messageBytes;
    uint fields;
    uint rawBytes;
    uint outputBytes;
}

private char normalized(char value) pure nothrow @nogc
{
    if (value >= 'A' && value <= 'Z')
        return cast(char)(value + 'a' - 'A');
    return value == '-' ? '_' : value;
}

private bool sameKey(scope const(char)[] left, scope const(char)[] right) pure nothrow @nogc
{
    if (left.length != right.length)
        return false;
    foreach (index, character; left)
        if (normalized(character) != normalized(right[index]))
            return false;
    return true;
}

package(flint.log) ubyte allowedMask(scope const(string)[] allowed) pure nothrow @nogc
{
    ubyte mask;
    foreach (index, candidate; sensitive)
        foreach (permission; allowed)
            if (sameKey(permission, candidate))
                mask |= cast(ubyte)(1U << index);
    return mask;
}

private bool hidden(scope const(char)[] key, ubyte allowed) pure nothrow @nogc
{
    foreach (index, candidate; sensitive)
        if (sameKey(key, candidate))
            return (allowed & (1U << index)) == 0;
    return false;
}

package(flint.log) bool validUtf8(scope const(char)[] input) pure nothrow @nogc
{
    enum block = 16;
    size_t index;
    while (index < input.length)
    {
        // Skip whole ASCII blocks; one combined test per block lets the compiler vectorize it.
        if (input.length - index >= block)
        {
            ubyte bits;
            foreach (character; input[index .. index + block])
                bits |= cast(ubyte) character;
            if (bits < 0x80)
            {
                index += block;
                continue;
            }
        }
        const lead = cast(ubyte) input[index++];
        if (lead < 0x80)
            continue;
        if (!scalar(input, lead, index))
            return false;
    }
    return true;
}

private bool scalar(scope const(char)[] input, ubyte lead, ref size_t index) pure nothrow @nogc
{
    if (lead < 0xC2 || lead > 0xF4)
        return false;

    uint value;
    uint minimum;
    uint count;
    if (lead < 0xE0)
    {
        value = lead & 0x1F;
        minimum = 0x80;
        count = 1;
    }
    else if (lead < 0xF0)
    {
        value = lead & 0x0F;
        minimum = 0x800;
        count = 2;
    }
    else
    {
        value = lead & 0x07;
        minimum = 0x1_0000;
        count = 3;
    }

    if (count > input.length - index)
        return false;
    foreach (_; 0 .. count)
    {
        const trail = cast(ubyte) input[index++];
        if ((trail & 0xC0) != 0x80)
            return false;
        value = (value << 6) | (trail & 0x3F);
    }
    return value >= minimum && value <= 0x10_FFFF && (value < 0xD800 || value > 0xDFFF);
}

private bool plain(char character) pure nothrow @nogc
{
    // Bitwise operators keep the test branch-free for the block loop below.
    return (character >= ' ') & (character != '"') & (character != '\\') & (character != 127);
}

/// Length of the longest prefix that JSON and console output copy without an escape.
private size_t plainPrefix(scope const(char)[] bytes) pure nothrow @nogc
{
    enum block = 16;
    size_t index;
    while (bytes.length - index >= block)
    {
        bool escaped;
        foreach (character; bytes[index .. index + block])
            escaped |= !plain(character);
        if (escaped)
            break;
        index += block;
    }
    while (index < bytes.length && plain(bytes[index]))
        ++index;
    return index;
}

private struct Line
{
    private char[] destination;
    size_t limit;
    size_t length;
    bool overflow;

    this(return scope char[] target) nothrow @nogc
    {
        destination = target;
        limit = target.length;
    }

    void append(scope const(char)[] bytes) scope nothrow @nogc
    {
        if (overflow)
            return;
        if (bytes.length > limit - length)
        {
            overflow = true;
            return;
        }
        if (destination !is null)
            destination[length .. length + bytes.length] = bytes;
        length += bytes.length;
    }

    void quoted(scope const(char)[] bytes) scope nothrow @nogc
    {
        append("\"");
        for (;;)
        {
            const run = plainPrefix(bytes);
            append(bytes[0 .. run]);
            if (run == bytes.length)
                break;
            escape(cast(ubyte) bytes[run]);
            bytes = bytes[run + 1 .. $];
        }
        append("\"");
    }

    private void escape(ubyte value) scope nothrow @nogc
    {
        if (value == '"' || value == '\\')
        {
            char[2] escaped = ['\\', cast(char) value];
            append(escaped[]);
        }
        else
        {
            char[6] escaped = ['\\', 'u', '0', '0', alphabet[value >> 4], alphabet[value & 15]];
            append(escaped[]);
        }
    }

    void decimal(ulong value, uint width = 0) scope nothrow @nogc
    {
        char[20] digits;
        size_t first = digits.length;
        do
        {
            digits[--first] = alphabet[value % 10];
            value /= 10;
        }
        while (value != 0 || digits.length - first < width);
        append(digits[first .. $]);
    }

    void hex(ulong value) scope nothrow @nogc
    {
        char[16] digits;
        foreach_reverse (ref digit; digits)
        {
            digit = alphabet[value & 15];
            value >>= 4;
        }
        append(digits[]);
    }

    void startRecord(Format mode, Level level, LogContext ctx, scope const(char)[] utc, ulong seq) scope nothrow @nogc
    {
        if (mode == Format.json)
        {
            append("{\"timestamp\":\"");
            append(utc);
            append("\",\"seq\":\"");
            decimal(seq, 20);
            append("\",\"level\":\"");
            append(levels[level]);
            append("\",\"requestId\":");
            decimal(ctx.requestId);
            append(",\"traceId\":\"");
            hex(ctx.traceIdHigh);
            hex(ctx.traceIdLow);
            append("\",\"spanId\":\"");
            hex(ctx.spanId);
            append("\",\"message\":");
        }
        else
        {
            append(utc);
            append(" ");
            append(levels[level]);
            append(" seq=");
            decimal(seq, 20);
            append(" requestId=");
            decimal(ctx.requestId);
            append(" traceId=");
            hex(ctx.traceIdHigh);
            hex(ctx.traceIdLow);
            append(" spanId=");
            hex(ctx.spanId);
            append(" message=");
        }
    }

    void startFields(Format format) scope nothrow @nogc
    {
        append(format == Format.json ? ",\"fields\":{" : " fields={");
    }

    void field(scope const(char)[] key, scope const(char)[] value, bool precedes) scope nothrow @nogc
    {
        if (precedes)
            append(",");
        quoted(key);
        append(":");
        quoted(value);
    }

    void endRecord(Format format) scope nothrow @nogc
    {
        append(format == Format.json ? "}}\n" : "}\n");
    }
}

package(flint.log) Result!RecordHeader measure(Format format, Level level, LogContext context,
        scope const(char)[] message, scope const(Field)[] fields, ubyte allowed, size_t limit) nothrow @nogc
{
    if (message.length > limit || fields.length > limit / fieldHeaderBytes)
        return tooLarge();
    if (!validUtf8(message))
        return Result!RecordHeader(RecordHeader.init, Error(Status.invalidArgument, "invalid message UTF-8"));

    scope Line line;
    line.limit = limit;
    line.startRecord(format, level, context, timestampPattern, 0);
    line.quoted(message);
    line.startFields(format);
    size_t rawBytes = message.length;
    foreach (index, ref field; fields)
    {
        const key = field.key;
        const value = hidden(key, allowed) ? redacted : field.value;
        if (value.length > limit || line.overflow)
            return tooLarge();
        if (key.length > maxKeyBytes || !validUtf8(key) || !validUtf8(value))
            return Result!RecordHeader(RecordHeader.init, Error(Status.invalidArgument, "invalid structured field"));

        rawBytes += fieldHeaderBytes + key.length + value.length;
        if (rawBytes > limit)
            return tooLarge();
        line.field(key, value, index != 0);
    }
    line.endRecord(format);
    if (line.overflow)
        return tooLarge();
    return Result!RecordHeader(RecordHeader(level, context, 0, cast(uint) message.length,
            cast(uint) fields.length, cast(uint) rawBytes, cast(uint) line.length));
}

private Result!RecordHeader tooLarge() pure nothrow @nogc
{
    return Result!RecordHeader(RecordHeader.init, Error(Status.resourceExhausted, "log record exceeds maximum"));
}

package(flint.log) void capture(scope char[] raw, scope const(char)[] message, scope const(Field)[] fields,
        ubyte allowed) nothrow @nogc
{
    raw[0 .. message.length] = message;
    size_t cursor = message.length;
    foreach (ref field; fields)
    {
        const key = field.key;
        const value = hidden(key, allowed) ? redacted : field.value;
        raw[cursor++] = cast(char) key.length;
        foreach (shift; 0 .. 4)
            raw[cursor++] = cast(char)((value.length >> (shift * 8)) & 255);
        raw[cursor .. cursor + key.length] = key;
        cursor += key.length;
        raw[cursor .. cursor + value.length] = value;
        cursor += value.length;
    }
    assert(cursor == raw.length);
}

private void fixedDigits(scope char[] target, uint value) pure nothrow @nogc
{
    foreach_reverse (ref position; target)
    {
        position = alphabet[value % 10];
        value /= 10;
    }
}

/// Format UTC milliseconds since the epoch as RFC 3339 for years 1970 through 9999.
package(flint.log) bool utcText(ulong millis, out char[24] text) pure nothrow @nogc
{
    // Civil-from-days conversion (proleptic Gregorian) without the C library's time zone state.
    const seconds = millis / 1000;
    const shifted = seconds / 86_400 + 719_468;
    const era = shifted / 146_097;
    const dayOfEra = cast(uint)(shifted - era * 146_097);
    const yearOfEra = (dayOfEra - dayOfEra / 1460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365;
    const dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100);
    const monthIndex = (5 * dayOfYear + 2) / 153;
    const month = monthIndex < 10 ? monthIndex + 3 : monthIndex - 9;
    const year = era * 400 + yearOfEra + (month <= 2);
    if (year > 9999)
        return false;
    const clock = cast(uint)(seconds % 86_400);
    text[] = timestampPattern;
    fixedDigits(text[0 .. 4], cast(uint) year);
    fixedDigits(text[5 .. 7], month);
    fixedDigits(text[8 .. 10], dayOfYear - (153 * monthIndex + 2) / 5 + 1);
    fixedDigits(text[11 .. 13], clock / 3600);
    fixedDigits(text[14 .. 16], clock / 60 % 60);
    fixedDigits(text[17 .. 19], clock % 60);
    fixedDigits(text[20 .. 23], cast(uint)(millis % 1000));
    return true;
}

package(flint.log) Status formatRecord(Format format, RecordHeader header, scope const(char)[] raw,
        scope char[] output, ulong sequence) nothrow @nogc
{
    char[24] timestamp;
    if (!utcText(header.timestamp, timestamp))
        return Status.ioError;

    scope Line line = Line(output);
    line.startRecord(format, header.level, header.context, timestamp[], sequence);
    line.quoted(raw[0 .. header.messageBytes]);
    line.startFields(format);

    size_t cursor = header.messageBytes;
    foreach (index; 0 .. header.fields)
    {
        const keyBytes = cast(ubyte) raw[cursor++];
        uint valueBytes;
        foreach (shift; 0 .. 4)
            valueBytes |= cast(uint) cast(ubyte) raw[cursor++] << (shift * 8);
        const keyEnd = cursor + keyBytes;
        const valueEnd = keyEnd + valueBytes;
        line.field(raw[cursor .. keyEnd], raw[keyEnd .. valueEnd], index != 0);
        cursor = valueEnd;
    }
    line.endRecord(format);
    return line.length == header.outputBytes && !line.overflow ? Status.ok : Status.ioError;
}

@("block fast paths escape and validate a special byte at every block offset")
unittest
{
    import std.utf : UTFException, validate;

    static bool expectedUtf8(scope const(char)[] text)
    {
        try
            validate(text);
        catch (UTFException)
            return false;
        return true;
    }

    static string expectedQuote(scope const(char)[] text)
    {
        string result = "\"";
        foreach (character; text)
        {
            if (character == '"' || character == '\\')
                result ~= ['\\', character];
            else if (character < ' ' || character == 127)
                result ~= ['\\', 'u', '0', '0', alphabet[character >> 4], alphabet[character & 15]];
            else
                result ~= character;
        }
        return result ~ "\"";
    }

    immutable string[] specials = [
        "\"", "\\", "\n", "\x01", "\x1f", "\x7f", " ", "é", "€", "𝄞", "\x80", "\xC3",
        "\xC0\x80", "\xED\xA0\x80", "\xF4\x90\x80\x80", "\xE2\x82"
    ];
    char[16] lowBits = '\0';
    foreach (position; 0 .. lowBits.length)
    {
        lowBits[position] = '\x80';
        assert(!validUtf8(lowBits[]));
        lowBits[position] = '\x7f';
        assert(validUtf8(lowBits[]));
        lowBits[position] = '\0';
    }
    foreach (length; [1, 15, 16, 17, 31, 32, 33, 48])
        foreach (position; 0 .. length)
            foreach (special; specials)
            {
                char[] text = new char[length];
                text[] = 'x';
                text = text[0 .. position] ~ special ~ text[position .. $];
                assert(validUtf8(text) == expectedUtf8(text));
                char[512] buffer;
                auto line = Line(buffer[]);
                line.quoted(text);
                assert(!line.overflow && buffer[0 .. line.length] == expectedQuote(text));
                auto counted = Line(null);
                counted.limit = buffer.length;
                counted.quoted(text);
                assert(counted.length == line.length);
            }
}
