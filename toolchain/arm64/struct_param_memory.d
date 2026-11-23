// Structs with a destructor (and static arrays of them) are passed in memory.
// The argument must be copied into the outgoing stack area, whatever produces it:
// a variable, a pointer, a call, a literal, or a register pair variable.
__gshared int dtors;

struct S(size_t N)
{
    ubyte[N] b;
    ~this() { ++dtors; }
}

S!N make(size_t N)(ubyte seed)
{
    S!N s;
    foreach (i, ref x; s.b)
        x = cast(ubyte)(seed + i);
    return s;
}

int sum(size_t N)(S!N s, int extra)
{
    int r = extra;
    foreach (x; s.b)
        r += x;
    return r;
}

int expect(size_t N)(ubyte seed, int extra)
{
    int r = extra;
    foreach (i; 0 .. N)
        r += cast(ubyte)(seed + i);
    return r;
}

int sumArr(T)(T[1] a) { return sum(a[0], 0); }

int test(size_t N)()
{
    auto v = make!N(3);
    if (sum(v, 1) != expect!N(3, 1)) return 1;          // variable
    auto p = &v;
    if (sum(*p, 2) != expect!N(3, 2)) return 2;         // through a pointer
    if (sum(make!N(5), 3) != expect!N(5, 3)) return 3;  // call result
    if (sumArr([make!N(7)]) != expect!N(7, 0)) return 4; // static array literal
    S!N[1] a = [v];
    if (sumArr(a) != expect!N(3, 0)) return 5;
    return 0;
}

int main()
{
    if (auto r = test!1()) return r;
    if (auto r = test!3()) return 10 + r;
    if (auto r = test!8()) return 20 + r;
    if (auto r = test!12()) return 30 + r;
    if (auto r = test!16()) return 40 + r;
    if (auto r = test!24()) return 50 + r;
    if (auto r = test!63()) return 60 + r;
    if (auto r = test!200()) return 70 + r;
    return dtors > 0 ? 0 : 99;
}
