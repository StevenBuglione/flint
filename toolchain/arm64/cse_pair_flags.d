// A common subexpression held in a register pair (a slice) and reloaded only to set the
// condition flags: on AArch64 the flags bit lies among the odd (MSW) registers, so it was
// taken for the register to load the high half into, leaving none to allocate (the inliner
// makes the same `s is null || s.length == 0` test of the same literal twice).
__gshared int interned;
pragma(inline, false) string internSlow(const(ubyte)[] bytes) { ++interned; return cast(string) bytes; }
string intern(const(ubyte)[] str)
{
    if (str is null || str.length == 0)
        return "";
    return internSlow(str);
}
__gshared string a, b, c;
string tlsA, tlsB;

int main()
{
    a = intern(cast(const(ubyte)[]) "this");
    b = intern(cast(const(ubyte)[]) "this");
    c = intern(null);
    tlsA = intern(cast(const(ubyte)[]) "that");
    tlsB = intern(cast(const(ubyte)[]) "that");
    if (a != "this" || b != "this" || c != "" || c.ptr is null) return 1;
    if (tlsA != "that" || tlsB != "that") return 2;
    if (interned != 4) return 3;
    return 0;
}
