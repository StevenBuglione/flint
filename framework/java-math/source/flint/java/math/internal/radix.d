module flint.java.math.internal.radix;

import core.bitop : bsr;
import flint.java.math.internal.division : divideByWord;

@safe:

package(flint.java.math):

/// Format a normalized magnitude and sign in the requested Java radix.
string formatRadix(scope const(uint)[] words, bool negative, int radix) pure nothrow
{
    if (!words.length)
        return "0";
    const uint base = radix >= 2 && radix <= 36 ? cast(uint) radix : 10;
    const uint shift = cast(uint) bsr(base);
    const size_t bits = words.length * 32 - 31 + bsr(words[$ - 1]);
    const size_t capacity = (bits + shift - 1) / shift + negative;
    return render(words, negative, base, shift, capacity);
}

private char[] render(scope const(uint)[] words, bool negative, uint base, uint shift, size_t capacity) pure nothrow
{
    auto text = new char[capacity];
    if ((base & (base - 1)) == 0)
    {
        writePowerOfTwo(text, words, negative, shift);
        return text;
    }

    uint[32] local = void;
    scope uint[] scratch = words.length <= local.length ? local[0 .. words.length] : new uint[words.length];
    scratch[] = words[];
    return text[writeGroups(text, scratch, negative, base) .. $];
}

private void writePowerOfTwo(scope char[] text, scope const(uint)[] words, bool negative, uint shift) pure nothrow @nogc
{
    const uint mask = (1U << shift) - 1;
    size_t bit;
    for (size_t at = text.length; at > negative; bit += shift)
    {
        const size_t limb = bit / 32;
        const uint offset = cast(uint)(bit % 32);
        uint group = words[limb] >> offset;
        if (offset + shift > 32 && limb + 1 < words.length)
            group |= words[limb + 1] << (32 - offset);
        text[--at] = digit(group & mask);
    }
    if (negative)
        text[0] = '-';
}

private size_t writeGroups(scope char[] text, scope uint[] scratch, bool negative, uint base) pure nothrow @nogc
{
    uint divisor = base;
    uint groupWidth = 1;
    while (divisor <= uint.max / base)
    {
        divisor *= base;
        ++groupWidth;
    }

    size_t at = text.length;
    do
    {
        uint remainder = divideByWord(scratch, scratch, divisor);
        // Dividing by one word can remove at most one leading word.
        if (!scratch[$ - 1])
            scratch = scratch[0 .. $ - 1];

        uint written;
        do
        {
            text[--at] = digit(remainder % base);
            remainder /= base;
        }
        while (++written < groupWidth && (scratch.length || remainder));
    }
    while (scratch.length);

    if (negative)
        text[--at] = '-';
    return at;
}

private char digit(uint value) pure nothrow @nogc
{
    return cast(char)(value < 10 ? '0' + value : 'a' + value - 10);
}
