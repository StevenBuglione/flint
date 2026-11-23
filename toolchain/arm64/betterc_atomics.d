// core.atomic on AArch64 needs no runtime library: -betterC programs use it and link without
// druntime (run.py links betterc_* tests that way). Every size, every operation (pause() is
// not a template, so it needs druntime here as on x86-64).
import core.atomic;

struct Pair { ulong a, b; }

extern(C) int main()
{
    shared ubyte b = 1; shared ushort h = 2; shared uint w = 3; shared ulong x = 4;
    if (atomicLoad(b) != 1 || atomicLoad(h) != 2 || atomicLoad(w) != 3 || atomicLoad(x) != 4) return 1;
    atomicStore(b, cast(ubyte) 250); atomicStore(x, 1UL << 40);
    if (atomicLoad(b) != 250 || atomicLoad(x) != 1UL << 40) return 2;
    if (atomicFetchAdd(b, 10) != 250 || atomicLoad(b) != 4) return 3;          // wraps
    if (atomicOp!"+="(w, 5) != 8 || atomicOp!"-="(h, 3) != ushort.max) return 4;
    if (atomicExchange(&x, 7UL) != 1UL << 40 || atomicLoad(x) != 7) return 5;
    ulong expected = 6;
    if (cas(&x, expected, 9UL) || atomicLoad(x) != 7) return 6;               // fails
    if (!cas(&x, 7UL, 9UL) || atomicLoad(x) != 9) return 7;
    ushort hv = 1;
    if (cas(&h, &hv, cast(ushort) 3) || hv != ushort.max) return 8;  // reports the value
    static if (has128BitCAS)
    {
        shared Pair p = Pair(1, 2);
        Pair old = atomicLoad(p);
        if (old.a != 1 || old.b != 2) return 9;
        if (!cas(&p, Pair(1, 2), Pair(3, 4))) return 10;
        if (cas(&p, Pair(1, 2), Pair(5, 6))) return 11;
        atomicStore(p, Pair(7, 8));
        if (atomicLoad(p).b != 8) return 12;
    }
    atomicFence();
    return 0;
}
