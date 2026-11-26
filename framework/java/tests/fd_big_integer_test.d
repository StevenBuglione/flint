module flint.java.internal.math.fd_big_integer_test;

import flint.java.internal.math.fdbiginteger : FDBigInteger;

@safe:

private FDBigInteger scaled(ulong value, uint fives = 0, uint twos = 0) pure nothrow @nogc
{
    FDBigInteger result;
    assert(FDBigInteger.tryScale(value, fives, twos, result));
    return result;
}

private int compareScaled(ref scope const FDBigInteger value, ulong word, uint fives, uint twos) pure nothrow @nogc
{
    const expected = scaled(word, fives, twos);
    return value.cmp(expected);
}

@("FDBigInteger scales across limbs without overflow or partial publication")
unittest
{
    auto power = scaled(1, 324, 323);
    assert(compareScaled(power, 1, 0, 1075) > 0);
    assert(compareScaled(power, 1, 0, 1076) < 0);
    const previous = power;
    assert(!FDBigInteger.tryScale(1, 0, 1280, power));
    assert(power.cmp(previous) == 0);
    assert(!FDBigInteger.tryScale(1, uint.max, 0, power));
    assert(power.cmp(previous) == 0);
    const zero = FDBigInteger.init;
    assert(scaled(0, uint.max, uint.max).cmp(zero) == 0);
}

@("FDBigInteger emits a decimal quotient and scales the remainder")
unittest
{
    auto numerator = scaled(43, 324, 323);
    const denominator = scaled(7, 324, 323);
    uint digit;
    assert(numerator.tryQuoRemIteration(denominator, digit));
    assert(digit == 6 && compareScaled(numerator, 10, 324, 323) == 0);
    assert(numerator.tryQuoRemIteration(denominator, digit));
    assert(digit == 1 && compareScaled(numerator, 30, 324, 323) == 0);

    auto outOfRange = scaled(70, 324, 323);
    assert(!outOfRange.tryQuoRemIteration(denominator, digit));
    assert(compareScaled(outOfRange, 70, 324, 323) == 0);
    const zero = FDBigInteger.init;
    assert(!numerator.tryQuoRemIteration(zero, digit));
    assert(compareScaled(numerator, 30, 324, 323) == 0);

    auto wideRemainder = scaled(1, 0, 1277);
    const divisor = scaled(1, 0, 1278);
    assert(!wideRemainder.tryQuoRemIteration(divisor, digit));
    assert(compareScaled(wideRemainder, 1, 0, 1277) == 0);
}

@("FDBigInteger compares three operands with cross-limb and final carries")
unittest
{
    const left = scaled(ulong.max, 0, 512);
    const right = scaled(1, 0, 512);
    assert(scaled(1, 0, 576).addAndCmp(left, right) == 0);
    assert(left.addAndCmp(left, right) < 0);
    assert(scaled(1, 0, 577).addAndCmp(left, right) > 0);

    const largestBit = scaled(1, 0, 1279);
    assert(largestBit.addAndCmp(largestBit, largestBit) < 0);
    const zero = FDBigInteger.init;
    assert(zero.addAndCmp(zero, zero) == 0);
}
