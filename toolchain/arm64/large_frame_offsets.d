// Locals at offsets the load/store immediates cannot reach directly: a merged 8-byte
// store at a misaligned offset of 256 or more, and offsets beyond 4095.
uint sumLiteral(uint seed)
{
    ubyte[300] pad = cast(ubyte) seed;
    dchar[8] word = ['o', 'l', 'l', 'e', 'h', 'x', 'y', 'z'];   // 'l','l' stored together
    uint s = pad[299];
    foreach (c; word) s += c;
    return s;
}

ulong far(ulong v)
{
    ubyte[5000] big = void;
    big[] = 0;
    big[4100] = cast(ubyte) v;
    *cast(uint*)&big[4996] = 7;
    ulong[2] tail = [v, v + 1];
    return big[4100] + *cast(uint*)&big[4996] + tail[1];
}

int main()
{
    if (sumLiteral(3) != 3 + 'o' + 'l' + 'l' + 'e' + 'h' + 'x' + 'y' + 'z') return 1;
    return far(9) == 9 + 7 + 10 ? 0 : 2;
}
