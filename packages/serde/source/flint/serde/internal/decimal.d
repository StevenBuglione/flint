/// Locale-independent decimal conversion for IEEE 754 binary32 and binary64.
module flint.serde.internal.decimal;

import flint.arena : Status;
import flint.serde.internal.shortest : shortest;
import flint.serde.internal.writer : Writer;

@safe:

// Midpoints of binary64 values terminate within 1,075 decimal places. Retaining
// 1,200 significant digits plus a discarded-nonzero flag resolves midpoint ties.
private enum significantLimit = 1_200;
private enum decimalChunk = 1_000_000_000U;

private struct Natural
{
    // Also holds the decimal denominator and binary normalization shifts.
    uint[168] words;
    size_t length;

    this(ulong value) nothrow @nogc
    {
        if (value == 0)
            return;
        words[0] = cast(uint) value;
        words[1] = cast(uint)(value >> 32);
        length = words[1] == 0 ? 1 : 2;
    }

    void multiplyAdd(uint factor, uint extra = 0) nothrow @nogc
    {
        ulong carry = extra;
        foreach (index; 0 .. length)
        {
            carry += cast(ulong) words[index] * factor;
            words[index] = cast(uint) carry;
            carry >>= 32;
        }
        if (carry != 0)
            words[length++] = cast(uint) carry;
    }

    void scaleTen(uint power) nothrow @nogc
    {
        while (power >= 9)
        {
            multiplyAdd(decimalChunk);
            power -= 9;
        }
        foreach (index; 0 .. power)
            multiplyAdd(10);
    }

    int bits() const nothrow @nogc
    {
        if (length == 0)
            return 0;
        int count = cast(int)(32 * (length - 1));
        for (uint top = words[length - 1]; top != 0; top >>= 1)
            ++count;
        return count;
    }

    void shift(uint distance) nothrow @nogc
    {
        if (length == 0 || distance == 0)
            return;
        immutable whole = distance / 32;
        immutable fraction = distance % 32;
        if (whole != 0)
        {
            foreach_reverse (index; 0 .. length)
                words[index + whole] = words[index];
            words[0 .. whole] = 0;
            length += whole;
        }
        if (fraction != 0)
        {
            ulong carry;
            foreach (index; whole .. length)
            {
                carry |= cast(ulong) words[index] << fraction;
                words[index] = cast(uint) carry;
                carry >>= 32;
            }
            if (carry != 0)
                words[length++] = cast(uint) carry;
        }
    }

    int compare(scope const ref Natural right) const nothrow @nogc
    {
        if (length != right.length)
            return length < right.length ? -1 : 1;
        foreach_reverse (index; 0 .. length)
        {
            if (words[index] != right.words[index])
                return words[index] < right.words[index] ? -1 : 1;
        }
        return 0;
    }

    void subtract(scope const ref Natural right) nothrow @nogc
    {
        ulong borrow;
        foreach (index; 0 .. length)
        {
            immutable subtrahend = (index < right.length ? right.words[index] : 0) + borrow;
            immutable original = words[index];
            words[index] = cast(uint)(original - subtrahend);
            borrow = original < subtrahend ? 1 : 0;
        }
        normalize();
    }

    private void normalize() nothrow @nogc
    {
        while (length != 0 && words[length - 1] == 0)
            --length;
    }
}

private struct Decimal
{
    Natural coefficient;
    int power;
    int digits;
    bool negative;
    bool beyondPrecision;
}

private Decimal collect(scope const(ubyte)[] token) nothrow @nogc
{
    Decimal decimal;
    size_t offset;
    if (token[0] == '-' || token[0] == '+')
    {
        decimal.negative = token[0] == '-';
        ++offset;
    }

    bool fractional;
    while (offset < token.length)
    {
        immutable letter = token[offset];
        if (letter == 'e' || letter == 'E')
            break;
        ++offset;
        if (letter == '.')
        {
            fractional = true;
            continue;
        }
        if (letter == '_')
            continue;
        if (fractional)
            --decimal.power;
        immutable digitValue = cast(uint)(letter - '0');
        if (decimal.digits == 0 && digitValue == 0)
            continue;
        if (decimal.digits < significantLimit)
        {
            decimal.coefficient.multiplyAdd(10, digitValue);
            ++decimal.digits;
        }
        else
        {
            ++decimal.power;
            if (digitValue != 0)
                decimal.beyondPrecision = true;
        }
    }
    if (offset != token.length)
        decimal.power += decimalExponent(token[offset + 1 .. $]);
    return decimal;
}

private int decimalExponent(scope const(ubyte)[] suffix) nothrow @nogc
{
    immutable negative = suffix[0] == '-';
    immutable signedSuffix = negative || suffix[0] == '+';
    int power;
    foreach (byteValue; suffix[signedSuffix ? 1 : 0 .. $])
    {
        if (byteValue == '_')
            continue;
        // The document is at most one MiB, so further digits cannot affect range.
        if (power >= 2_000_000)
            break;
        power = power * 10 + byteValue - '0';
    }
    return negative ? -power : power;
}

private struct IeeeFormat
{
    uint fractionBits;
    int bias;
    int decimalMaximum;
    int decimalMinimum;

    int minimumExponent() const nothrow @nogc
    {
        return 1 - bias;
    }

    ulong fractionMask() const nothrow @nogc
    {
        return (1UL << fractionBits) - 1;
    }

    ulong signMask() const nothrow @nogc
    {
        return (cast(ulong)(bias * 2 + 2)) << fractionBits;
    }

    uint exponentMask() const nothrow @nogc
    {
        return cast(uint)(bias * 2 + 1);
    }
}

private enum binary32 = IeeeFormat(23, 127, 38, -46);
private enum binary64 = IeeeFormat(52, 1023, 308, -324);

private bool readBits(scope const(ubyte)[] token, IeeeFormat format, out ulong bits) nothrow @nogc
{
    const decimal = collect(token);
    immutable sign = decimal.negative ? format.signMask() : 0;
    immutable power = decimal.power + decimal.digits - 1;
    if (decimal.digits == 0 || power < format.decimalMinimum)
    {
        bits = sign;
        return true;
    }
    if (power > format.decimalMaximum)
        return false;

    Natural numerator = decimal.coefficient;
    auto denominator = Natural(1);
    if (decimal.power < 0)
        denominator.scaleTen(cast(uint)-decimal.power);
    else
        numerator.scaleTen(cast(uint) decimal.power);

    int exponent = floorExponent(numerator, denominator);
    if (exponent > format.bias)
        return false;

    immutable minimum = format.minimumExponent();
    immutable shift = cast(int) format.fractionBits - (exponent < minimum ? minimum : exponent);
    if (shift >= 0)
        numerator.shift(cast(uint) shift);
    else
        denominator.shift(cast(uint)-shift);
    ulong significand = roundedQuotient(numerator, denominator, decimal.beyondPrecision);
    immutable implicitBit = 1UL << format.fractionBits;
    if (exponent < minimum)
    {
        // A rounded subnormal can reach the minimum normal value.
        bits = sign | significand;
        return true;
    }
    if (significand == implicitBit * 2)
    {
        significand >>= 1;
        if (++exponent > format.bias)
            return false;
    }
    bits = sign | (cast(ulong)(exponent + format.bias) << format.fractionBits) | (significand & format.fractionMask());
    return true;
}

private int floorExponent(scope const ref Natural numerator, scope const ref Natural denominator) nothrow @nogc
{
    immutable estimate = numerator.bits() - denominator.bits();
    if (estimate < 0)
    {
        Natural scaled = numerator;
        scaled.shift(cast(uint)-estimate);
        return scaled.compare(denominator) < 0 ? estimate - 1 : estimate;
    }
    Natural scaled = denominator;
    scaled.shift(cast(uint) estimate);
    return numerator.compare(scaled) < 0 ? estimate - 1 : estimate;
}

private ulong roundedQuotient(ref Natural dividend, scope const ref Natural divisor, bool sticky) nothrow @nogc
{
    ulong whole;
    for (int bit = dividend.bits() - divisor.bits(); bit >= 0; --bit)
    {
        Natural scale = divisor;
        scale.shift(cast(uint) bit);
        if (dividend.compare(scale) >= 0)
        {
            dividend.subtract(scale);
            whole |= 1UL << bit;
        }
    }

    dividend.shift(1);
    immutable comparison = dividend.compare(divisor);
    if (comparison > 0 || (comparison == 0 && (sticky || (whole & 1) != 0)))
        ++whole;
    return whole;
}

// Powers of ten that binary64 and binary32 represent exactly.
private static immutable double[23] exactPowers = [
    1e0, 1e1, 1e2, 1e3, 1e4, 1e5, 1e6, 1e7, 1e8, 1e9, 1e10, 1e11, 1e12, 1e13, 1e14, 1e15, 1e16,
    1e17, 1e18, 1e19, 1e20, 1e21, 1e22,
];
private static immutable float[11] exactSinglePowers = [
    1e0f, 1e1f, 1e2f, 1e3f, 1e4f, 1e5f, 1e6f, 1e7f, 1e8f, 1e9f, 1e10f
];

// A token whose significant digits fit in 64 bits: value = mantissa * 10^power.
private struct ShortDecimal
{
    ulong mantissa;
    int power;
    bool negative;
    bool fits;
}

private ShortDecimal shortDecimal(scope const(ubyte)[] token) nothrow @nogc
{
    ShortDecimal decimal;
    size_t offset;
    if (token[0] == '-' || token[0] == '+')
    {
        decimal.negative = token[0] == '-';
        ++offset;
    }
    uint digits;
    bool fractional;
    for (; offset < token.length; ++offset)
    {
        immutable letter = token[offset];
        if (letter == 'e' || letter == 'E')
            break;
        if (letter == '.')
        {
            fractional = true;
            continue;
        }
        if (letter == '_')
            continue;
        if (fractional)
            --decimal.power;
        if (digits == 0 && letter == '0')
            continue;
        if (++digits > 19)
            return decimal;
        decimal.mantissa = decimal.mantissa * 10 + (letter - '0');
    }
    if (offset != token.length)
        decimal.power += decimalExponent(token[offset + 1 .. $]);
    decimal.fits = true;
    return decimal;
}

// Clinger's fast path: an exact significand and an exact power of ten give one
// correctly rounded IEEE operation. Other inputs use the exact big-number path.
private bool fastDouble(scope const(ubyte)[] token, out double value) nothrow @nogc
{
    enum ulong exactLimit = 1UL << 53;
    const decimal = shortDecimal(token);
    if (!decimal.fits || decimal.mantissa > exactLimit)
        return false;
    if (decimal.mantissa == 0)
    {
        value = decimal.negative ? -0.0 : 0.0;
        return true;
    }
    if (decimal.power < -22)
        return false;
    ulong mantissa = decimal.mantissa;
    int power = decimal.power;
    // Move an excess power into the significand while the product stays exact.
    for (; power > 22; --power)
    {
        if (mantissa > exactLimit / 10)
            return false;
        mantissa *= 10;
    }
    double magnitude = mantissa;
    if (power < 0)
        magnitude /= exactPowers[-power];
    else
        magnitude *= exactPowers[power];
    value = decimal.negative ? -magnitude : magnitude;
    return true;
}

private bool fastSingle(scope const(ubyte)[] token, out float value) nothrow @nogc
{
    enum ulong exactLimit = 1UL << 53;
    const decimal = shortDecimal(token);
    if (!decimal.fits)
        return false;
    if (decimal.mantissa == 0)
    {
        value = decimal.negative ? -0.0f : 0.0f;
        return true;
    }
    if (decimal.power < -10)
        return false;
    float magnitude;
    if (decimal.mantissa <= (1UL << 24) && decimal.power <= 10)
    {
        // Wider evaluation of this one operation still rounds correctly (2 * 24 + 2 <= 53).
        magnitude = decimal.mantissa;
        if (decimal.power < 0)
            magnitude /= exactSinglePowers[-decimal.power];
        else
            magnitude *= exactSinglePowers[decimal.power];
    }
    else if (decimal.power >= 0 && decimal.mantissa <= exactLimit)
    {
        // An integer that binary64 holds exactly converts to binary32 with one rounding.
        ulong integer = decimal.mantissa;
        foreach (step; 0 .. decimal.power)
        {
            if (integer > exactLimit / 10)
                return false;
            integer *= 10;
        }
        immutable double exact = integer;
        magnitude = cast(float) exact;
    }
    else
        return false;
    value = decimal.negative ? -magnitude : magnitude;
    return true;
}

private union SingleBits
{
    uint raw;
    float value;
}

private union DoubleBits
{
    ulong raw;
    double value;
}

/// Convert a validated decimal number into the correctly rounded binary32 value.
bool parseDecimal(scope const(ubyte)[] token, out float value) nothrow @nogc
{
    if (fastSingle(token, value))
        return true;
    ulong raw;
    if (!readBits(token, binary32, raw))
        return false;
    SingleBits parts;
    parts.raw = cast(uint) raw;
    value = parts.value;
    return true;
}

/// Convert a validated decimal number into the correctly rounded binary64 value.
bool parseDecimal(scope const(ubyte)[] token, out double value) nothrow @nogc
{
    if (fastDouble(token, value))
        return true;
    ulong raw;
    if (!readBits(token, binary64, raw))
        return false;
    DoubleBits parts;
    parts.raw = raw;
    value = parts.value;
    return true;
}

/// Emit the shortest decimal that parses back to this finite binary32 value.
void writeDecimal(ref scope Writer writer, float value, bool toml = false) nothrow @nogc
{
    SingleBits parts;
    parts.value = value;
    writeBits(writer, parts.raw, binary32, toml);
}

/// Emit the shortest decimal that parses back to this finite binary64 value.
void writeDecimal(ref scope Writer writer, double value, bool toml = false) nothrow @nogc
{
    DoubleBits parts;
    parts.value = value;
    writeBits(writer, parts.raw, binary64, toml);
}

private void writeBits(ref scope Writer writer, ulong raw, IeeeFormat format, bool toml) nothrow @nogc
{
    immutable expBits = cast(uint)((raw >> format.fractionBits) & format.exponentMask());
    if (expBits == format.exponentMask())
    {
        if (toml)
        {
            if ((raw & format.signMask()) != 0)
                writer.put('-');
            writer.append(cast(const(ubyte)[])((raw & format.fractionMask()) == 0 ? "inf" : "nan"));
        }
        else
            writer.fail(Status.invalidArgument, "non-finite floating point value");
        return;
    }
    if ((raw & format.signMask()) != 0)
        writer.put('-');

    immutable fraction = raw & format.fractionMask();
    if (expBits == 0 && fraction == 0)
    {
        writer.append(cast(const(ubyte)[])(toml ? "0.0" : "0"));
        return;
    }

    const decimal = shortest(fraction, expBits, format.fractionBits, format.bias);
    ubyte[20] digits;
    size_t first = digits.length;
    ulong remaining = decimal.digits;
    do
    {
        digits[--first] = cast(ubyte)('0' + remaining % 10);
        remaining /= 10;
    }
    while (remaining != 0);
    immutable point = cast(int)(digits.length - first) + decimal.exponent;
    writeDigits(writer, digits[first .. $], point, toml);
}

private void writeDigits(ref scope Writer writer, scope const(ubyte)[] digits, int point, bool toml) nothrow @nogc
{
    if (point > 0 && point <= 21)
    {
        foreach (index; 0 .. point)
            writer.put(index < digits.length ? digits[index] : '0');
        if (point < digits.length)
        {
            writer.put('.');
            writer.append(digits[point .. $]);
        }
        else if (toml)
            writer.append(cast(const(ubyte)[]) ".0");
    }
    else if (point <= 0 && point > -6)
    {
        writer.append(cast(const(ubyte)[]) "0.");
        foreach (index; 0 .. -point)
            writer.put('0');
        writer.append(digits);
    }
    else
    {
        writer.put(digits[0]);
        if (digits.length > 1)
        {
            writer.put('.');
            writer.append(digits[1 .. $]);
        }
        writer.put('e');
        writer.signedNumber(point - 1);
    }
}

// Every input the fast paths accept converts to the same bits as the exact path.
unittest
{
    ubyte[48] buffer;
    const(ubyte)[] spell(ulong mantissa, int power, bool point, bool negative)
    {
        size_t length = buffer.length;
        immutable exponent = power;
        uint fraction = point ? cast(uint)(mantissa % 7) : 0;
        do
        {
            buffer[--length] = cast(ubyte)('0' + mantissa % 10);
            mantissa /= 10;
            if (fraction != 0 && --fraction == 0)
                buffer[--length] = '.';
        }
        while (mantissa != 0 || fraction != 0);
        if (buffer[length] == '.')
            buffer[--length] = '0';
        if (negative)
            buffer[--length] = '-';
        ubyte[16] suffix;
        size_t used;
        suffix[used++] = 'e';
        if (exponent < 0)
            suffix[used++] = '-';
        uint magnitude = exponent < 0 ? -exponent : exponent;
        ubyte[8] reversed;
        size_t count;
        do
        {
            reversed[count++] = cast(ubyte)('0' + magnitude % 10);
            magnitude /= 10;
        }
        while (magnitude != 0);
        while (count != 0)
            suffix[used++] = reversed[--count];
        // Shift left to make room for the exponent suffix.
        immutable start = length - used;
        foreach (index; length .. buffer.length)
            buffer[index - used] = buffer[index];
        foreach (index; 0 .. used)
            buffer[buffer.length - used + index] = suffix[index];
        return buffer[start .. $];
    }

    ulong state = 0x6a09_e667_f3bc_c909;
    uint fastDoubles;
    uint fastSingles;
    foreach (index; 0 .. 200_000)
    {
        state ^= state << 13;
        state ^= state >>> 7;
        state ^= state << 17;
        immutable ulong[4] ranges = [100, 16_777_217, 9_007_199_254_740_993, ulong.max];
        immutable mantissa = state % ranges[index % 4];
        immutable power = cast(int)((state >> 33) % 81) - 40;
        const token = spell(mantissa, power, (index & 4) != 0, (index & 8) != 0);
        ulong exact;
        double[1] wide;
        if (fastDouble(token, wide[0]))
        {
            ++fastDoubles;
            DoubleBits parts;
            parts.value = wide[0];
            assert(readBits(token, binary64, exact) && parts.raw == exact);
        }
        float[1] narrow;
        if (fastSingle(token, narrow[0]))
        {
            ++fastSingles;
            SingleBits parts;
            parts.value = narrow[0];
            assert(readBits(token, binary32, exact) && parts.raw == exact);
        }
    }
    assert(fastDoubles > 20_000 && fastSingles > 20_000);
}
