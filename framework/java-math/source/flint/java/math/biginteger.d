/// Immutable arbitrary-precision integers (Java SE 21, rules R1, R5, R7, R8 and R11).
module flint.java.math.biginteger;

import flint.java.lang : ArithmeticException, Comparable, IndexOutOfBoundsException, JavaObject,
    NullPointerException, NumberFormatException;
import flint.java.lang.number : Number;
import flint.java.math.internal.division : divideByWord, divideWords;
import flint.java.math.internal.floating : roundedFloating;
import flint.java.math.internal.limbs : combineLimbs, compareLimbs, firstNonzeroLimb, loadLimbs,
    magnitudeBitLength, signedLength, significantBytes, significantLimbs, storeSignedBytes;
import flint.java.math.internal.products : multiplyLimbs;
import flint.java.math.internal.radix : formatRadix;

@safe:

/// A signed integer with an owned, normalized magnitude.
class BigInteger : Number, Comparable!BigInteger
{
    mixin JavaObject;

    private const(uint)[] magnitude;
    private int sign;

    /// Decode a big-endian two's-complement representation.
    this(scope const(byte)[] value)
    {
        this(value, 0, cast(int) value.length);
    }

    /// Decode a big-endian two's-complement representation in the selected byte range.
    this(scope const(byte)[] value, int offset, int length)
    {
        if (!value.length)
            throw new NumberFormatException("Zero length BigInteger");
        const bytes = byteRange(value, offset, length);
        const bool negative = bytes.length && bytes[0] < 0;
        magnitude = decode(bytes, negative);
        sign = magnitude.length ? (negative ? -1 : 1) : 0;
    }

    /// Decode a separate sign and a big-endian, unsigned magnitude.
    this(int signum, scope const(byte)[] value)
    {
        this(signum, value, 0, cast(int) value.length);
    }

    /// Decode the sign and the selected range of a big-endian, unsigned magnitude.
    this(int signum, scope const(byte)[] value, int offset, int length)
    {
        if (signum < -1 || signum > 1)
            throw new NumberFormatException("Invalid signum value");
        magnitude = decode(byteRange(value, offset, length), false);
        if (signum == 0 && magnitude.length)
            throw new NumberFormatException("signum-magnitude mismatch");
        sign = magnitude.length ? signum : 0;
    }

    private this(const(uint)[] words, int sign)
    {
        const length = significantLimbs(words);
        checkRange(words[0 .. length]);
        this.magnitude = words[0 .. length];
        this.sign = length ? sign : 0;
    }

    /// Construct an integer from a signed 64-bit value.
    static BigInteger valueOf(long value) pure nothrow
    {
        return new BigInteger(value);
    }

    private this(long value) pure nothrow
    {
        if (!value)
            return;
        sign = value < 0 ? -1 : 1;
        const ulong absolute = value < 0 ? 0UL - cast(ulong) value : cast(ulong) value;
        const uint high = cast(uint)(absolute >> 32);
        auto words = new uint[high ? 2 : 1];
        words[0] = cast(uint) absolute;
        if (high)
            words[1] = high;
        magnitude = words;
    }

    /// Return -1, 0, or 1 for a negative, zero, or positive value.
    int signum() const pure nothrow @nogc
    {
        return sign;
    }

    /// Return the bit length of the shortest two's-complement representation without its sign bit.
    int bitLength() const scope pure nothrow @nogc
    {
        const int bits = cast(int) magnitudeBitLength(magnitude);
        return bits - (sign < 0 && hasSingleMagnitudeBit());
    }

    /// Return the low 64 bits in two's complement.
    override long longValue() const pure nothrow @nogc
    {
        const ulong low = lowMagnitude();
        return cast(long)(sign < 0 ? 0UL - low : low);
    }

    /// Return the low 32 bits in two's complement.
    override int intValue() const pure nothrow @nogc
    {
        const uint low = magnitude.length ? magnitude[0] : 0;
        return cast(int)(sign < 0 ? 0U - low : low);
    }

    /// Return the low 16 bits in two's complement.
    override short shortValue() const pure nothrow @nogc
    {
        return cast(short) intValue();
    }

    /// Return the low eight bits in two's complement.
    override byte byteValue() const pure nothrow @nogc
    {
        return cast(byte) intValue();
    }

    /// Convert to binary32, rounding once at the target precision.
    override float floatValue() const pure nothrow @nogc
    {
        return cast(float) roundedFloating(magnitude, sign < 0, 24, 128);
    }

    /// Convert to binary64, rounding halfway values to even.
    override double doubleValue() const pure nothrow @nogc
    {
        return roundedFloating(magnitude, sign < 0, 53, 1_024);
    }

    /// Convert to a long, throwing on overflow.
    long longValueExact() const
    {
        return checkedValue(long.max, "BigInteger out of long range");
    }

    /// Convert to an int, throwing on overflow.
    int intValueExact() const
    {
        return cast(int) checkedValue(int.max, "BigInteger out of int range");
    }

    /// Convert to a short, throwing on overflow.
    short shortValueExact() const
    {
        return cast(short) checkedValue(short.max, "BigInteger out of short range");
    }

    /// Convert to a byte, throwing on overflow.
    byte byteValueExact() const
    {
        return cast(byte) checkedValue(byte.max, "BigInteger out of byte range");
    }

    private long checkedValue(ulong positiveLimit, string message) const
    {
        const ulong low = lowMagnitude();
        if (magnitude.length > 2 || low > positiveLimit + (sign < 0))
            throw new ArithmeticException(message);
        return cast(long)(sign < 0 ? 0UL - low : low);
    }

    private ulong lowMagnitude() const pure nothrow @nogc
    {
        if (!magnitude.length)
            return 0;
        const ulong high = magnitude.length > 1 ? magnitude[1] : 0;
        return (high << 32) | magnitude[0];
    }

    /// Return the signed decimal text.
    override string toString() const pure nothrow
    {
        return formatRadix(magnitude, sign < 0, 10);
    }

    /// Return signed text in radix 2 to 36, with decimal for a radix outside that range.
    string toString(int radix) const pure nothrow
    {
        return formatRadix(magnitude, sign < 0, radix);
    }

    /// Return a fresh, minimal big-endian two's-complement byte array.
    byte[] toByteArray() const pure nothrow
    {
        const bool negative = sign < 0;
        const size_t first = negative ? firstNonzeroLimb(magnitude) : 0;
        auto bytes = new byte[signedLength(magnitude, negative, first)];
        storeSignedBytes(bytes, magnitude, negative, first);
        return bytes;
    }

    /// Compare the signed values.
    override int compareTo(BigInteger other)
    {
        if (other is null)
            throw new NullPointerException();
        if (sign != other.sign)
            return sign < other.sign ? -1 : 1;
        return sign * compareLimbs(magnitude, other.magnitude);
    }

    /// Compare the numeric value with another BigInteger.
    bool equals(scope const Object other) const pure nothrow @nogc
    {
        const value = cast(const BigInteger) other;
        return value !is null && sign == value.sign && compareLimbs(magnitude, value.magnitude) == 0;
    }

    /// Fold the magnitude words from most to least significant, with 32-bit wraparound.
    int hashCode() const pure nothrow @nogc
    {
        uint hash;
        foreach_reverse (word; magnitude)
            hash = 31U * hash + word;
        return cast(int)(sign < 0 ? 0U - hash : hash);
    }

    /// Return the absolute value.
    BigInteger abs()
    {
        return sign < 0 ? negate() : this;
    }

    /// Reverse the sign and share the owned magnitude.
    BigInteger negate()
    {
        return sign == 0 ? this : new BigInteger(magnitude, -sign);
    }

    /// Return the lesser operand by signed comparison.
    BigInteger min(BigInteger other)
    {
        return compareTo(other) <= 0 ? this : other;
    }

    /// Return the greater operand by signed comparison.
    BigInteger max(BigInteger other)
    {
        return compareTo(other) >= 0 ? this : other;
    }

    /// Return the exact sum.
    BigInteger add(BigInteger other)
    {
        if (other is null)
            throw new NullPointerException();
        if (!sign)
            return other;
        return combine(other.magnitude, other.sign);
    }

    /// Return the exact difference.
    BigInteger subtract(BigInteger other)
    {
        if (other is null)
            throw new NullPointerException();
        return combine(other.magnitude, -other.sign);
    }

    /// Return the exact product.
    BigInteger multiply(BigInteger other)
    {
        if (other is null)
            throw new NullPointerException();
        if (!sign)
            return this;
        if (!other.sign)
            return other;
        return new BigInteger(multiplyWords(magnitude, other.magnitude), sign * other.sign);
    }

    /// Raise this integer to a nonnegative exponent.
    BigInteger pow(int exponent)
    {
        if (exponent < 0)
            throw new ArithmeticException("Negative exponent");
        if (exponent == 0)
            return valueOf(1);
        if (exponent == 1 || !sign)
            return this;

        const ulong topBit = cast(ulong)(magnitudeBitLength(magnitude) - 1) * exponent;
        if (topBit >= int.max)
            throw new ArithmeticException("BigInteger exceeds supported range");
        const int resultSign = sign < 0 && (exponent & 1) ? -1 : 1;
        if (topBit == 0)
            return sign == resultSign ? this : valueOf(1);

        if (hasSingleMagnitudeBit())
        {
            auto words = new uint[cast(size_t)(topBit / 32 + 1)];
            words[$ - 1] = 1U << (topBit % 32);
            return new BigInteger(words, resultSign);
        }

        return new BigInteger(powerMagnitude(magnitude, cast(uint) exponent), resultSign);
    }

    // Both callers have a nonzero magnitude. Share the scan in their linked code.
    pragma(inline, false) private bool hasSingleMagnitudeBit() const scope pure nothrow @nogc
    {
        const uint high = magnitude[$ - 1];
        return (high & (high - 1)) == 0 && firstNonzeroLimb(magnitude) + 1 == magnitude.length;
    }

    /// Divide with truncation toward zero.
    BigInteger divide(BigInteger other)
    {
        return divideTo(other, true, false).quotient;
    }

    /// Return the remainder with the sign of this integer.
    BigInteger remainder(BigInteger other)
    {
        return divideTo(other, false, true).remainder;
    }

    /// Return the nonnegative remainder for a strictly positive modulus.
    BigInteger mod(BigInteger modulus)
    {
        if (modulus is null || modulus.sign <= 0)
            failDivision(modulus, "BigInteger: modulus not positive");
        auto rest = remainder(modulus);
        return rest.sign < 0 ? rest.add(modulus) : rest;
    }

    /// Return the quotient followed by the remainder.
    BigInteger[] divideAndRemainder(BigInteger other)
    {
        auto result = divideTo(other, true, true);
        return [result.quotient, result.remainder];
    }

    private struct Division
    {
        BigInteger quotient;
        BigInteger remainder;
    }

    private Division divideTo(BigInteger other, bool wantQuotient, bool wantRemainder)
    {
        if (other is null || !other.sign)
            failDivision(other, "BigInteger divide by zero");

        const int order = compareLimbs(magnitude, other.magnitude);
        const int quotientSign = sign * other.sign;
        Division result;
        if (order <= 0)
        {
            if (wantQuotient)
                result.quotient = valueOf(order < 0 ? 0 : quotientSign);
            if (wantRemainder)
                result.remainder = order < 0 ? this : valueOf(0);
            return result;
        }

        auto quotient = wantQuotient ? new uint[magnitude.length - other.magnitude.length + 1] : null;
        const divisor = other.magnitude;
        if (divisor.length == 1)
        {
            const uint rest = divideByWord(quotient, magnitude, divisor[0]);
            if (wantRemainder)
                result.remainder = valueOf(cast(long) rest * sign);
        }
        else
        {
            result.remainder = divideLarge(quotient, divisor, wantRemainder);
        }
        if (wantQuotient)
            result.quotient = new BigInteger(quotient, quotientSign);
        return result;
    }

    pragma(inline, false) private static void failDivision(scope const BigInteger divisor, string message)
    {
        if (divisor is null)
            throw new NullPointerException();
        throw new ArithmeticException(message);
    }

    private BigInteger divideLarge(scope uint[] quotient, scope const(uint)[] divisor, bool wantRemainder)
    {
        uint[32] smallNumerator = void;
        uint[32] smallDivisor = void;
        const size_t length = magnitude.length + 1;
        scope uint[] work = length <= smallNumerator.length ? smallNumerator[0 .. length] : new uint[length];
        scope uint[] normalized = divisor.length <= smallDivisor.length
            ? smallDivisor[0 .. divisor.length] : new uint[divisor.length];
        divideWords(quotient, work, normalized, magnitude, divisor);
        if (!wantRemainder)
            return null;
        const size_t remaining = significantLimbs(work[0 .. divisor.length]);
        auto owned = new uint[remaining];
        owned[] = work[0 .. remaining];
        return new BigInteger(owned, sign);
    }

    private BigInteger combine(const(uint)[] other, int otherSign)
    {
        if (!otherSign)
            return this;
        if (!sign)
            return new BigInteger(other, otherSign);
        const bool adding = sign == otherSign;
        const int order = adding ? (magnitude.length < other.length ? -1 : 1) : compareLimbs(magnitude, other);
        const high = order < 0 ? other : magnitude;
        const low = order < 0 ? magnitude : other;
        if (!order)
            return new BigInteger(cast(const(uint)[]) null, 0);
        auto words = new uint[high.length + adding];
        combineLimbs(words, high, low, !adding);
        return new BigInteger(words, order < 0 ? otherSign : sign);
    }
}

private uint[] multiplyWords(scope const(uint)[] left, scope const(uint)[] right)
{
    const size_t length = left.length + right.length;
    if (length > maxLimbs + 1)
        throw new ArithmeticException("BigInteger exceeds supported range");
    auto product = new uint[length];
    multiplyLimbs(product, left, right);
    return product;
}

private const(uint)[] checkedProduct(scope const(uint)[] left, scope const(uint)[] right)
{
    const words = multiplyWords(left, right);
    const result = words[0 .. significantLimbs(words)];
    checkRange(result);
    return result;
}

private const(uint)[] powerMagnitude(return scope const(uint)[] factor, uint exponent)
{
    const(uint)[] result;
    for (uint remaining = exponent; remaining; remaining >>= 1)
    {
        if (remaining & 1)
            result = result.length ? checkedProduct(result, factor) : factor;
        if (remaining > 1)
            factor = checkedProduct(factor, factor);
    }
    return result;
}

private const(byte)[] byteRange(return scope const(byte)[] bytes, int offset, int length)
{
    if (offset < 0 || length < 0 || offset > bytes.length || length > bytes.length - offset)
        throw new IndexOutOfBoundsException();
    return bytes[offset .. offset + cast(size_t) length];
}

private const(uint)[] decode(scope const(byte)[] value, bool negative)
{
    const bytes = significantBytes(value, negative);
    const size_t length = bytes.length / 4 + (bytes.length % 4 != 0);
    if (length > maxLimbs)
        throw new ArithmeticException("BigInteger exceeds supported range");
    auto words = new uint[length];
    loadLimbs(words, bytes, negative);
    checkRange(words);
    return words[0 .. significantLimbs(words)];
}

private enum size_t maxLimbs = (cast(size_t) int.max + 31) / 32;

private void checkRange(scope const(uint)[] words)
{
    if (words.length > maxLimbs || (words.length == maxLimbs && words[$ - 1] > int.max))
        throw new ArithmeticException("BigInteger exceeds supported range");
}
