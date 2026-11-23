// Static data referenced directly (a cast string literal) is addressed with ADRP.
int sum(ubyte[16] a) { int s; foreach (b; a) s += b; return s; }

int main()
{
    if (sum(cast(ubyte[16]) x"00112233445566778899aabbccddeeff") != 2040) return 1;
    ubyte[16] d = cast(ubyte[16]) x"0102030405060708090a0b0c0d0e0f10";
    return sum(d) == 136 ? 0 : 2;
}
