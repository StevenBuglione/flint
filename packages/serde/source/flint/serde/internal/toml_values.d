/// TOML scalar grammar, checked integer conversion and explicit calendar values.
module flint.serde.internal.toml_values;

import flint.arena : Status;
import flint.serde.internal.decimal : parseDecimal;
import flint.serde.internal.types : TomlDate, TomlDateTime, TomlTime;
import flint.serde.internal.writer : Writer;

@safe:

/// Valid scalar kinds retained in the document token tree.
enum ScalarKind : ubyte
{
    invalid,
    text,
    boolean,
    integer,
    fraction,
    date,
    time,
    datetime
}

private bool same(scope const(ubyte)[] value, string expected) nothrow @nogc
{
    if (value.length != expected.length)
        return false;
    foreach (index, byteValue; value)
    {
        if (byteValue != expected[index])
            return false;
    }
    return true;
}

private uint digitValue(ubyte byteValue) nothrow @nogc
{
    if (byteValue >= '0' && byteValue <= '9')
        return byteValue - '0';
    if (byteValue >= 'a' && byteValue <= 'f')
        return byteValue - 'a' + 10;
    if (byteValue >= 'A' && byteValue <= 'F')
        return byteValue - 'A' + 10;
    return uint.max;
}

private bool digits(scope const(ubyte)[] bytes, ref size_t offset, uint base, out size_t count) nothrow @nogc
{
    if (offset == bytes.length || digitValue(bytes[offset]) >= base)
        return false;
    for (;;)
    {
        ++offset;
        ++count;
        if (offset == bytes.length)
            break;
        if (bytes[offset] == '_')
        {
            ++offset;
            if (offset == bytes.length || digitValue(bytes[offset]) >= base)
                return false;
        }
        else if (digitValue(bytes[offset]) >= base)
            break;
    }
    return true;
}

private struct Special
{
    bool negative;
    bool nan;
    bool valid;
}

private Special specialFloat(scope const(ubyte)[] bytes) nothrow @nogc
{
    if (bytes.length == 0)
        return Special.init;
    const negative = bytes[0] == '-';
    const hasSign = negative || bytes[0] == '+';
    scope spelling = bytes[hasSign ? 1 : 0 .. $];
    const nan = same(spelling, "nan");
    return Special(negative, nan, nan || same(spelling, "inf"));
}

private ScalarKind numberKind(scope const(ubyte)[] bytes) nothrow @nogc
{
    if (specialFloat(bytes).valid)
        return ScalarKind.fraction;
    if (!decimalSyntax(bytes))
        return ScalarKind.invalid;
    double[1] parsed = [0.0];
    return parseDecimal(bytes, parsed[0]) ? ScalarKind.fraction : ScalarKind.invalid;
}

private bool decimalSyntax(scope const(ubyte)[] bytes) nothrow @nogc
{
    size_t offset;
    if (bytes[0] == '+' || bytes[0] == '-')
        ++offset;
    immutable firstDigit = offset;
    size_t count;
    if (!digits(bytes, offset, 10, count))
        return false;
    if (count != 1 && bytes[firstDigit] == '0')
        return false;

    bool floating;
    if (offset < bytes.length && bytes[offset] == '.')
    {
        floating = true;
        ++offset;
        if (!digits(bytes, offset, 10, count))
            return false;
    }
    if (offset == bytes.length)
        return floating;
    return exponentSyntax(bytes, offset);
}

private bool exponentSyntax(scope const(ubyte)[] bytes, size_t offset) nothrow @nogc
{
    if (bytes[offset] != 'e' && bytes[offset] != 'E')
        return false;
    ++offset;
    if (offset < bytes.length && (bytes[offset] == '+' || bytes[offset] == '-'))
        ++offset;
    size_t count;
    return digits(bytes, offset, 10, count) && offset == bytes.length;
}

/// Convert a TOML signed 64-bit integer in its permitted base.
bool integerValue(scope const(ubyte)[] bytes, out long value) nothrow @nogc
{
    if (bytes.length == 0)
        return false;
    immutable negative = bytes[0] == '-';
    immutable hasSign = negative || bytes[0] == '+';
    size_t offset = hasSign ? 1 : 0;
    const base = hasSign ? 10 : integerRadix(bytes);
    if (base != 10)
        offset += 2;

    immutable start = offset;
    size_t count;
    if (!digits(bytes, offset, base, count) || offset != bytes.length)
        return false;
    if (base == 10 && bytes[start] == '0' && count > 1)
        return false;
    ulong[1] parsed;
    const limit = cast(ulong) long.max + (negative ? 1UL : 0);
    if (!magnitude(bytes[start .. $], base, limit, parsed[0]))
        return false;
    const valueBits = parsed[0];
    value = negative && valueBits != 0 ? -cast(long)(valueBits - 1) - 1 : cast(long) valueBits;
    return true;
}

private bool magnitude(scope const(ubyte)[] digits, uint base, ulong limit, out ulong value) nothrow @nogc
{
    foreach (byteValue; digits)
    {
        if (byteValue == '_')
            continue;
        const digit = digitValue(byteValue);
        if (value > (limit - digit) / base)
            return false;
        value = value * base + digit;
    }
    return true;
}

private uint integerRadix(scope const(ubyte)[] bytes) nothrow @nogc
{
    if (bytes.length <= 2 || bytes[0] != '0')
        return 10;
    switch (bytes[1])
    {
    case 'b':
        return 2;
    case 'o':
        return 8;
    case 'x':
        return 16;
    default:
        return 10;
    }
}

/// Convert a validated TOML fraction or explicit infinity or NaN.
bool floatingValue(T)(scope const(ubyte)[] bytes, out T value) nothrow @nogc
        if (is(T == float) || is(T == double))
{
    const special = specialFloat(bytes);
    if (special.valid)
    {
        value = special.nan ? T.nan : T.infinity;
        if (special.negative)
            value = -value;
        return true;
    }
    return parseDecimal(bytes, value);
}

/// Convert a validated TOML boolean.
bool booleanValue(scope const(ubyte)[] bytes) nothrow @nogc
{
    return same(bytes, "true");
}

private bool smallUnsigned(scope const(ubyte)[] bytes, out uint value) nothrow @nogc
{
    foreach (byteValue; bytes)
    {
        if (byteValue < '0' || byteValue > '9')
            return false;
        value = value * 10 + byteValue - '0';
    }
    return true;
}

private bool validCalendar(TomlDate date) nothrow @nogc
{
    if (date.year > 9_999 || date.month == 0 || date.month > 12 || date.day == 0)
        return false;
    immutable ubyte[12] days = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
    const leap = date.year % 4 == 0 && (date.year % 100 != 0 || date.year % 400 == 0);
    return date.day <= days[date.month - 1] + (date.month == 2 && leap ? 1 : 0);
}

private bool validClock(TomlTime time) nothrow @nogc
{
    return time.hour <= 23 && time.minute <= 59 && time.second <= 60 && time.nanosecond < 1_000_000_000;
}

/// Parse a TOML local calendar date.
bool dateValue(scope const(ubyte)[] bytes, out TomlDate date) nothrow @nogc
{
    if (bytes.length != 10 || bytes[4] != '-' || bytes[7] != '-')
        return false;
    uint[3] parts;
    if (!smallUnsigned(bytes[0 .. 4], parts[0]) || !smallUnsigned(bytes[5 .. 7], parts[1])
            || !smallUnsigned(bytes[8 .. 10], parts[2]))
        return false;
    date = TomlDate(cast(ushort) parts[0], cast(ubyte) parts[1], cast(ubyte) parts[2]);
    return validCalendar(date);
}

private bool prefixTime(scope const(ubyte)[] bytes, out TomlTime time, out size_t used) nothrow @nogc
{
    if (bytes.length < 8 || bytes[2] != ':' || bytes[5] != ':')
        return false;
    uint[3] parts;
    if (!smallUnsigned(bytes[0 .. 2], parts[0]) || !smallUnsigned(bytes[3 .. 5], parts[1])
            || !smallUnsigned(bytes[6 .. 8], parts[2]))
        return false;
    used = 8;
    uint nanos;
    if (used < bytes.length && bytes[used] == '.')
    {
        immutable first = ++used;
        while (used < bytes.length && digitValue(bytes[used]) < 10)
        {
            if (used - first < 9)
                nanos = nanos * 10 + digitValue(bytes[used]);
            ++used;
        }
        if (used == first)
            return false;
        for (size_t padding = used - first; padding < 9; ++padding)
            nanos *= 10;
    }
    time = TomlTime(cast(ubyte) parts[0], cast(ubyte) parts[1], cast(ubyte) parts[2], nanos);
    return validClock(time);
}

/// Parse a TOML local clock value without a timezone.
bool timeValue(scope const(ubyte)[] bytes, out TomlTime time) nothrow @nogc
{
    size_t used;
    return prefixTime(bytes, time, used) && used == bytes.length;
}

/// Parse a TOML local or explicitly offset date and time.
bool datetimeValue(scope const(ubyte)[] bytes, out TomlDateTime timestamp) nothrow @nogc
{
    if (bytes.length < 19 || (bytes[10] != 'T' && bytes[10] != 't' && bytes[10] != ' ')
            || !dateValue(bytes[0 .. 10], timestamp.date))
        return false;
    size_t used;
    if (!prefixTime(bytes[11 .. $], timestamp.time, used))
        return false;
    return offsetValue(bytes[11 + used .. $], timestamp);
}

private bool offsetValue(scope const(ubyte)[] zone, ref TomlDateTime timestamp) nothrow @nogc
{
    if (zone.length == 0)
        return true;

    timestamp.hasOffset = true;
    if (zone.length == 1)
        return zone[0] == 'Z' || zone[0] == 'z';
    if (zone.length != 6 || (zone[0] != '+' && zone[0] != '-') || zone[3] != ':')
        return false;
    uint[2] hm;
    if (!smallUnsigned(zone[1 .. 3], hm[0]) || !smallUnsigned(zone[4 .. 6], hm[1]) || hm[0] > 23 || hm[1] > 59)
        return false;
    immutable magnitude = cast(short)(hm[0] * 60 + hm[1]);
    timestamp.offsetMinutes = cast(short)(zone[0] == '-' ? -magnitude : magnitude);
    return true;
}

/// Recognize one complete unquoted TOML scalar.
ScalarKind classify(scope const(ubyte)[] bytes) nothrow @nogc
{
    if (bytes.length == 0)
        return ScalarKind.invalid;
    if (same(bytes, "true") || same(bytes, "false"))
        return ScalarKind.boolean;
    if (bytes.length >= 10 && bytes[4] == '-' && bytes[7] == '-')
    {
        TomlDate date;
        if (dateValue(bytes, date))
            return ScalarKind.date;
        TomlDateTime timestamp;
        return datetimeValue(bytes, timestamp) ? ScalarKind.datetime : ScalarKind.invalid;
    }
    if (bytes.length >= 8 && bytes[2] == ':')
    {
        TomlTime time;
        return timeValue(bytes, time) ? ScalarKind.time : ScalarKind.invalid;
    }
    long[1] parsed;
    return integerValue(bytes, parsed[0]) ? ScalarKind.integer : numberKind(bytes);
}

private void fixedDigits(ref scope Writer writer, uint value, uint count) nothrow @nogc
{
    ubyte[9] output;
    foreach_reverse (index; 0 .. count)
    {
        output[index] = cast(ubyte)('0' + value % 10);
        value /= 10;
    }
    writer.append(output[0 .. count]);
}

/// Encode a validated local calendar date.
void emitDate(ref scope Writer writer, TomlDate value) nothrow @nogc
{
    if (!validCalendar(value))
    {
        writer.fail(Status.invalidArgument, "invalid TOML calendar date");
        return;
    }

    fixedDigits(writer, value.year, 4);
    writer.put('-');
    fixedDigits(writer, value.month, 2);
    writer.put('-');
    fixedDigits(writer, value.day, 2);
}

/// Encode a validated local clock value with its optional fractional second.
void emitTime(ref scope Writer writer, TomlTime value) nothrow @nogc
{
    if (!validClock(value))
    {
        writer.fail(Status.invalidArgument, "invalid TOML clock value");
        return;
    }
    fixedDigits(writer, value.hour, 2);
    writer.put(':');
    fixedDigits(writer, value.minute, 2);
    writer.put(':');
    fixedDigits(writer, value.second, 2);
    if (value.nanosecond != 0)
    {
        writer.put('.');
        uint fraction = value.nanosecond;
        uint digits = 9;
        while (fraction % 10 == 0)
        {
            fraction /= 10;
            --digits;
        }
        fixedDigits(writer, fraction, digits);
    }
}

/// Encode a local date and time and its explicit offset, when present.
void emitDatetime(ref scope Writer writer, TomlDateTime value) nothrow @nogc
{
    emitDate(writer, value.date);
    writer.put('T');
    emitTime(writer, value.time);
    if (!value.hasOffset)
        return;
    if (value.offsetMinutes < -1_439 || value.offsetMinutes > 1_439)
    {
        writer.fail(Status.invalidArgument, "invalid TOML timezone offset");
        return;
    }
    if (value.offsetMinutes == 0)
    {
        writer.put('Z');
        return;
    }

    immutable negative = value.offsetMinutes < 0;
    immutable magnitude = cast(uint)(negative ? -value.offsetMinutes : value.offsetMinutes);
    writer.put(negative ? '-' : '+');
    fixedDigits(writer, magnitude / 60, 2);
    writer.put(':');
    fixedDigits(writer, magnitude % 60, 2);
}
