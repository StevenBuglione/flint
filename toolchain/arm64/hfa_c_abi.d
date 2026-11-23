// Homogeneous floating point aggregates (HFAs) of 3 and 4 float or double elements go in
// as many SIMD registers in C calls, as arguments and as results (AAPCS64), like CGRect in
// Objective-C calls. Calls from D to C and from C to D, mixed with other arguments.
struct Rect { double x, y, w, h; }
struct Rgb { float r, g, b; }
struct F4 { float[4] v; }

extern(C) Rect make_rect(double x, double y, double w, double h);
extern(C) double rect_area(Rect r);
extern(C) Rect inset(double d, Rect r, int times);
extern(C) Rgb make_rgb(float r, float g, float b);
extern(C) float rgb_sum(Rgb c, float extra);
extern(C) F4 f4_scale(F4 a, float s);
extern(C) double call_d();

extern(C) Rect d_rect(double x) { return Rect(x, x + 1, x * 3, x * 4); }
extern(C) double d_area(Rect r, double scale) { return r.w * r.h * scale; }

struct Holder { int pad; Rect r; }

int main()
{
    Rect r = make_rect(1, 2, 3, 4);
    if (r.x != 1 || r.y != 2 || r.w != 3 || r.h != 4) return 1;
    if (rect_area(r) != 12) return 2;
    Rect s = inset(0.5, r, 2);
    if (s.x != 2 || s.y != 3 || s.w != 1 || s.h != 2) return 3;
    Rgb c = make_rgb(0.25f, 0.5f, 1);
    if (c.r != 0.25f || c.b != 1 || rgb_sum(c, 2) != 3.75f) return 4;
    F4 f = f4_scale(F4([1, 2, 3, 4]), 2);
    if (f.v != [2.0f, 4, 6, 8]) return 5;
    if (call_d() != 6 * 8 * 10 + 2) return 6;
    Holder h;
    h.r = make_rect(5, 6, 7, 8);                 // constructed into a field
    if (h.pad != 0 || h.r.h != 8) return 7;
    auto fp = &make_rect;
    if (fp(1, 1, 2, 5).h != 5) return 8;
    if (d_area(d_rect(1), 2) != 3 * 4 * 2) return 9;   // D to D, extern(C)
    return 0;
}
