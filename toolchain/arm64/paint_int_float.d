// Reinterpreting register variables between integer and floating point.
double bits2d(ulong u) { ulong x = u ^ 1; x ^= 1; return *cast(double*)&x; }
ulong d2bits(double d) { double y = d * 1.0; return *cast(ulong*)&y; }
float bits2f(uint u) { uint x = u + 0; return *cast(float*)&x; }
uint f2bits(float f) { float y = f + 0.0f; return *cast(uint*)&y; }

int cmp(double x, double y)
{
    union R { double number; ulong bits; }
    R[2] vars = void;
    vars[0].number = x; vars[1].number = y;
    foreach (ref var; vars)
        if (var.bits & (1UL << 63)) var.bits = ~var.bits; else var.bits |= 1UL << 63;
    return vars[0].bits < vars[1].bits ? -1 : vars[0].bits > vars[1].bits ? 1 : 0;
}

int main()
{
    if (bits2d(0x4009_21FB_5444_2D18) != 0x1.921fb54442d18p+1) return 1;
    if (d2bits(2.5) != 0x4004_0000_0000_0000) return 2;
    if (bits2f(0x3fc0_0000) != 1.5f) return 3;
    if (f2bits(-1.0f) != 0xbf80_0000) return 4;
    if (cmp(1.0, 2.0) != -1 || cmp(-1.0, -2.0) != 1 || cmp(3.0, 3.0) != 0) return 5;
    return 0;
}
