/// Locale-independent decimal conversion for IEEE 754 binary32 and binary64.
module flint.serde.internal.decimal;

import flint.arena : Status;
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

    void scaleFive(uint power) nothrow @nogc
    {
        while (power >= 13)
        {
            multiplyAdd(1_220_703_125);
            power -= 13;
        }
        foreach (index; 0 .. power)
            multiplyAdd(5);
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

    uint divide(uint divisor) nothrow @nogc
    {
        ulong remainder;
        foreach_reverse (index; 0 .. length)
        {
            remainder = (remainder << 32) | words[index];
            words[index] = cast(uint)(remainder / divisor);
            remainder %= divisor;
        }
        normalize();
        return cast(uint) remainder;
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
    ulong raw;
    if (!readBits(token, binary64, raw))
        return false;
    DoubleBits parts;
    parts.raw = raw;
    value = parts.value;
    return true;
}

/// Emit an exact decimal representation of one finite binary32 value.
void writeDecimal(ref scope Writer writer, float value, bool toml = false) nothrow @nogc
{
    SingleBits parts;
    parts.value = value;
    writeBits(writer, parts.raw, binary32, toml);
}

/// Emit an exact decimal representation of one finite binary64 value.
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

    ulong significand = raw & format.fractionMask();
    int exponent = format.minimumExponent();
    if (expBits != 0)
    {
        exponent = cast(int) expBits - format.bias;
        significand |= 1UL << format.fractionBits;
    }
    if (significand == 0)
    {
        writer.append(cast(const(ubyte)[])(toml ? "0.0" : "0"));
        return;
    }

    exponent -= cast(int) format.fractionBits;
    auto coefficient = Natural(significand);
    if (exponent >= 0)
    {
        coefficient.shift(cast(uint) exponent);
        exponent = 0;
    }
    else
        coefficient.scaleFive(cast(uint)-exponent);

    ubyte[significantLimit] digits;
    size_t first = digits.length;
    do
    {
        uint remainder = coefficient.divide(decimalChunk);
        if (coefficient.length == 0)
        {
            do
            {
                digits[--first] = cast(ubyte)('0' + remainder % 10);
                remainder /= 10;
            }
            while (remainder != 0);
        }
        else
        {
            foreach (index; 0 .. 9)
            {
                digits[--first] = cast(ubyte)('0' + remainder % 10);
                remainder /= 10;
            }
        }
    }
    while (coefficient.length != 0);

    immutable point = cast(int)(digits.length - first) + exponent;
    size_t end = digits.length;
    while (end > first + 1 && digits[end - 1] == '0')
        --end;
    writeDigits(writer, digits[first .. end], point, toml);
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
