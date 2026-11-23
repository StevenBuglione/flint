// The loop that copies a large struct changes its index register, which must not
// still be taken for the constant it was set to (here `false` for the setter).
struct Spec
{
    int width;
    long[8] payload;
    ubyte flags;
    void zero(bool v) { if (v) flags |= 2; else flags &= cast(ubyte) ~2; }
}

ubyte copyAndClear(scope const ref Spec f)
{
    Spec fs = f;
    fs.zero(false);
    return fs.flags;
}

int main()
{
    Spec s;
    s.flags = 1;
    return copyAndClear(s) == 1 ? 0 : 1;
}
