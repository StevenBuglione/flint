// ImportC: DMD preprocesses importc_preprocess/cfuns.c with the C compiler driver, without
// -m64 for AArch64 (GCC for AArch64 has no such switch). The C file is in the test's library.
module importc_preprocess_test;

extern(C) int scaled(int x);

int main()
{
    return scaled(14) == 42 ? 0 : 1;
}
