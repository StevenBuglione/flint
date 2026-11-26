module app;

import core.stdc.stdio : printf;
import flint.java.util.hexformat : HexFormat;

@safe:

int main(string[] args) @system
{
    const int count = cast(int) args.length;
    const long value = 0x12AB_CDEF + count;
    auto lower = HexFormat.of();
    auto upper = lower.withUpperCase();
    auto format = (count & 1) ? upper : upper.withLowerCase();
    const small = format.toHexDigits(cast(byte) value);
    const unit = format.toHexDigits(cast(wchar) value);
    const medium = format.toHexDigits(cast(short) value);
    const intText = format.toHexDigits(cast(int) value);
    const full = format.toHexDigits(value);
    const suffix = format.toHexDigits(value, count);
    const int codePoint = '0' + count;
    const int decoded = HexFormat.fromHexDigit(codePoint);
    printf("%.*s %.*s %.*s %.*s %.*s %.*s %c%c %d %d\n", cast(int) small.length, small.ptr,
            cast(int) unit.length, unit.ptr, cast(int) medium.length, medium.ptr,
            cast(int) intText.length, intText.ptr, cast(int) full.length, full.ptr,
            cast(int) suffix.length, suffix.ptr, format.toHighHexDigit(cast(int) value),
            format.toLowHexDigit(cast(int) value), decoded, cast(int)(format.isUpperCase()
                && HexFormat.isHexDigit(codePoint)));
    return 0;
}
