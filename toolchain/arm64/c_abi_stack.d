// Stack arguments take 8-byte slots (AAPCS64), checked against C in both directions.
struct S3 { ubyte a, b, c; }
struct S12 { int a, b, c; }
extern (C) long cfun(long a, long b, long c, long d, long e, long f, long g, long h, int i, S3 s, short j, S12 t, ubyte k);
extern (C) long callD();
extern (C) long dfun(long a, long b, long c, long d, long e, long f, long g, long h, int i, S3 s, short j, S12 t, ubyte k)
{
    return a + h + i + s.a * 100 + s.c + j + t.a + t.c * 1000 + k;
}

int main()
{
    const want = 1 + 8 + 9 + 100 + 3 - 10 + 11 + 13000 + 14;
    if (cfun(1, 2, 3, 4, 5, 6, 7, 8, 9, S3(1, 2, 3), -10, S12(11, 12, 13), 14) != want) return 1;
    if (callD() != want) return 2;
    return 0;
}
