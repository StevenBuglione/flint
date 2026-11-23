// A register variable changed by ++/-- must not still be taken for the constant it was
// initialized to: std.format printed one digit too many for "%.3e" of negative longs.
size_t digitEnd(ulong arg, bool negative, char spec, int precision)
{
    char[64] digits = void;
    size_t pos = digits.length - 1;
    do { digits[pos--] = cast(char)('0' + arg % 10); arg /= 10; } while (arg > 0);
    char[3] prefix = void;
    size_t left = 2;
    size_t right = 2;
    if (negative)
        prefix[right++] = '-';
    size_t end = pos + precision + ((spec == 'g' || spec == 'G') ? 1 : 2);
    return end + (right - left) * 100 + digits[pos + 1] - '0';
}

int main()
{
    if (digitEnd(9223372036854775808UL, true, 'e', 3) != 49 + 100 + 9) return 1;
    if (digitEnd(9223372036854775808UL, false, 'e', 3) != 49 + 9) return 2;
    return digitEnd(42, true, 'g', 3) == 65 + 100 + 4 ? 0 : 3;
}
