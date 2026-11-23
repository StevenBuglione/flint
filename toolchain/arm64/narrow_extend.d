// Sign and zero extension of narrow integers: loads into 64-bit registers,
// shift-assign on a short, and 64-bit constants in register variables.
long widen(long v) { return v; }
long fromByte(byte b) { return widen(b); }
long fromShort(short s) { return widen(s); }
int indexByte(byte* p, size_t i) { return p[i]; }
short shiftBack(ubyte bf) { auto result = cast(short) (bf >> 4U); result <<= 12U; result >>= 12U; return result; }

size_t firstAtLeast(int[] r, int limit)
{
    size_t lessI = size_t.max;
    while (r[++lessI] < limit) {}
    return lessI;
}

int main()
{
    if (fromByte(-9) != -9 || fromShort(-300) != -300) return 1;
    byte[4] a = [1, -2, 3, -4];
    if (indexByte(a.ptr, 3) != -4) return 2;
    if (shiftBack(0x81) != -8) return 3;
    int[4] r = [1, 7, 3, 9];
    if (firstAtLeast(r[], 5) != 1) return 4;
    short s = 32767; s += 1;
    if (s != -32768) return 5;
    return 0;
}
