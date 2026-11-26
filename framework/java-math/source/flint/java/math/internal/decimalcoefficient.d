/// Materialize the coefficient of a validated Java decimal value.
module flint.java.math.internal.decimalcoefficient;

import flint.java.math.biginteger : BigInteger;
import flint.java.math.internal.decimalparse : DecimalParts;
import flint.java.math.internal.radixparse : digitAt;

@safe:

package(flint.java.math):

/// Convert the scanner's compact value or coefficient range into an owned integer.
BigInteger materializeCoefficient(scope const(char)[] text, ref const DecimalParts parts)
{
    if (parts.isCompact)
        return BigInteger.valueOf(parts.compactValue);

    const coefficient = text[parts.coefficientStart .. parts.coefficientEnd];
    enum int blockDigits = 9;
    enum uint blockRadix = 1_000_000_000;
    const int blockCount = (parts.precision - 1) / blockDigits + 1;
    const int firstWidth = (parts.precision - 1) % blockDigits + 1;

    // Each block adds fewer than 32 bits, so one reserved limb per block suffices.
    auto words = new uint[blockCount];
    size_t position;
    uint first;
    do
        first = nextDigit(coefficient, position);
    while (first == 0);
    words[0] = readBlock(coefficient, position, firstWidth - 1, first);
    size_t used = 1;
    foreach (block; 1 .. blockCount)
    {
        const uint value = readBlock(coefficient, position, blockDigits, 0);
        const uint carry = multiplyAdd(words[0 .. used], blockRadix, value);
        if (carry)
            words[used++] = carry;
    }
    return BigInteger.fromOwnedMagnitude(words[0 .. used], parts.negative ? -1 : 1);
}

private:

uint nextDigit(scope const(char)[] coefficient, ref size_t position) pure nothrow @nogc
{
    if (coefficient[position] == '.')
        ++position;
    return cast(uint) digitAt(coefficient, position, 10);
}

uint readBlock(scope const(char)[] coefficient, ref size_t position, int count, uint value) pure nothrow @nogc
{
    foreach (digit; 0 .. count)
        value = value * 10 + nextDigit(coefficient, position);
    return value;
}

uint multiplyAdd(scope uint[] words, uint factor, uint addend) pure nothrow @nogc
{
    ulong carry = addend;
    foreach (ref word; words)
    {
        const ulong combined = cast(ulong) word * factor + carry;
        word = cast(uint) combined;
        carry = combined >> 32;
    }
    return cast(uint) carry;
}
