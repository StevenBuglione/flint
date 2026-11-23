// real is double on AArch64: constants, array fills and comparisons use 8 bytes.
int cmpd(scope const real[] a, scope const real[] b)
{
    foreach (i; 0 .. a.length < b.length ? a.length : b.length)
    {
        if (a[i] < b[i]) return -1;
        if (a[i] > b[i]) return 1;
    }
    return 0;
}

real half(real x) { return x / 2; }

int main()
{
    static assert(real.sizeof == 8 && real.mant_dig == 53);
    real[2] a = [real.max, real.max];
    real[3] b = real.min_normal;
    if (a[1] != double.max || b[2] != double.min_normal) return 1;
    if (cmpd(a[], b[]) != 1 || cmpd(b[], a[]) != -1) return 2;
    creal c = 1.5L + 2.5Li;
    if (c.re != 1.5 || c.im != 2.5) return 3;
    return half(3.0L) == 1.5 ? 0 : 4;
}
