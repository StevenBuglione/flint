/// Unsigned-word arithmetic and signed byte conversion for BigInteger.
module flint.java.math.internal.limbs;

import core.bitop : bsr;

@safe:

package(flint.java.math):

/// Return the length of a magnitude without leading zero words.
size_t significantLimbs(scope const(uint)[] words) pure nothrow @nogc
{
    foreach_reverse (i, word; words)
        if (word)
            return i + 1;
    return 0;
}

/// Return the width of a normalized magnitude in bits.
size_t magnitudeBitLength(scope const(uint)[] words) pure nothrow @nogc
{
    if (!words.length)
        return 0;
    size_t leading = words.length;
    --leading;
    return leading * 32 + 1 + bsr(words[leading]);
}

/// Compare normalized magnitudes from their most significant words.
int compareLimbs(scope const(uint)[] left, scope const(uint)[] right) pure nothrow @nogc
{
    if (left.length > right.length)
        return 1;
    if (left.length < right.length)
        return -1;

    foreach_reverse (i, word; left)
    {
        const uint other = right[i];
        if (word < other)
            return -1;
        if (word > other)
            return 1;
    }
    return 0;
}

/// Combine magnitudes in descending length order. Addition reserves a final carry word.
void combineLimbs(scope uint[] dest, scope const(uint)[] left, scope const(uint)[] right, bool minus) pure nothrow @nogc
{
    // For subtraction add the two's complement of the shorter input, including its sign extension.
    const uint extension = minus ? uint.max : 0;
    ulong carry = minus;
    foreach (i, word; left)
    {
        const uint other = i < right.length ? right[i] : 0;
        const ulong total = cast(ulong) word + (other ^ extension) + carry;
        dest[i] = cast(uint) total;
        carry = total >> 32;
    }
    if (!minus)
        dest[left.length] = cast(uint) carry;
}

/// Return the input suffix that contributes to the signed value or unsigned magnitude.
const(byte)[] significantBytes(return scope const(byte)[] bytes, bool negative) pure nothrow @nogc
{
    if (!negative)
    {
        foreach (i, octet; bytes)
            if (octet)
                return bytes[i .. $];
        return bytes[$ .. $];
    }

    foreach (i, octet; bytes[0 .. $ - 1])
        if (octet != -1 || bytes[i + 1] >= 0)
            return bytes[i .. $];
    return bytes[$ - 1 .. $];
}

/// Decode big-endian input into little-endian words.
void loadLimbs(scope uint[] words, scope const(byte)[] bytes, bool negative) pure nothrow @nogc
{
    const uint padding = negative ? uint.max : 0;
    uint carry = negative;
    size_t remaining = bytes.length;
    foreach (ref word; words)
    {
        uint packed;
        uint bits;
        do
        {
            --remaining;
            packed |= cast(uint) cast(ubyte) bytes[remaining] << bits;
            bits += 8;
        }
        while (remaining && bits < 32);
        // Sign extension is only needed at the most significant, partial word.
        if (bits < 32)
            packed |= padding << bits;
        word = (packed ^ padding) + carry;
        carry &= word == 0;
    }
}

/// Find the first nonzero word from the least significant end.
size_t firstNonzeroLimb(scope const(uint)[] words) pure nothrow @nogc
{
    foreach (i, word; words)
        if (word)
            return i;
    return words.length;
}

/// Return the byte length including a sign bit.
size_t signedLength(scope const(uint)[] words, bool negative, size_t firstNonzero) pure nothrow @nogc
{
    if (!words.length)
        return 1;
    size_t leading = words.length;
    --leading;
    uint word = words[leading];
    if (negative && firstNonzero == leading)
        --word;
    const size_t leadingBits = word ? 1 + bsr(word) : 0;
    return leading * 4 + leadingBits / 8 + 1;
}

/// Write the minimal big-endian two's-complement bytes, including sign extension.
void storeSignedBytes(scope byte[] bytes, scope const(uint)[] words, bool negative, size_t first) pure nothrow @nogc
{
    size_t end = bytes.length;
    foreach (i, limb; words)
    {
        const uint mask = negative && i >= first ? uint.max : 0;
        uint word = (limb ^ mask) + (negative && i == first);
        uint count = 4;
        do
        {
            --end;
            bytes[end] = cast(byte) word;
            word >>= 8;
            --count;
        }
        while (end && count);
    }
    if (end)
        bytes[0] = negative ? -1 : 0;
}
