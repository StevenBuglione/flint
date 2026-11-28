/// Read Java radix digits from Flint's UTF-8 string representation.
module flint.java.math.internal.radixparse;

import flint.engine.aot.text : decodeUtf8;
import flint.java.lang.character : digit;

@safe:

/// Consume one digit using Java's UTF-16 code unit range.
int digitAt(scope const(char)[] text, ref size_t index, int radix) pure nothrow @nogc
{
    if (text[index] < 0x80)
        return digit(text[index++], radix);
    const point = decodeUtf8(text, index);
    return point <= wchar.max ? digit(cast(wchar) point, radix) : -1;
}
