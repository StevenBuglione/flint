// C-style, D-style and typesafe variadic functions (Apple AArch64 passes the
// variadic part of C-style and D-style calls on the stack, typesafe ones as a slice).
import core.stdc.stdarg;
import core.stdc.stdio : snprintf, vsnprintf;

extern (C) int cfmt(char* buf, size_t n, const char* fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    const r = vsnprintf(buf, n, fmt, ap);
    va_end(ap);
    return r;
}

int sum(int n, ...)
{
    va_list ap;
    va_start(ap, n);
    int s;
    foreach (i; 0 .. n)
        s += va_arg!int(ap);
    va_end(ap);
    return s + cast(int)_arguments.length * 100;
}

size_t total(size_t base, size_t[] bits...)
{
    foreach (b; bits) base += b;
    return base + bits.length * 1000;
}

int main()
{
    char[64] buf;
    cfmt(buf.ptr, buf.length, "%d %s %.1f", 42, "str".ptr, 2.5);
    if (buf[0 .. 11] != "42 str 2.5\0") return 1;
    if (sum(4, 1, 2, 3, 4) != 410) return 2;
    if (total(100, 0, 1, 31, 63, 85) != 5280) return 3;
    size_t extra = 7;
    size_t nested(size_t n, size_t[] bits...) { foreach (b; bits) n += b; return n + extra; }
    return nested(1, 2, 3) == 13 ? 0 : 4;
}
