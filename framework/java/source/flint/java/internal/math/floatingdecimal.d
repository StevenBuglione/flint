/*
 * Copyright (c) 2013, 2020, Oracle and/or its affiliates. All rights reserved.
 * DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS FILE HEADER.
 *
 * This code is free software; you can redistribute it and/or modify it
 * under the terms of the GNU General Public License version 2 only, as
 * published by the Free Software Foundation.  Oracle designates this
 * particular file as subject to the "Classpath" exception as provided
 * by Oracle in the LICENSE file that accompanied this code.
 *
 * This code is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
 * FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
 * version 2 for more details (a copy is included in the LICENSE file that
 * accompanied this code).
 *
 * You should have received a copy of the GNU General Public License version
 * 2 along with this work; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin St, Fifth Floor, Boston, MA 02110-1301 USA.
 *
 * Please contact Oracle, 500 Oracle Parkway, Redwood Shores, CA 94065 USA
 * or visit www.oracle.com if you need additional information or have any
 * questions.
 */
// Ported from openjdk 21.0.13: src/java.base/share/classes/jdk/internal/math/FloatingDecimal.java
// (readJavaFormatString and ASCIIToBinaryBuffer.doubleValue) and FDBigInteger.java (the arithmetic
// doubleValue uses), with src/java.base/share/classes/java/text/DigitList.java (getDouble).
// Modified by the Flint authors.
module flint.java.internal.math.floatingdecimal;

@safe:

package(flint.java):

enum FloatingDecimalStatus : ubyte
{
    ok,
    /// Java throws NumberFormatException.
    numberFormat,
    /// A hexadecimal floating-point string, which this port does not parse yet.
    hexUnsupported,
    /// Longer than a Java string or DigitList can be.
    capacity,
}

struct FloatingDecimalResult
{
    FloatingDecimalStatus status;
    /// The parsed value when `status` is `ok`.
    double value = 0;
}

/// Double.parseDouble for decimal input, without the NumberFormatException.
FloatingDecimalResult parseDouble(scope const(char)[] text) pure nothrow @nogc
{
    if (text.length > maxTextLength)
        return FloatingDecimalResult(FloatingDecimalStatus.capacity);
    const input = trimJava(text);
    if (input.length == 0)
        return failed();
    const signSeen = input[0] == '-' || input[0] == '+';
    const isNegative = input[0] == '-';
    const start = signSeen ? 1 : 0;
    if (start == input.length)
        return failed();
    FloatingDecimalResult special;
    if (trySpecial(input[start .. $], isNegative, special))
        return special;
    DecimalScan scan;
    if (!scan.read(input, start, signSeen))
        return failed();
    if (scan.isZero)
        return parsed(isNegative ? -0.0 : 0.0);
    return doubleValue(isNegative, scan.decExp, scan.digits[], scan.nDigits);
}

/// DigitList.getDouble: Double.parseDouble("." ~ digits ~ "E" ~ decimalAt).
/// `digits` holds the first stored digits of `count`; the rest are zeros.
FloatingDecimalResult digitListToDouble(scope const(char)[] digits, size_t count, int decimalAt) pure nothrow @nogc
{
    if (count == 0)
        return parsed(0.0);
    if (count > maxTextLength || digits.length > count)
        return FloatingDecimalResult(FloatingDecimalStatus.capacity);
    foreach (digit; digits)
        if (digit < '0' || digit > '9')
            return failed();

    // The leading point gives decPt zero; leading zeros only lower the exponent.
    size_t first;
    while (first < digits.length && digits[first] == '0')
        ++first;
    size_t last = digits.length;
    while (last > first && digits[last - 1] == '0')
        --last;
    if (first == last)
        return parsed(0.0);
    const nDigits = cast(int)(last - first);
    const nTrailZero = cast(int)(count - last);

    // Scan the exponent from its decimal text, as Java does after StringBuilder.append(int).
    char[10] exponent = void;
    size_t i = exponent.length;
    uint magnitude = decimalAt < 0 ? 0u - cast(uint) decimalAt : decimalAt;
    do
    {
        exponent[--i] = cast(char)('0' + magnitude % 10);
        magnitude /= 10;
    }
    while (magnitude);
    int expVal;
    bool expOverflow;
    scanExponent(exponent[], i, expVal, expOverflow);
    const expSign = decimalAt < 0 ? -1 : 1;
    const decExp = adjustExponent(-cast(int) first, expSign, expVal, expOverflow, nDigits + nTrailZero);
    return doubleValue(false, decExp, digits[first .. last], nDigits);
}

private:

enum maxTextLength = int.max / 4;

enum expShift = 52;
enum ulong fractHob = 1UL << expShift;
enum ulong signifBitMask = fractHob - 1;
enum ulong expBitMask = 0x7ffUL << expShift;
enum ulong signBitMask = 1UL << 63;
enum expBias = 1023;
enum maxDecimalDigits = 15;
enum maxDecimalExponent = 308;
enum minDecimalExponent = -324;
enum bigDecimalExponent = 324;
enum maxNDigits = 1100;

static immutable double[23] small10Pow = [
    1.0e0, 1.0e1, 1.0e2, 1.0e3, 1.0e4, 1.0e5, 1.0e6, 1.0e7, 1.0e8, 1.0e9, 1.0e10, 1.0e11, 1.0e12,
    1.0e13, 1.0e14, 1.0e15, 1.0e16, 1.0e17, 1.0e18, 1.0e19, 1.0e20, 1.0e21, 1.0e22,
];
static immutable double[5] big10Pow = [1e16, 1e32, 1e64, 1e128, 1e256];
static immutable double[5] tiny10Pow = [1e-16, 1e-32, 1e-64, 1e-128, 1e-256];
enum maxSmallTen = cast(int) small10Pow.length - 1;

FloatingDecimalResult failed() pure nothrow @nogc
{
    return FloatingDecimalResult(FloatingDecimalStatus.numberFormat);
}

FloatingDecimalResult parsed(double value) pure nothrow @nogc
{
    return FloatingDecimalResult(FloatingDecimalStatus.ok, value);
}

FloatingDecimalResult signed(bool isNegative, double value) pure nothrow @nogc
{
    return parsed(isNegative ? -value : value);
}

int minInt(int left, int right) pure nothrow @nogc
{
    return left < right ? left : right;
}

ulong doubleToRawBits(double value) pure nothrow @nogc
{
    union Bits
    {
        double d;
        ulong u;
    }

    Bits bits;
    bits.d = value;
    return bits.u;
}

double rawBitsToDouble(ulong value) pure nothrow @nogc
{
    union Bits
    {
        ulong u;
        double d;
    }

    Bits bits;
    bits.u = value;
    return bits.d;
}

// String.trim removes UTF-16 units up to U+0020, which are exactly these UTF-8 bytes.
inout(char)[] trimJava(return scope inout(char)[] text) pure nothrow @nogc
{
    size_t begin;
    size_t end = text.length;
    while (begin < end && text[begin] <= ' ')
        ++begin;
    while (end > begin && text[end - 1] <= ' ')
        --end;
    return text[begin .. end];
}

// NaN, Infinity and the hexadecimal prefix, after an optional sign.
bool trySpecial(scope const(char)[] rest, bool isNegative, out FloatingDecimalResult result) pure nothrow @nogc
{
    if (rest[0] == 'N')
        result = rest == "NaN" ? parsed(double.nan) : failed();
    else if (rest[0] == 'I')
        result = rest == "Infinity" ? signed(isNegative, double.infinity) : failed();
    else if (rest.length > 1 && rest[0] == '0' && (rest[1] == 'x' || rest[1] == 'X'))
        result = FloatingDecimalResult(FloatingDecimalStatus.hexUnsupported);
    else
        return false;
    return true;
}

// The decimal branch of readJavaFormatString.
struct DecimalScan
{
    // Java keeps every digit, but doubleValue reads at most maxNDigits of them and a sticky one.
    char[maxNDigits] digits = void;
    int nDigits;
    int nLeadZero;
    int nTrailZero;
    int decExp;
    bool isZero;

    bool read(scope const(char)[] input, size_t i, bool signSeen) pure nothrow @nogc
    {
        int decPt = -1;
        for (; i < input.length; ++i)
        {
            const c = input[i];
            if (c == '.')
            {
                if (decPt >= 0)
                    return false;
                decPt = cast(int) i - signSeen;
            }
            else if (c < '0' || c > '9')
                break;
            else if (c == '0' && nDigits == 0)
                ++nLeadZero;
            else
                append(c);
        }
        nDigits -= nTrailZero;
        isZero = nDigits == 0;
        if (isZero && nLeadZero == 0)
            return false;
        decExp = decPt >= 0 ? decPt - nLeadZero : nDigits + nTrailZero;
        return readExponent(input, i) && suffixOnly(input, i);
    }

    private void append(char c) pure nothrow @nogc
    {
        if (nDigits < maxNDigits)
            digits[nDigits] = c;
        ++nDigits;
        nTrailZero = c == '0' ? nTrailZero + 1 : 0;
    }

    private bool readExponent(scope const(char)[] input, ref size_t i) pure nothrow @nogc
    {
        if (i == input.length || (input[i] != 'e' && input[i] != 'E'))
            return true;
        if (++i == input.length)
            return false;
        int expSign = 1;
        if (input[i] == '-' || input[i] == '+')
            expSign = input[i++] == '-' ? -1 : 1;
        const expAt = i;
        int expVal;
        bool expOverflow;
        scanExponent(input, i, expVal, expOverflow);
        decExp = adjustExponent(decExp, expSign, expVal, expOverflow, nDigits + nTrailZero);
        // No digits after the marker and sign is an error; trailing text is checked separately.
        return i != expAt;
    }

    private static bool suffixOnly(scope const(char)[] input, size_t i) pure nothrow @nogc
    {
        if (i == input.length)
            return true;
        if (i + 1 != input.length)
            return false;
        const c = input[i];
        return c == 'f' || c == 'F' || c == 'd' || c == 'D';
    }
}

// Java's expLoop, including the int wraparound once the value has overflowed.
void scanExponent(scope const(char)[] input, ref size_t i, ref int expVal, ref bool expOverflow) pure nothrow @nogc
{
    enum reallyBig = int.max / 10;
    for (; i < input.length; ++i)
    {
        if (expVal >= reallyBig)
            expOverflow = true;
        const c = input[i];
        if (c < '0' || c > '9')
            break;
        expVal = expVal * 10 + (c - '0');
    }
}

// The exponent limit over all digits, trailing zeros included, keeps doubleValue from overflowing.
int adjustExponent(int decExp, int expSign, int expVal, bool expOverflow, int digitCount) pure nothrow @nogc
{
    const expLimit = bigDecimalExponent + digitCount;
    if (!expOverflow && expVal <= expLimit)
        return decExp + expSign * expVal;
    if (!expOverflow && expSign == 1 && decExp < 0 && expVal + decExp < expLimit)
        return decExp + expVal;
    return expSign * expLimit;
}

// Java truncates more than maxNDigits digits to maxNDigits and a sticky '1'.
char digitAt(scope const(char)[] digits, int index) pure nothrow @nogc
{
    return index == maxNDigits ? '1' : digits[index];
}

// ASCIIToBinaryBuffer.doubleValue over `nDigits` significant digits without leading or trailing zeros.
FloatingDecimalResult doubleValue(bool negative, int decExp, scope const(char)[] digits, int nDigits) pure nothrow @nogc
{
    const kDigits = minInt(nDigits, maxDecimalDigits + 1);
    long lValue;
    foreach (i; 0 .. kDigits)
        lValue = lValue * 10 + (digits[i] - '0');
    double dValue = cast(double) lValue;
    const exp = decExp - kDigits;
    double exact;
    if (nDigits <= maxDecimalDigits && tryOneRounding(dValue, exp, kDigits, exact))
        return signed(negative, exact);

    final switch (approximate(dValue, exp, decExp))
    {
    case Estimate.infinity:
        return signed(negative, double.infinity);
    case Estimate.zero:
        return signed(negative, 0.0);
    case Estimate.candidate:
        break;
    }

    if (nDigits > maxNDigits)
        nDigits = maxNDigits + 1;
    Correction correction;
    correction.start(lValue, digits, kDigits, nDigits, decExp - nDigits);
    ulong ieeeBits = doubleToRawBits(dValue);
    while (correction.adjust(ieeeBits))
    {
    }
    if (correction.overflow)
        return FloatingDecimalResult(FloatingDecimalStatus.capacity);
    if (negative)
        ieeeBits |= signBitMask;
    return parsed(rawBitsToDouble(ieeeBits));
}

// Exact digits and a small exponent need only one rounding.
bool tryOneRounding(double dValue, int exp, int kDigits, out double result) pure nothrow @nogc
{
    if (exp == 0 || dValue == 0.0)
        result = dValue;
    else if (exp > 0 && exp <= maxSmallTen)
        result = dValue * small10Pow[exp];
    else if (exp > 0)
    {
        // dValue * 10^slop is still exact, leaving one rounding for the rest.
        const slop = maxDecimalDigits - kDigits;
        if (exp > maxSmallTen + slop)
            return false;
        const scaled = dValue * small10Pow[slop];
        result = scaled * small10Pow[exp - slop];
    }
    else if (exp >= -maxSmallTen)
        result = dValue / small10Pow[-exp];
    else
        return false;
    return true;
}

enum Estimate : ubyte
{
    candidate,
    infinity,
    zero,
}

// Naive scaling by powers of ten gives the first candidate.
Estimate approximate(ref double dValue, int exp, int decExponent) pure nothrow @nogc
{
    if (exp > 0)
        return decExponent > maxDecimalExponent + 1 ? Estimate.infinity : scaleUp(dValue, exp);
    if (exp < 0)
        return decExponent < minDecimalExponent - 1 ? Estimate.zero : scaleDown(dValue, -exp);
    return Estimate.candidate;
}

Estimate scaleUp(ref double dValue, int exp) pure nothrow @nogc
{
    if ((exp & 15) != 0)
        dValue *= small10Pow[exp & 15];
    exp >>= 4;
    if (exp == 0)
        return Estimate.candidate;
    int j;
    for (; exp > 1; ++j, exp >>= 1)
        if ((exp & 1) != 0)
            dValue *= big10Pow[j];
    // The last multiplication can overflow; one step past Double.MAX_VALUE still gives a candidate.
    double t = dValue * big10Pow[j];
    if (t == double.infinity)
    {
        t = dValue / 2.0;
        t *= big10Pow[j];
        if (t == double.infinity)
            return Estimate.infinity;
        t = double.max;
    }
    dValue = t;
    return Estimate.candidate;
}

Estimate scaleDown(ref double dValue, int exp) pure nothrow @nogc
{
    if ((exp & 15) != 0)
        dValue /= small10Pow[exp & 15];
    exp >>= 4;
    if (exp == 0)
        return Estimate.candidate;
    int j;
    for (; exp > 1; ++j, exp >>= 1)
        if ((exp & 1) != 0)
            dValue *= tiny10Pow[j];
    // The last multiplication can underflow; one step below Double.MIN_VALUE still gives a candidate.
    double t = dValue * tiny10Pow[j];
    if (t == 0.0)
    {
        t = dValue * 2.0;
        t *= tiny10Pow[j];
        if (t == 0.0)
            return Estimate.zero;
        t = rawBitsToDouble(1);
    }
    dValue = t;
    return Estimate.candidate;
}

// The candidate's significand and the powers of 2 that keep bigB, bigD and half an ulp integral.
struct CandidateScale
{
    ulong bigBbits;
    int bigIntExp;
    int bigIntNBits;
    int b2;
    int d2;
    int ulp2;

    this(ulong ieeeBits, int b5, int d5) pure nothrow @nogc
    {
        import core.bitop : bsf, bsr;

        // ieeeBits is finite and nonzero here.
        int binexp = cast(int)(ieeeBits >>> expShift);
        ulong bits = ieeeBits & signifBitMask;
        if (binexp > 0)
            bits |= fractHob;
        else
        {
            // Normalize a subnormal candidate.
            const shift = (63 - bsr(bits)) - (63 - expShift);
            bits <<= shift;
            binexp = 1 - shift;
        }
        binexp -= expBias;
        const lowOrderZeros = bsf(bits);
        bigBbits = bits >>> lowOrderZeros;
        bigIntExp = binexp - expShift + lowOrderZeros;
        bigIntNBits = expShift + 1 - lowOrderZeros;

        b2 = b5;
        d2 = d5;
        if (bigIntExp >= 0)
            b2 += bigIntExp;
        else
            d2 -= bigIntExp;
        ulp2 = b2;
        const hulpbias = binexp <= -expBias ? binexp + lowOrderZeros + expBias : 1 + lowOrderZeros;
        b2 += hulpbias;
        d2 += hulpbias;
        // Common factors of 2 add nothing.
        const common2 = minInt(b2, minInt(d2, ulp2));
        b2 -= common2;
        d2 -= common2;
        ulp2 -= common2;
    }
}

// doubleValue's correctionLoop: compare the candidate with the exact value bigD0 * 10^exp.
struct Correction
{
    DecimalBigInteger bigD0;
    DecimalBigInteger pow5;
    DecimalBigInteger bigD;
    DecimalBigInteger bigB;
    int b5;
    int d5;
    int prevD2 = -1;

    void start(long lValue, scope const(char)[] digits, int kDigits, int nDigits, int exp) pure nothrow @nogc
    {
        b5 = exp < 0 ? -exp : 0;
        d5 = exp > 0 ? exp : 0;
        bigD0.setDigits(lValue, digits, kDigits, nDigits);
        bigD0.multiplyPow5(d5);
        pow5.setPow5(b5);
    }

    bool overflow() const pure nothrow @nogc
    {
        return bigD0.overflow || pow5.overflow || bigD.overflow || bigB.overflow;
    }

    // Moves ieeeBits one ulp toward the exact value; false when the loop is done.
    bool adjust(ref ulong ieeeBits) pure nothrow @nogc
    {
        const scale = CandidateScale(ieeeBits, b5, d5);
        bigB.setProduct(pow5, scale.bigBbits);
        bigB.shiftLeft(scale.b2);
        if (prevD2 != scale.d2)
        {
            bigD = bigD0;
            bigD.shiftLeft(scale.d2);
            prevD2 = scale.d2;
        }

        // The difference replaces bigB.
        const order = bigB.compare(bigD);
        if (order == 0)
            return false;
        const overvalue = order > 0;
        int ulp2 = scale.ulp2;
        if (overvalue)
        {
            bigB.subtract(bigD);
            // A normalized power of two that is too big uses the ulp of the next smaller range.
            if (scale.bigIntNBits == 1 && scale.bigIntExp > -expBias + 1 && --ulp2 < 0)
            {
                ulp2 = 0;
                bigB.shiftLeft(1);
            }
        }
        else
            bigB.subtractFrom(bigD);
        if (overflow)
            return false;

        const half = bigB.compareShifted(pow5, ulp2);
        if (half < 0)
            return false;
        // Exactly half an ulp rounds to even.
        if (half == 0 && (ieeeBits & 1) == 0)
            return false;
        ieeeBits = overvalue ? ieeeBits - 1 : ieeeBits + 1;
        return half > 0 && ieeeBits != 0 && ieeeBits != expBitMask;
    }
}

// FDBigInteger's values without its offset words or allocation. With at most maxNDigits + 1 digits
// the operands stay below 10^1101 * 2^1128 (fewer than 4,790 bits) before a final doubling.
struct DecimalBigInteger
{
    enum wordCapacity = 160;
    uint[wordCapacity] words;
    uint wordCount;
    bool overflow;

    // FDBigInteger(long, char[], int, int): lValue followed by digits[kDigits .. nDigits].
    void setDigits(long lValue, scope const(char)[] digits, int kDigits, int nDigits) pure nothrow @nogc
    {
        words[0] = cast(uint) lValue;
        words[1] = cast(uint)(lValue >>> 32);
        wordCount = 2;
        int i = kDigits;
        const limit = nDigits - 5;
        while (i < limit)
        {
            const ilim = i + 5;
            uint v = digitAt(digits, i++) - '0';
            while (i < ilim)
                v = 10 * v + (digitAt(digits, i++) - '0');
            multiplyAdd(100_000, v);
        }
        uint factor = 1;
        uint v;
        while (i < nDigits)
        {
            v = 10 * v + (digitAt(digits, i++) - '0');
            factor *= 10;
        }
        if (factor != 1)
            multiplyAdd(factor, v);
        trim();
    }

    void setPow5(int p5) pure nothrow @nogc
    {
        words[0] = 1;
        wordCount = 1;
        multiplyPow5(p5);
    }

    void multiplyPow5(int p5) pure nothrow @nogc
    {
        for (; p5 >= 13; p5 -= 13)
            multiplyAdd(1_220_703_125, 0);
        if (p5)
            multiplyAdd(smallFivePowers[p5], 0);
    }

    // FDBigInteger.mult(int[], int, int, int, int[]): source times a value below 2^64.
    void setProduct(ref scope const DecimalBigInteger source, ulong value) pure nothrow @nogc
    {
        overflow = source.overflow;
        if (source.wordCount + 2 > wordCapacity)
        {
            overflow = true;
            wordCount = 0;
            return;
        }
        const n = source.wordCount;
        ulong low = cast(uint) value;
        ulong carry;
        foreach (j; 0 .. n)
        {
            const product = source.words[j] * low + carry;
            words[j] = cast(uint) product;
            carry = product >>> 32;
        }
        words[n] = cast(uint) carry;
        const high = value >>> 32;
        carry = 0;
        foreach (j; 0 .. n)
        {
            const product = words[j + 1] + high * source.words[j] + carry;
            words[j + 1] = cast(uint) product;
            carry = product >>> 32;
        }
        words[n + 1] = cast(uint) carry;
        wordCount = n + 2;
        trim();
    }

    void shiftLeft(int bits) pure nothrow @nogc
    {
        if (wordCount == 0 || bits == 0)
            return;
        const offset = cast(uint) bits / 32;
        const shift = cast(uint) bits % 32;
        const high = shift == 0 ? 0 : words[wordCount - 1] >>> (32 - shift);
        if (wordCount + offset + (high != 0) > wordCapacity)
        {
            overflow = true;
            return;
        }
        if (high)
            words[wordCount + offset] = high;
        foreach_reverse (i; 0 .. wordCount)
        {
            uint word = words[i] << shift;
            if (shift && i)
                word |= words[i - 1] >>> (32 - shift);
            words[i + offset] = word;
        }
        words[0 .. offset] = 0;
        wordCount += offset + (high != 0);
    }

    int compare(ref scope const DecimalBigInteger other) const pure nothrow @nogc
    {
        if (wordCount != other.wordCount)
            return wordCount < other.wordCount ? -1 : 1;
        foreach_reverse (i; 0 .. wordCount)
            if (words[i] != other.words[i])
                return words[i] < other.words[i] ? -1 : 1;
        return 0;
    }

    // FDBigInteger.cmpPow52 without materializing `other << bits`.
    int compareShifted(ref scope const DecimalBigInteger other, int bits) const pure nothrow @nogc
    {
        if (other.wordCount == 0)
            return wordCount != 0;
        const offset = cast(uint) bits / 32;
        const shift = cast(uint) bits % 32;
        const high = shift == 0 ? 0 : other.words[other.wordCount - 1] >>> (32 - shift);
        const otherLength = other.wordCount + offset + (high != 0);
        if (wordCount != otherLength)
            return wordCount < otherLength ? -1 : 1;
        foreach_reverse (i; 0 .. wordCount)
        {
            uint word;
            if (i >= offset)
            {
                const source = i - offset;
                if (source < other.wordCount)
                    word = other.words[source] << shift;
                if (shift && source > 0)
                    word |= other.words[source - 1] >>> (32 - shift);
            }
            if (words[i] != word)
                return words[i] < word ? -1 : 1;
        }
        return 0;
    }

    // this -= other, where other <= this.
    void subtract(ref scope const DecimalBigInteger other) pure nothrow @nogc
    {
        ulong borrow;
        foreach (i; 0 .. wordCount)
        {
            const subtrahend = borrow + (i < other.wordCount ? other.words[i] : 0);
            const minuend = words[i];
            words[i] = cast(uint)(minuend - subtrahend);
            borrow = minuend < subtrahend;
        }
        trim();
    }

    // this = other - this, where this <= other.
    void subtractFrom(ref scope const DecimalBigInteger other) pure nothrow @nogc
    {
        ulong borrow;
        foreach (i; 0 .. other.wordCount)
        {
            const subtrahend = borrow + (i < wordCount ? words[i] : 0);
            const minuend = other.words[i];
            words[i] = cast(uint)(minuend - subtrahend);
            borrow = minuend < subtrahend;
        }
        wordCount = other.wordCount;
        overflow |= other.overflow;
        trim();
    }

private:
    void multiplyAdd(uint factor, uint addend) pure nothrow @nogc
    {
        ulong carry = addend;
        foreach (i; 0 .. wordCount)
        {
            const product = cast(ulong) words[i] * factor + carry;
            words[i] = cast(uint) product;
            carry = product >>> 32;
        }
        if (carry)
        {
            if (wordCount == wordCapacity)
            {
                overflow = true;
                return;
            }
            words[wordCount++] = cast(uint) carry;
        }
    }

    void trim() pure nothrow @nogc
    {
        while (wordCount && words[wordCount - 1] == 0)
            --wordCount;
    }

    static immutable uint[13] smallFivePowers = [
        1, 5, 25, 125, 625, 3_125, 15_625, 78_125, 390_625, 1_953_125, 9_765_625, 48_828_125,
        244_140_625,
    ];
}
