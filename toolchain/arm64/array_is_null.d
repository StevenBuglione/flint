// An array is null only if both halves are: `is null`, `!a` and `if (a)` on an empty
// slice with a non-null pointer, as on x86-64.
int main()
{
    char[] a = "x\n".dup;
    char[] b = a[0 .. 0];
    char[] n;
    bool r1 = b is null, r2 = n is null, r3 = a is null, r4 = !b, r5 = !n;
    if (r1 || !r2 || r3 || r4 || !r5) return 1;
    if (b) {} else return 2;
    if (n) return 3;
    return 0;
}
