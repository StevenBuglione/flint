// Complex results from real, imaginary and complex operands.
cfloat mk(float re, ifloat im) { return re + im; }
cdouble mk2(double re, idouble im) { return re - im; }
cdouble mk3(cdouble c, double r) { return c + r; }
cdouble mk4(idouble i, cdouble c) { return i - c; }
cfloat mk5(ifloat i, float r) { return i + r; }

int main()
{
    auto a = mk(1.5f, 2.5fi), b = mk2(3, 4i), c = mk3(1 + 2i, 10), d = mk4(5i, 1 + 2i), f = mk5(7fi, 8);
    if (a.re != 1.5f || a.im != 2.5f) return 1;
    if (b.re != 3 || b.im != -4) return 2;
    if (c.re != 11 || c.im != 2) return 3;
    if (d.re != -1 || d.im != 3) return 4;
    if (f.re != 8 || f.im != 7) return 5;
    return 0;
}
