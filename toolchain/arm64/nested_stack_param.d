// A nested function reads its parent's parameters through the frame base it is
// given. Parameters passed on the stack are just above that base on AArch64: the
// frame record (x29, x30) is below the locals, not between them and the parameters.
import core.lifetime : forward;

struct S { int n; this(this) { n++; } }   // a postblit: S[1] is passed in memory

struct W
{
    S[1] s;
    long extra;
    this(S[1] v) { s = __ctfe ? v : forward!v; }    // forward!v is a nested function reading v
    long member(long a, long b, long c, long d, long e, long f, long g, long h, long i, long j)
    {
        long get() { return i * 100 + j + extra; }      // nested function in a member function
        return get();
    }
}

long plain(long a, long b, long c, long d, long e, long f, long g, long h, long i, long j)
{
    long local = 5;
    pragma(inline, false) long get() { return i * 100 + j + local; }
    return get();
}

int main()
{
    S[1] a = [S(5)];
    auto w = W(a);
    if (w.s[0].n != 6) return 1;
    if (plain(1, 2, 3, 4, 5, 6, 7, 8, 9, 10) != 915) return 2;
    w.extra = 3;
    if (w.member(1, 2, 3, 4, 5, 6, 7, 8, 9, 10) != 913) return 3;
    return 0;
}
