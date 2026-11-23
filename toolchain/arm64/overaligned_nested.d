// Over-aligned frames (align(32) members) address locals from SP; other base
// registers, such as the closure pointer, stay as they are.
int main()
{
    int i;
    struct Nested { align(32) int[3] stuff = [0, 1, 2]; ~this() { ++i; } }
    static struct NotNested { int before = 42; align(Nested.alignof * 4) Nested n; long after = 43; }
    {
        auto a = NotNested(1, Nested([3, 4, 5]), 2);
        if (a.before != 1 || a.after != 2 || a.n.stuff[1] != 4) return 1;
    }
    return i == 1 ? 0 : 3;   // a.n was destroyed (the temporary was moved into it)
    // (DMD does not align a nested struct member to 128 on x86-64 either: not tested)
}
