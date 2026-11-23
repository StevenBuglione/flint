struct S3 { unsigned char a, b, c; };
struct S12 { int a, b, c; };
long cfun(long a, long b, long c, long d, long e, long f, long g, long h, int i, struct S3 s, short j, struct S12 t, unsigned char k)
{
    return a + h + i + s.a * 100 + s.c + j + t.a + t.c * 1000 + k;
}
long dfun(long a, long b, long c, long d, long e, long f, long g, long h, int i, struct S3 s, short j, struct S12 t, unsigned char k);
long callD(void)
{
    struct S3 s = {1, 2, 3};
    struct S12 t = {11, 12, 13};
    return dfun(1, 2, 3, 4, 5, 6, 7, 8, 9, s, -10, t, 14);
}
