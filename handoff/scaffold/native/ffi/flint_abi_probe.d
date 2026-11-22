module flint.native_abi_probe;
struct AbiInfo {
    uint abiVersion, structBytes, pointerBytes, sizeTBytes;
    uint longBytes, littleEndian, llhttpBytes, llhttpAlignment;
    uint nghttp2NvBytes, nghttp2NvAlignment, curlOffTBytes, sqliteInt64Bytes;
}
static assert(AbiInfo.sizeof == 48);
extern(C) int flint_abi_probe(AbiInfo* output, size_t outputBytes) @system nothrow @nogc;
// SAFETY: The address names a live aligned stack object, the exact byte size is
// passed, and the pinned C probe writes at most that size without retaining it.
AbiInfo queryAbi() @trusted nothrow @nogc {
    AbiInfo result;
    const code = flint_abi_probe(&result, AbiInfo.sizeof);
    assert(code == 0);
    return result;
}
