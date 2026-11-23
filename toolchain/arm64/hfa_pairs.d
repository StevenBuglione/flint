// Homogeneous float aggregates of one or two elements travel in SIMD registers;
// larger ones follow the general aggregate rules.
struct F2 { float a, b; }
struct D2 { double a, b; }
struct D3 { double a, b, c; }
struct F4 { float a, b, c, d; }
struct D1 { double x; }

F2 mkf2(float v) { return F2(v, v * 2); }
D2 mkd2(double v) { return D2(v, -v); }
D3 mk3(double v) { return D3(v, v + 1, v + 2); }
F4 mkf4(float v) { return F4(v, v + 1, v + 2, v + 3); }
D1 mk1(double v) { return D1(v * 2); }
double use(F2 a, D2 b, D3 c, F4 d, D1 e) { return a.a + a.b + b.a + b.b + c.a + c.c + d.a + d.d + e.x; }

int main()
{
    auto a = mkf2(1.5f);
    auto b = mkd2(3);
    auto c = mk3(10);
    auto d = mkf4(100);
    auto e = mk1(4);
    if (a.b != 3 || b.b != -3 || c.c != 12 || d.d != 103 || e.x != 8) return 1;
    return use(a, b, c, d, e) == 1.5 + 3 + 0 + 10 + 12 + 100 + 103 + 8 ? 0 : 2;
}
