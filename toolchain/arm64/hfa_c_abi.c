/* C side of hfa_c_abi.d: homogeneous floating point aggregates of 3 and 4 elements are
   passed and returned in SIMD registers (AAPCS64). */
typedef struct { double x, y, w, h; } Rect;     /* like CGRect */
typedef struct { float r, g, b; } Rgb;
typedef struct { float v[4]; } F4;

Rect make_rect(double x, double y, double w, double h) { Rect r = { x, y, w, h }; return r; }
double rect_area(Rect r) { return r.w * r.h; }
Rect inset(double d, Rect r, int times)
{
    Rect s = { r.x + d * times, r.y + d * times, r.w - 2 * d * times, r.h - 2 * d * times };
    return s;
}
Rgb make_rgb(float r, float g, float b) { Rgb c = { r, g, b }; return c; }
float rgb_sum(Rgb c, float extra) { return c.r + c.g + c.b + extra; }
F4 f4_scale(F4 a, float s) { F4 r; for (int i = 0; i < 4; ++i) r.v[i] = a.v[i] * s; return r; }

/* defined in D */
Rect d_rect(double x);
double d_area(Rect r, double scale);
double call_d(void) { Rect r = d_rect(2); return d_area(r, 10) + r.x; }
