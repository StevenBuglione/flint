// DWARF exception handling: catch, rethrow, finally, scope(exit), nested functions.
class E1 : Exception { this(string m) { super(m); } }
int finallies;

void thrower(int n)
{
    scope(exit) ++finallies;
    if (n == 1) throw new E1("one");
    if (n == 2) throw new Exception("two");
}

int depth(int n) { if (n == 0) thrower(1); return depth(n - 1) + 1; }

int main()
{
    int caught;
    try thrower(1); catch (E1 e) { if (e.msg == "one") ++caught; }
    try thrower(2); catch (E1 e) { return 1; } catch (Exception e) { ++caught; }
    try { try thrower(1); finally ++finallies; } catch (Exception e) { ++caught; }
    try depth(20); catch (E1) { ++caught; }
    thrower(0);
    return caught == 4 && finallies == 6 ? 0 : 2;
}
