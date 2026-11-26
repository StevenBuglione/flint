/// Immutable arbitrary-precision integers (Java SE 21, rules R1, R5, R7, R8 and R11).
module flint.java.math.biginteger;

import flint.java.lang : ArithmeticException, Comparable, IndexOutOfBoundsException,
    NullPointerException, NumberFormatException;
import flint.java.math.internal.limbs : addLimbs, compareLimbs, firstNonzeroLimb, loadLimbs,
    signedLength, significantBytes, significantLimbs, storeSignedBytes, subtractLimbs;
import flint.java.math.internal.products : multiplyLimbs;

@safe:

/// A signed integer with an owned, normalized magnitude.
class BigInteger : Comparable!BigInteger
{
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

    /// Return -1, 0, or 1 for a negative, zero, or positive value.
    int signum() const pure nothrow @nogc
    {
        return sign;
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
        const size_t length = magnitude.length + other.magnitude.length;
        if (length > maxLimbs + 1)
            throw new ArithmeticException("BigInteger exceeds supported range");
        auto product = new uint[length];
        multiplyLimbs(product, magnitude, other.magnitude);
        return new BigInteger(product, sign * other.sign);
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
        if (adding)
        {
            auto sum = new uint[high.length + 1];
            addLimbs(sum, high, low);
            return new BigInteger(sum, sign);
        }
        if (!order)
            return new BigInteger(cast(const(uint)[]) null, 0);
        auto difference = new uint[high.length];
        subtractLimbs(difference, high, low);
        return new BigInteger(difference, order < 0 ? otherSign : sign);
    }
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
