// Callee-saved registers survive an exception caught below: the unwinder can only
// restore what the frames' CFI says they saved (x19-x28, d8-d15).
__gshared int sink;

void thrower(int n)
{
    long a = n, b = n * 3, c = n * 5, d = n * 7, e = n * 11, f = n * 13, g = n * 17, h = n * 19, i = n * 23, j = n * 29;
    double x = n * 0.5, y = n * 1.5, z = n * 2.5;
    foreach (k; 0 .. n) { a += b; b += c; c += d; d += e; e += f; f += g; g += h; h += i; i += j; j += a; x += y; y += z; z += x; }
    sink += cast(int)(a + b + c + d + e + f + g + h + i + j + x + y + z);
    if (n > 0) throw new Exception("x");
}

int catcher(int n)          // keeps nothing of its own in callee-saved registers
{
    try thrower(n);
    catch (Exception) return 1;
    return 0;
}

int main()
{
    long s1 = 1, s2 = 2, s3 = 3, s4 = 4, s5 = 5, s6 = 6;
    double f1 = 0.25, f2 = 0.5;
    int caught;
    foreach (k; 0 .. 4)
    {
        caught += catcher(k + 1);
        s1 += 1; s2 += 2; s3 += 3; s4 += 4; s5 += 5; s6 += 6; f1 += 1; f2 += 2;
    }
    return caught == 4 && s1 == 5 && s2 == 10 && s3 == 15 && s4 == 20 && s5 == 25 && s6 == 30 && f1 == 4.25 && f2 == 8.5 ? 0 : 1;
}
