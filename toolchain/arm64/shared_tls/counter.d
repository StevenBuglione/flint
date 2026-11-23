// The shared library of shared_tls.d: thread-local variables in position-independent code (compiled -fPIC -betterC)
module counter;

int counter;                    // thread-local, zero-initialised
int[4] block = [1, 2, 3, 4];    // thread-local, initialised

extern (C) int bump() { return ++counter; }

extern (C) int blockSum()
{
    int sum;
    foreach (b; block)
        sum += b;
    return sum;
}
