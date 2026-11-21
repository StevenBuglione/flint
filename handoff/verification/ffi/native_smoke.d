module flint.verify.native_smoke;
import flint.native_abi_probe : queryAbi;
extern(C) int flint_native_smoke() @system nothrow @nogc;
// SAFETY: The test C function takes no pointers, owns all of its buffers, and
// reports status. It retains no D reference and does not invoke D callbacks.
private int nativeSmoke() @trusted nothrow @nogc { return flint_native_smoke(); }
void main() @safe {
    const abi = queryAbi();
    assert(abi.abiVersion == 1 && abi.structBytes == 48);
    assert(abi.pointerBytes == (void*).sizeof && abi.sizeTBytes == size_t.sizeof);
    assert(abi.littleEndian == 1 && abi.llhttpBytes > 0);
    assert(nativeSmoke() == 0);
}
