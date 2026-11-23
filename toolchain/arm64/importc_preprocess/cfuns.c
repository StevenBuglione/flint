/* DMD runs the C preprocessor on this file (ImportC). For AArch64 it must not pass -m64,
   which GCC for AArch64 rejects. */
#define SCALE 3
int scaled(int x) { return x * SCALE; }
