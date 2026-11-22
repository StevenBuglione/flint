module toolchain_flags;

@safe:
private int transform(int value) nothrow @nogc
{
    return value * 3 + 1;
}

extern (C) int main() nothrow @nogc
{
    return transform(7) == 22 ? 0 : 1;
}
