// Thread-local variables, members of a thread-local struct, and a global.
struct S { int a; long b; int[4] c; }
S tls;
int tlsInt = 7;
__gshared int g = 5;

int main()
{
    tls.b = 40;
    tls.c[3] = 2;
    tlsInt += g;
    int* p = &tls.c[3];
    return tls.b + *p + tlsInt == 54 ? 0 : 1;
}
