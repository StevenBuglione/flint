// `real` is `double` in DMD's AArch64 back end, but C's `long double` is 128-bit on
// Linux AArch64. druntime binds the C library's long double functions to the double ones.
import core.stdc.math;
import core.stdc.stdlib : strtold;

int main()
{
    if (truncl(3.75L) != 3) return 1;
    if (floorl(-2.5L) != -3) return 2;
    if (sqrtl(16.0L) != 4) return 3;
    if (fabsl(-1.5L) != 1.5) return 4;
    if (lrintl(2.0L) != 2) return 5;
    if (fmodl(7.0L, 4.0L) != 3) return 6;
    int e;
    if (frexpl(8.0L, &e) != 0.5 || e != 4) return 7;
    if (strtold("2.5", null) != 2.5) return 8;
    if (nexttoward(1.0, 2.0L) <= 1.0) return 9;
    if (nexttowardf(1.0f, 2.0L) <= 1.0f || nexttowardf(1.0f, 0.0L) >= 1.0f) return 10;
    if (nexttowardf(1.0f, 1.0L) != 1.0f) return 11;
    char[1] empty = 0;
    if (!isnan(nanl(empty.ptr))) return 12;
    return 0;
}
