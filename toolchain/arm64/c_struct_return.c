/* C side of c_struct_return.d: results larger than 16 bytes are returned through the
   address the caller passes in x8 (AAPCS64), not x0. */
typedef struct { long a, b, c; } Big;

Big make_big(long x) { Big r = { x, x * 2, x * 3 }; return r; }
Big shift_big(Big in, long d) { Big r = { in.a + d, in.b + d, in.c + d }; return r; }

Big d_make(long x);   /* defined in D */
long call_d_make(long x) { Big b = d_make(x); return b.a + b.b + b.c; }
