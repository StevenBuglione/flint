// A shared library's thread-local variables are its own, per thread, and leave the executable's alone. The AArch64
// back end addressed a module's own TLS with local-exec offsets even under -fPIC, which in a library address the
// executable's block: bump() returned 12 and 13 here and overwrote mine[0].
import core.thread : Thread;

extern (C) int bump();
extern (C) int blockSum();

long[4] mine = [11, 22, 33, 44];   // the executable's own thread-local data

int main()
{
    if (bump() != 1 || bump() != 2)
        return 1;
    if (mine != [11, 22, 33, 44])
        return 2;
    if (blockSum() != 10)
        return 3;
    int a, b;
    auto t1 = new Thread({ foreach (i; 0 .. 3) a = bump(); });
    auto t2 = new Thread({ foreach (i; 0 .. 5) b = bump(); });
    t1.start();
    t2.start();
    t1.join();
    t2.join();
    if (a != 3 || b != 5)               // each thread counts in its own copy
        return 4;
    if (bump() != 3 || mine != [11, 22, 33, 44])
        return 5;
    return 0;
}
