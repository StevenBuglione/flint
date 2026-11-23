// alloca() is expanded inline and evaluates its argument once.
import core.stdc.stdlib : alloca;

double f(size_t n)
{
    auto p = cast(double*) alloca(n * double.sizeof);
    p[0 .. n] = 0;
    double s = 0;
    foreach (i; 0 .. n) { p[i] = i; s += p[i]; }
    return s;
}

int main()
{
    return f(10) == 45 && f(1000) == 499500 ? 0 : 1;
}
