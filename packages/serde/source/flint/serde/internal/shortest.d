/// Shortest round-trip decimal significands for IEEE 754 binary32 and binary64.
///
/// This is Ryu (Ulf Adams, "Ryu: fast float-to-string conversion", PLDI 2018) with
/// its small-table power-of-five reconstruction. Binary32 inputs run through the same
/// binary64 core with their own interval; the 125-bit factors are exact for every
/// significand below 2^55, which covers both formats.
module flint.serde.internal.shortest;

@safe:

/// The decimal value `digits * 10^exponent` with the fewest significant digits that
/// still parses back to the input; among those, the one closest to it (ties to even).
struct ShortestDecimal
{
    /// At most 17 decimal digits without trailing zeros.
    ulong digits;
    /// Power of ten applied to digits.
    int exponent;
}

private enum uint pow5BitCount = 125;
private enum uint pow5TableStride = 26;

private static immutable ulong[pow5TableStride] smallPow5 = [
    1, 5, 25, 125, 625, 3_125, 15_625, 78_125, 390_625, 1_953_125, 9_765_625, 48_828_125,
    244_140_625, 1_220_703_125, 6_103_515_625, 30_517_578_125, 152_587_890_625, 762_939_453_125,
    3_814_697_265_625, 19_073_486_328_125, 95_367_431_640_625, 476_837_158_203_125,
    2_384_185_791_015_625, 11_920_928_955_078_125, 59_604_644_775_390_625, 298_023_223_876_953_125,
];

// 5^(26k) truncated to its top 125 bits, as [low, high].
private static immutable ulong[2][13] pow5Split = [
    [0x0000_0000_0000_0000, 0x1000_0000_0000_0000], [0x0000_0000_0000_0000, 0x14ad_f4b7_3203_34b9],
    [0x0e54_9208_b31a_db10, 0x1aba_4714_957d_300d], [0x6dc6_ad26_4d8f_0866,
        0x1145_b7e2_85bf_98f5], [0xeb1d_bd92_3d85_96ca,
        0x1652_efdc_6018_a1fc],
    [0xb4c1_b80b_22ae_923c, 0x1cda_6205_5b2d_9d83], [0x5bb2_8b4e_8f7e_4c30, 0x12a5_568b_9f52_f416],
    [0xf08a_ed43_7682_d4fb, 0x1819_6515_31f9_e78f], [0xb4ee_134a_d99b_f150,
        0x1f25_c186_a6f0_4c28], [0x1649_9ecb_70c2_5f03,
        0x1420_eb44_9c88_42e6],
    [0x85a5_6ead_3608_65b0, 0x1a03_fde2_14ca_f085], [0x093d_b1d5_7999_890b, 0x10cf_eb35_3a97_dad8],
    [0xcf38_bb73_5e3f_36ac, 0x15ba_af44_fa52_673e],
];

// 2^(bits(5^(26k)) - 1 + 125) / 5^(26k) + 1, as [low, high].
private static immutable ulong[2][13] pow5InverseSplit = [
    [0x0000_0000_0000_0001, 0x2000_0000_0000_0000], [0x52a6_c95f_c065_5034, 0x18c2_40c4_aecb_13bb],
    [0x7ca8_d500_71df_c806, 0x1327_fc58_da0f_6ff5], [0x6520_247d_3556_476e,
        0x1da4_8ce4_68e7_c702], [0x6139_cdd7_6802_e6e9,
        0x16ef_5b40_c2fc_7779],
    [0xf951_a7ff_43de_8c79, 0x11be_bdf5_78b2_f391], [0x7be8_bee8_d6e9_57e8, 0x1b75_8d84_8fac_54b0],
    [0x8bd3_f9e9_99a4_23ea, 0x153e_da61_4071_a3b7], [0x0848_f973_cb3e_e3ce,
        0x1070_1bd5_27b4_978c], [0x1532_85eb_b9ef_bfa2,
        0x196f_bb9b_b44d_b44d],
    [0xadee_e7f8_6c07_b696, 0x13ae_3591_f5b4_d936], [0x4d68_6a4e_af18_2222, 0x1e74_404f_3daa_da91],
    [0x98c0_a106_e09e_bd9f, 0x1790_0ea4_fda7_c257],
];

// Two-bit corrections, 16 per word, that make the reconstructed values exact.
private static immutable uint[21] pow5Offsets = [
    0x0000_0000, 0x0000_0000, 0x0000_0000, 0x0000_0000, 0x4000_0000, 0x5969_5995, 0x5554_5555,
    0x5655_5515, 0x4115_0504, 0x4055_5410, 0x4455_5145, 0x4450_4540, 0x4555_5550, 0x4000_4000,
    0x9644_0440, 0x5556_5565, 0x5445_4045, 0x4015_4151, 0x5555_9155, 0x5140_5555, 0x0000_0105,
];

private static immutable uint[19] pow5InverseOffsets = [
    0x5454_4554, 0x0405_5545, 0x1004_1000, 0x0040_0414, 0x4001_0000, 0x4115_5555, 0x0000_0454,
    0x0001_0044, 0x4000_0000, 0x4400_0041, 0x5045_4450, 0x5555_0054, 0x5165_5554, 0x4000_4000,
    0x0100_0001, 0x0001_0500, 0x5151_5411, 0x0555_5554, 0x0000_0000,
];

/// Compute the shortest decimal of a nonzero finite value from its IEEE fields.
ShortestDecimal shortest(ulong ieeeMantissa, uint ieeeExponent, uint mantissaBits, int bias) pure nothrow @nogc
{
    auto interval = scaledInterval(ieeeMantissa, ieeeExponent, mantissaBits, bias);
    ulong output = interval.vmIsTrailingZeros || interval.vrIsTrailingZeros
        ? removeExact(interval) : removeCommon(interval);
    int exponent = interval.e10;
    while (output % 10 == 0)
    {
        output /= 10;
        ++exponent;
    }
    return ShortestDecimal(output, exponent);
}

// The value and its rounding interval scaled by 10^-e10: [vm, vp] around vr.
private struct Interval
{
    ulong vr;
    ulong vp;
    ulong vm;
    int e10;
    bool acceptBounds;
    bool vmIsTrailingZeros;
    bool vrIsTrailingZeros;
}

private Interval scaledInterval(ulong ieeeMantissa, uint ieeeExponent, uint mantissaBits, int bias) pure nothrow @nogc
{
    // Two extra bits leave room for the interval bounds.
    int e2 = 1 - bias - cast(int) mantissaBits - 2;
    ulong m2 = ieeeMantissa;
    if (ieeeExponent != 0)
    {
        e2 += cast(int) ieeeExponent - 1;
        m2 |= 1UL << mantissaBits;
    }
    Interval interval;
    interval.acceptBounds = (m2 & 1) == 0;
    immutable mv = 4 * m2;
    immutable uint mmShift = ieeeMantissa != 0 || ieeeExponent <= 1;
    if (e2 >= 0)
    {
        immutable q = log10Pow2(e2) - (e2 > 3 ? 1 : 0);
        interval.e10 = cast(int) q;
        immutable k = cast(int)(pow5BitCount + pow5Bits(q)) - 1;
        scale(interval, m2, inversePow5(q), -e2 + cast(int) q + k, mmShift);
        if (q <= 21)
        {
            // At most one of mp, mv and mm is a multiple of five.
            if (mv % 5 == 0)
                interval.vrIsTrailingZeros = multipleOfPow5(mv, q);
            else if (interval.acceptBounds)
                interval.vmIsTrailingZeros = multipleOfPow5(mv - 1 - mmShift, q);
            else if (multipleOfPow5(mv + 2, q))
                --interval.vp;
        }
    }
    else
    {
        immutable q = log10Pow5(-e2) - (-e2 > 1 ? 1 : 0);
        interval.e10 = cast(int) q + e2;
        immutable index = -e2 - cast(int) q;
        immutable k = cast(int) pow5Bits(index) - cast(int) pow5BitCount;
        scale(interval, m2, pow5(index), cast(int) q - k, mmShift);
        if (q <= 1)
        {
            // mv = 4 * m2 always has at least two trailing zero bits.
            interval.vrIsTrailingZeros = true;
            if (interval.acceptBounds)
                interval.vmIsTrailingZeros = mmShift == 1;
            else
                --interval.vp;
        }
        else if (q < 63)
            interval.vrIsTrailingZeros = (mv & ((1UL << q) - 1)) == 0;
    }
    return interval;
}

private void scale(ref Interval interval, ulong m2, Wide factor, int shift, uint mmShift) pure nothrow @nogc
{
    interval.vr = mulShift(4 * m2, factor, shift);
    interval.vp = mulShift(4 * m2 + 2, factor, shift);
    interval.vm = mulShift(4 * m2 - 1 - mmShift, factor, shift);
}

// Rare general case that tracks exact trailing zeros of the bounds and the value.
private ulong removeExact(ref Interval interval) pure nothrow @nogc
{
    ulong vr = interval.vr;
    ulong vp = interval.vp;
    ulong vm = interval.vm;
    bool vmIsTrailingZeros = interval.vmIsTrailingZeros;
    bool vrIsTrailingZeros = interval.vrIsTrailingZeros;
    uint lastRemovedDigit;
    // Remove digits while the bounds differ, then any shared trailing zeros of vm.
    while (vp / 10 > vm / 10 || (vmIsTrailingZeros && vm % 10 == 0))
    {
        immutable sharedZero = vp / 10 <= vm / 10;
        if (!sharedZero)
            vmIsTrailingZeros &= vm % 10 == 0;
        vrIsTrailingZeros &= lastRemovedDigit == 0;
        lastRemovedDigit = cast(uint)(vr % 10);
        vr /= 10;
        vp /= 10;
        vm /= 10;
        ++interval.e10;
    }
    // Round half to even when the exact value ends in 50...0.
    if (vrIsTrailingZeros && lastRemovedDigit == 5 && vr % 2 == 0)
        lastRemovedDigit = 4;
    immutable outside = vr == vm && (!interval.acceptBounds || !vmIsTrailingZeros);
    return vr + (outside || lastRemovedDigit >= 5 ? 1 : 0);
}

// Common case (about 99%): no exact trailing zeros to track.
private ulong removeCommon(ref Interval interval) pure nothrow @nogc
{
    ulong vr = interval.vr;
    ulong vp = interval.vp;
    ulong vm = interval.vm;
    bool roundUp;
    if (vp / 100 > vm / 100)
    {
        roundUp = vr % 100 >= 50;
        vr /= 100;
        vp /= 100;
        vm /= 100;
        interval.e10 += 2;
    }
    while (vp / 10 > vm / 10)
    {
        roundUp = vr % 10 >= 5;
        vr /= 10;
        vp /= 10;
        vm /= 10;
        ++interval.e10;
    }
    return vr + (vr == vm || roundUp ? 1 : 0);
}

// Bit length of 5^e for 0 < e <= 3528 (and 1 for e = 0).
private uint pow5Bits(int e) pure nothrow @nogc
{
    return ((cast(uint) e * 1_217_359) >> 19) + 1;
}

// floor(log10(2^e)) for 0 <= e <= 1650.
private uint log10Pow2(int e) pure nothrow @nogc
{
    return (cast(uint) e * 78_913) >> 18;
}

// floor(log10(5^e)) for 0 <= e <= 2620.
private uint log10Pow5(int e) pure nothrow @nogc
{
    return (cast(uint) e * 732_923) >> 20;
}

private bool multipleOfPow5(ulong value, uint power) pure nothrow @nogc
{
    uint count;
    while (value != 0 && value % 5 == 0)
    {
        value /= 5;
        ++count;
    }
    return count >= power;
}

/// An unsigned 128-bit value.
package(flint.serde) struct Wide
{
    /// Bits 0 to 63.
    ulong low;
    /// Bits 64 to 127.
    ulong high;
}

// 64x64 -> 128-bit product without compiler intrinsics or druntime helpers.
private Wide multiply(ulong a, ulong b) pure nothrow @nogc
{
    immutable aLow = a & 0xffff_ffff;
    immutable aHigh = a >> 32;
    immutable bLow = b & 0xffff_ffff;
    immutable bHigh = b >> 32;
    immutable lowLow = aLow * bLow;
    immutable middle = aHigh * bLow + (lowLow >> 32);
    immutable middle2 = aLow * bHigh + (middle & 0xffff_ffff);
    return Wide((middle2 << 32) | (lowLow & 0xffff_ffff), aHigh * bHigh + (middle >> 32) + (middle2 >> 32));
}

// Bits [distance, distance + 64) of high:low, for 0 < distance < 64.
private ulong shiftRight128(ulong low, ulong high, uint distance) pure nothrow @nogc
{
    return (high << (64 - distance)) | (low >> distance);
}

// The 192-bit product m * factor, three words from the least significant.
private ulong[3] multiply192(ulong m, Wide factor) pure nothrow @nogc
{
    immutable top = multiply(m, factor.high);
    immutable bottom = multiply(m, factor.low);
    immutable sum = bottom.high + top.low;
    return [bottom.low, sum, top.high + (sum < bottom.high ? 1 : 0)];
}

private ulong mulShift(ulong m, Wide factor, int shift) pure nothrow @nogc
{
    immutable product = multiply192(m, factor);
    return shiftRight128(product[1], product[2], cast(uint)(shift - 64));
}

/// 5^index truncated to its top 125 bits.
package(flint.serde) Wide pow5(int index) pure nothrow @nogc
{
    immutable base = cast(uint) index / pow5TableStride;
    immutable base2 = base * pow5TableStride;
    immutable offset = cast(uint) index - base2;
    immutable factor = Wide(pow5Split[base][0], pow5Split[base][1]);
    if (offset == 0)
        return factor;
    immutable product = multiply192(smallPow5[offset], factor);
    immutable delta = pow5Bits(index) - pow5Bits(base2);
    immutable correction = (pow5Offsets[index / 16] >> ((index % 16) << 1)) & 3;
    immutable low = shiftRight128(product[0], product[1], delta) + correction;
    return Wide(low, shiftRight128(product[1], product[2], delta));
}

/// 2^(bits(5^index) - 1 + 125) / 5^index + 1.
package(flint.serde) Wide inversePow5(uint index) pure nothrow @nogc
{
    immutable base = (index + pow5TableStride - 1) / pow5TableStride;
    immutable base2 = base * pow5TableStride;
    immutable offset = base2 - index;
    immutable factor = Wide(pow5InverseSplit[base][0], pow5InverseSplit[base][1]);
    if (offset == 0)
        return factor;
    immutable product = multiply192(smallPow5[offset], Wide(factor.low - 1, factor.high));
    immutable delta = pow5Bits(base2) - pow5Bits(index);
    immutable correction = (pow5InverseOffsets[index / 16] >> ((index % 16) << 1)) & 3;
    immutable low = shiftRight128(product[0], product[1], delta) + 1 + correction;
    return Wide(low, shiftRight128(product[1], product[2], delta));
}
