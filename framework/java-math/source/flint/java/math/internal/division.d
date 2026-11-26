module flint.java.math.internal.division;

import core.bitop : bsr;

@safe:

package(flint.java.math):

/// Divide by one word, optionally writing the quotient. Both slices may be the same buffer.
uint divideByWord(scope uint[] quotient, scope const(uint)[] value, uint divisor) pure nothrow @nogc
{
    ulong remainder;
    foreach_reverse (index; 0 .. value.length)
    {
        const ulong partial = (remainder << 32) | value[index];
        if (quotient.length)
            quotient[index] = cast(uint)(partial / divisor);
        remainder = partial % divisor;
    }
    return cast(uint) remainder;
}

/// Normalize, divide, and leave the remainder in work[0 .. divisor.length].
void divideWords(scope uint[] quotient, scope uint[] work, scope uint[] normalized,
        scope const(uint)[] numerator, scope const(uint)[] divisor) pure nothrow @nogc
{
    const uint shift = 31 - cast(uint) bsr(divisor[$ - 1]);
    shiftLeft(work, numerator, shift);
    shiftLeft(normalized, divisor, shift);
    const size_t width = normalized.length;
    const ulong high = normalized[width - 1];
    foreach_reverse (position; 0 .. work.length - width)
    {
        const size_t top = position + width;
        const ulong partial = (cast(ulong) work[top] << 32) | work[top - 1];
        ulong digit = partial / high;
        if (digit > uint.max)
            digit = uint.max;
        ulong residual = partial - digit * high;
        while (residual <= uint.max && digit * normalized[width - 2] > ((residual << 32) | work[top - 2]))
        {
            --digit;
            residual += high;
        }
        if (subtractProduct(work[position .. top + 1], normalized, cast(uint) digit))
        {
            --digit;
            addBack(work[position .. top + 1], normalized);
        }
        if (quotient.length)
            quotient[position] = cast(uint) digit;
    }
    if (shift)
        shiftRight(work[0 .. width], shift);
}

private void shiftLeft(scope uint[] outWords, scope const(uint)[] source, uint shift) pure nothrow @nogc
{
    ulong carry;
    foreach (i, word; source)
    {
        const ulong shifted = (cast(ulong) word << shift) | carry;
        outWords[i] = cast(uint) shifted;
        carry = shifted >> 32;
    }
    if (outWords.length > source.length)
        outWords[source.length] = cast(uint) carry;
}

private void shiftRight(scope uint[] words, uint shift) pure nothrow @nogc
{
    uint carry;
    foreach_reverse (ref word; words)
    {
        const uint original = word;
        word = (original >> shift) | carry;
        carry = original << (32 - shift);
    }
}

private bool subtractProduct(scope uint[] work, scope const(uint)[] divisor, uint digit) pure nothrow @nogc
{
    ulong borrow;
    foreach (i, word; divisor)
    {
        const ulong product = cast(ulong) word * digit + borrow;
        const uint low = cast(uint) product;
        const uint original = work[i];
        work[i] = original - low;
        borrow = (product >> 32) + (original < low);
    }
    const uint high = work[$ - 1];
    work[$ - 1] = high - cast(uint) borrow;
    return high < borrow;
}

private void addBack(scope uint[] work, scope const(uint)[] divisor) pure nothrow @nogc
{
    ulong carry;
    foreach (i, word; divisor)
    {
        carry += cast(ulong) work[i] + word;
        work[i] = cast(uint) carry;
        carry >>= 32;
    }
    work[$ - 1] += cast(uint) carry;
}
