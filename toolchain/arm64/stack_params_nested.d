// Parameters passed on the stack that live in registers and are referenced by
// a nested function (or by ref) are loaded in the prolog.
uint among(Value, Values...)(Value value, Values values)
{
    foreach (uint i, ref v; values)
        if (value == v) return i + 1;
    return 0;
}

long sum(long a, long b, long c, long d, long e, long f, long g, long h, byte i, short j, double k, ulong l)
{
    long delegate() dg = () => i + j + cast(long)k + l;
    return dg() + a + h;
}

int main()
{
    if (among('x', 'a','b','c','d','e','f','g','h','i','x') != 10) return 1;
    if (among('i', 'a','b','c','d','e','f','g','h','i','x') != 9) return 2;
    if (among(-3, 1,2,3,4,5,6,7,8,9,-3) != 10) return 3;
    if (among(1L, 1L,2L,3L,4L,5L,6L,7L,8L,9L,-3L) != 1) return 4;
    if (sum(1,2,3,4,5,6,7,8,-9,-300,2.5,1000) != 702) return 5;
    return 0;
}
