// Results larger than 16 bytes are returned in memory, at an address passed in x8 (AAPCS64).
// x0 holds the first argument as usual, and the address is not returned. Both directions
// between C and D, member functions (whose interface thunks adjust 'this' in x0), and
// results constructed directly into a field.
struct Big { long a, b, c; }

extern(C) Big make_big(long x);
extern(C) Big shift_big(Big in_, long d);
extern(C) long call_d_make(long x);

extern(C) Big d_make(long x) { return Big(x, x + 1, x + 2); }

interface Maker { Big make(long x); }
class Doubler : Maker
{
    long base = 100;
    Big make(long x) { return Big(base + x, base + 2 * x, base + 3 * x); }
}

struct Holder { long pad; Big big; }

// Its own result address arrives in x8, which the call it makes does not preserve.
pragma(inline, false) Big forward(Big function(long) f, long x) { return f(x); }
Big viaD(long x) { return Big(x, x, x); }

int main()
{
    Big b = make_big(5);
    if (b.a != 5 || b.b != 10 || b.c != 15) return 1;
    b = shift_big(b, 1);
    if (b.a != 6 || b.b != 11 || b.c != 16) return 2;
    if (call_d_make(10) != 33) return 3;
    Holder h;
    h.big = make_big(7);                 // constructed into the field
    if (h.pad != 0 || h.big.c != 21) return 4;
    Maker m = new Doubler;
    Big r = m.make(1);                   // through the interface thunk
    if (r.a != 101 || r.b != 102 || r.c != 103) return 5;
    Big f = forward(&viaD, 4);
    if (f.a != 4 || f.c != 4) return 6;
    return 0;
}
