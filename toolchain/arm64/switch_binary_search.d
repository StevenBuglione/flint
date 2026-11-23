// With -O, a switch of 4 or more cases is a binary search. Case values that do not
// fit a CMP immediate (negative or large ones) are compared through a register,
// and the "greater than" branch must compare the switch value with the case.
pragma(inline, false) int small(int e)
{
    switch (e)
    {
        case 1: return 10;
        case 2: return 20;
        case -1: return 30;
        case -2: return 40;
        case -3: return 50;
        case -4: return 60;
        case -5: return 70;
        case -6: return 80;
        default: return 0;
    }
}

pragma(inline, false) int big(long e)
{
    switch (e)
    {
        case 5000: return 1;
        case 70000: return 2;
        case 0x1234_5678_9ABC: return 3;
        case -9000: return 4;
        case -1: return 5;
        case 3: return 6;
        default: return 0;
    }
}

int main()
{
    static immutable int[2][] t = [[1, 10], [2, 20], [-1, 30], [-2, 40], [-3, 50], [-4, 60], [-5, 70], [-6, 80], [7, 0], [-7, 0]];
    foreach (p; t)
        if (small(p[0]) != p[1]) return 1;
    static immutable long[2][] u = [[5000, 1], [70000, 2], [0x1234_5678_9ABC, 3], [-9000, 4], [-1, 5], [3, 6], [4, 0], [-2, 0]];
    foreach (p; u)
        if (big(p[0]) != p[1]) return 2;
    return 0;
}
