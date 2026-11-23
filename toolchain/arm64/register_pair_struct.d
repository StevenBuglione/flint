// A dynamic array parameter in a register pair whose address is taken.
TTo[] arrCast(TFrom, TTo)(return scope TFrom[] from) @trusted
{
    struct Array { size_t length; void* ptr; }
    auto a = cast(Array*)&from;
    a.length = from.length * TFrom.sizeof / TTo.sizeof;
    return *cast(TTo[]*)a;
}

int main()
{
    byte[int.sizeof * 3] b = cast(byte) 0xab;
    int[] i = arrCast!(byte, int)(b);
    if (i.length != 3 || i.ptr !is cast(void*)b.ptr) return 1;
    foreach (v; i) if (v != cast(int)0xabab_abab) return 2;
    return 0;
}
