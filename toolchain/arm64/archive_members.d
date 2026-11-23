// dmd -lib writes Mach-O archives whose members start at 8 byte aligned offsets, which
// the 64-bit Apple linker requires. The library is built from archive_members/ (run.py).
module archive_members_test;

import archive_members.m1, archive_members.m22, archive_members.m333, archive_members.m4444;

int main()
{
    if (first(1) != 2 || second(3) != 6 || table[36] != 7) return 1;
    if (third(5.0) != 2.5 || name() != "third member" || fourth(2, 3, 4) != 10) return 2;
    return 0;
}
