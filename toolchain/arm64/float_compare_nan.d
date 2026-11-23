// Floating point comparisons with operands swapped and with NaN.
bool lt(double a, double b) { return a < b; }
bool le(double a, double b) { return a <= b; }
bool gt(double a, double b) { return a > b; }
bool ge(double a, double b) { return a >= b; }
bool ne(float a, float b) { return a != b; }

int main()
{
    double nan = double.nan;
    if (!lt(1, 2) || lt(2, 1) || lt(nan, 1) || lt(1, nan)) return 1;
    if (!le(2, 2) || le(nan, nan)) return 2;
    if (!gt(3, 2) || gt(nan, 1) || gt(1, nan)) return 3;
    if (!ge(2, 2) || ge(nan, 0)) return 4;
    if (!ne(float.nan, float.nan) || ne(1, 1)) return 5;
    return 0;
}
