module flint.java.math.internal.floating;

import core.math : ldexp;
import flint.java.math.internal.limbs : firstNonzeroLimb, magnitudeBitLength;

@safe:

package(flint.java.math):

/// Round directly at the target precision, and return the rounded value in binary64.
double roundedFloating(scope const(uint)[] words, bool negative, uint precision, size_t maximumBits) pure nothrow @nogc
{
    const size_t bits = magnitudeBitLength(words);
    if (!bits)
        return 0;
    if (bits > maximumBits)
        return negative ? -double.infinity : double.infinity;

    const size_t discarded = bits > precision ? bits - precision : 0;
    const size_t limb = discarded / 32;
    const uint offset = cast(uint)(discarded % 32);
    ulong significand = words[limb] >> offset;
    if (limb + 1 < words.length)
        significand |= cast(ulong) words[limb + 1] << (32 - offset);
    // At most 53 significant bits are needed, so a third word requires a nonzero offset.
    if (limb + 2 < words.length)
        significand |= cast(ulong) words[limb + 2] << (64 - offset);

    if (discarded && roundUp(words, discarded - 1, significand))
        ++significand;
    if (bits == maximumBits && significand == (1UL << precision))
        return negative ? -double.infinity : double.infinity;

    // The integer conversion and power-of-two scaling are exact after rounding.
    const double result = ldexp(cast(double) significand, cast(int) discarded);
    return negative ? -result : result;
}

private bool roundUp(scope const(uint)[] words, size_t guardPosition, ulong significand) pure nothrow @nogc
{
    const size_t limb = guardPosition / 32;
    const uint guard = 1U << (guardPosition % 32);
    if (!(words[limb] & guard))
        return false;
    return (significand & 1) || (words[limb] & (guard - 1)) || firstNonzeroLimb(words) < limb;
}
