module archive_members.m1;
int first(int x) { return x + 1; }
int extra_a() { return 5; }   // sizes the symbol table so that a 4 byte padded one misaligns the members
