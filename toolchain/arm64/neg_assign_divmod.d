// x = -x on a variable in memory negated into the wrong register; this is druntime's
// 128-bit unsigned division, whose remainder came out wrong with -inline.
import core.int128, core.stdc.stdio; alias U = ulong; enum Ubits = 64; enum Zero = Cent();
Cent ud(Cent c1, Cent c2, out Cent modulus)
{
    //printf("udiv c1(%llx,%llx) c2(%llx,%llx)\n", c1.lo, c1.hi, c2.lo, c2.hi);
    // Based on "Unsigned Doubleword Division" in Hacker's Delight
    import core.bitop;

    // Special cases
    if (!tst(c2))
    {
        // Divide by zero
        modulus = Zero;
        return com(modulus);
    }
    if (c1.hi == 0 && c2.hi == 0)
    {
        // Single precision divide
        const Cent rem = { lo:c1.lo % c2.lo };
        modulus = rem;
        const Cent ret = { lo:c1.lo / c2.lo };
        return ret;
    }
    if (c1.hi == 0)
    {
        // Numerator is smaller than the divisor
        modulus = c1;
        return Zero;
    }
    if (c2.hi == 0)
    {
        // Divisor is a 64-bit value, so we just need one 128/64 division.
        // If c1 / c2 would overflow, break c1 up into two halves.
        const q1 = (c1.hi < c2.lo) ? 0 : (c1.hi / c2.lo);
        if (q1)
            c1.hi = c1.hi % c2.lo;
        Cent rem;
        const q0 = udivmod(c1, c2.lo, rem.lo);
        modulus = rem;
        const Cent ret = { lo:q0, hi:q1 };
        return ret;
    }

    // Full cent precision division.
    // Here c2 >= 2^^64
    // We know that c2.hi != 0, so count leading zeros is OK
    // We have 0 <= shift <= 63
    const shift = (Ubits - 1) - bsr(c2.hi);

    // Normalize the divisor so its MSB is 1
    // v1 = (c2 << shift) >> 64
    U v1 = shl(c2, shift).hi;

    // To ensure no overflow.
    Cent u1 = shr1(c1);

    // Get quotient from divide unsigned operation.
    U rem_ignored;
    const Cent q1 = { lo:udivmod(u1, v1, rem_ignored) };

    // Undo normalization and division of c1 by 2.
    Cent quotient = shr(shl(q1, shift), 63);

    // Make quotient correct or too small by 1
    if (tst(quotient))
        quotient = dec(quotient);

    // Now quotient is correct.
    // Compute rem = c1 - (quotient * c2);
    Cent rem = sub(c1, mul(quotient, c2));

    // Check if remainder is larger than the divisor
    if (uge(rem, c2))
    {
        // Increment quotient
        quotient = inc(quotient);
        // Subtract c2 from remainder
        rem = sub(rem, c2);
    }
    modulus = rem;
    //printf("quotient "); print(quotient);
    //printf("modulus  "); print(modulus);
    return quotient;
}
int main()
{
    Cent a = { lo: 15, hi: 72 }, b = { lo: 20, hi: 10 }, r;
    auto q = ud(a, b, r);
    return q.lo == 7 && r.hi == 1 && r.lo == cast(ulong)-125 ? 0 : 1;
}
